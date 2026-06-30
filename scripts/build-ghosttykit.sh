#!/usr/bin/env bash
# Build GhosttyKit.xcframework from the pinned `ghostty/` submodule.
# Downloads the exact Zig toolchain ghostty requires (0.15.2) into .zig-toolchain/
# if a matching `zig` is not already on PATH, then emits the universal xcframework.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ZIG_VERSION="0.15.2"   # must match ghostty/build.zig.zon minimum_zig_version
ZIG_DIR="$REPO_ROOT/.zig-toolchain"

# --- ensure submodule is checked out ---
if [ ! -f "ghostty/build.zig" ]; then
  echo "==> Initializing ghostty submodule..."
  git submodule update --init ghostty
fi

# --- resolve a Zig 0.15.2 binary ---
ZIG_BIN=""
if command -v zig >/dev/null 2>&1 && [ "$(zig version)" = "$ZIG_VERSION" ]; then
  ZIG_BIN="$(command -v zig)"
elif [ -x "$ZIG_DIR/zig" ] && [ "$("$ZIG_DIR/zig" version)" = "$ZIG_VERSION" ]; then
  ZIG_BIN="$ZIG_DIR/zig"
else
  arch="$(uname -m)"   # arm64 -> aarch64
  [ "$arch" = "arm64" ] && arch="aarch64"
  tarball="zig-${arch}-macos-${ZIG_VERSION}.tar.xz"
  url="https://ziglang.org/download/${ZIG_VERSION}/${tarball}"
  echo "==> Downloading Zig ${ZIG_VERSION} (${arch})..."
  rm -rf "$ZIG_DIR" && mkdir -p "$ZIG_DIR"
  tmp="$(mktemp -d)"
  if command -v aria2c >/dev/null 2>&1; then
    aria2c -q -d "$tmp" -o "$tarball" "$url"
  else
    curl -fsSL -o "$tmp/$tarball" "$url"
  fi
  tar -xf "$tmp/$tarball" -C "$ZIG_DIR" --strip-components=1
  rm -rf "$tmp"
  ZIG_BIN="$ZIG_DIR/zig"
fi
echo "==> Using zig: $ZIG_BIN ($("$ZIG_BIN" version))"

# --- pick an SDK Zig 0.15.2 can parse ---
# macOS 26 (Tahoe) ships .tbd files that Zig 0.15.2 cannot parse, so every libc
# symbol comes back undefined ("undefined symbol: _waitpid", etc.) — even when
# compiling Zig's own build runner. Zig locates the SDK by shelling out to
# `xcrun --show-sdk-path`, and it ignores SDKROOT / --sysroot for the build
# runner. The macOS 15 SDK bundled with the Command Line Tools links cleanly,
# so we shadow `xcrun` on PATH to hand Zig that older SDK for the whole build.
SDK=""
for cand in \
  /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk \
  /Library/Developer/CommandLineTools/SDKs/MacOSX15.*.sdk \
  /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15*.sdk
do
  [ -d "$cand" ] && { SDK="$cand"; break; }
done

SHIM_DIR="$(mktemp -d)"

if [ -n "$SDK" ]; then
  echo "==> Pinning Zig's macOS SDK to: $SDK"
  cat > "$SHIM_DIR/xcrun" <<EOF
#!/bin/bash
for a in "\$@"; do
  [ "\$a" = "--show-sdk-path" ] && { echo "$SDK"; exit 0; }
done
exec /usr/bin/xcrun "\$@"
EOF
  chmod +x "$SHIM_DIR/xcrun"
else
  echo "==> WARNING: no macOS 15 SDK found; building against default SDK (may fail on macOS 26)." >&2
fi

# Apple's `libtool -static` SILENTLY DROPS members when merging multiple
# archives that share member basenames (e.g. several deps ship a `base64.o` /
# `compiler_rt.o`). Ghostty's xcframework step merges ~15 archives that way, so
# the resulting libghostty-fat.a comes out missing the main object and many
# dependencies. We shadow `libtool` to instead explode every input archive into
# uniquely-named objects and re-archive those, which preserves everything. It
# also stashes the combined lib at $KTERM_FATLIB_DEST so we can build the
# xcframework ourselves below (Zig's own xcframework step is entangled with the
# Ghostty.app build, which fails to link in this toolchain).
FATLIB_DEST="$REPO_ROOT/.ghostty-build/libghostty-fat.a"
rm -rf "$REPO_ROOT/.ghostty-build" && mkdir -p "$REPO_ROOT/.ghostty-build"
cat > "$SHIM_DIR/libtool" <<EOF
#!/bin/bash
KTERM_FATLIB_DEST="$FATLIB_DEST"
EOF
cat >> "$SHIM_DIR/libtool" <<'EOF'
if [ "$1" = "-static" ]; then
  base="$PWD"
  shift
  out=""; inputs=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -o) out="$2"; shift 2 ;;
      *.a) inputs+=("$1"); shift ;;
      *) shift ;;   # ignore other flags
    esac
  done
  if [ -n "$out" ] && [ "${#inputs[@]}" -gt 0 ]; then
    tmp="$(mktemp -d)"; mkdir -p "$tmp/obj"; i=0
    for a in "${inputs[@]}"; do
      case "$a" in /*) abs="$a" ;; *) abs="$base/$a" ;; esac
      [ -f "$abs" ] || continue
      i=$((i+1)); d="$tmp/ex$i"; mkdir -p "$d"
      ( cd "$d" && ar x "$abs" 2>/dev/null && chmod +r ./* 2>/dev/null; rm -f __.SYMDEF* )
      pre="$(basename "$a" .a)"
      for o in "$d"/*.o; do
        [ -f "$o" ] && mv "$o" "$tmp/obj/${pre}__$(basename "$o")"
      done
    done
    /usr/bin/libtool -static -o "$out" "$tmp/obj"/*.o
    rc=$?
    # Stash the fully-combined ghostty lib for the script to package.
    if [ $rc -eq 0 ] && [ "$(basename "$out")" = "libghostty-fat.a" ] && [ -n "$KTERM_FATLIB_DEST" ]; then
      cp "$out" "$KTERM_FATLIB_DEST"
    fi
    rm -rf "$tmp"; exit $rc
  fi
fi
exec /usr/bin/libtool "$@"
EOF
chmod +x "$SHIM_DIR/libtool"

# --- ensure the Metal Toolchain is installed ---
# Ghostty compiles Metal shaders (.metal -> .metallib). On Xcode 26 the Metal
# Toolchain is a separate, downloadable component; without it the build fails
# with "cannot execute tool 'metal' due to missing Metal Toolchain".
if ! /usr/bin/xcrun -f metal >/dev/null 2>&1; then
  echo "==> Metal Toolchain missing; downloading (~700 MB, one time)..."
  /usr/bin/xcodebuild -downloadComponent MetalToolchain
fi

# --- build the ghostty static lib (deps + C API combined by our libtool shim) ---
echo "==> Building libghostty (this takes a few minutes)..."
(
  cd ghostty
  # `native` builds only this host's macOS arch (we don't ship iOS / Intel).
  # Zig's install/xcframework step also builds the full Ghostty.app, which can
  # fail to link in this toolchain — we don't need it. Our libtool shim has
  # already stashed the combined lib by then, so we ignore the exit code.
  PATH="$SHIM_DIR:$PATH" "$ZIG_BIN" build \
    -Demit-xcframework=true \
    -Dxcframework-target=native \
    -Doptimize=ReleaseFast || echo "==> zig build returned non-zero (expected: the Ghostty.app step); checking lib..."
)
rm -rf "$SHIM_DIR"

[ -f "$FATLIB_DEST" ] || {
  echo "Error: combined libghostty-fat.a was not produced (libtool shim did not run — clear ghostty/.zig-cache and retry)" >&2
  exit 1
}

# --- assemble the xcframework ourselves ---
echo "==> Packaging GhosttyKit.xcframework..."
rm -rf "$REPO_ROOT/GhosttyKit.xcframework"
/usr/bin/xcodebuild -create-xcframework \
  -library "$FATLIB_DEST" \
  -headers "$REPO_ROOT/ghostty/include" \
  -output "$REPO_ROOT/GhosttyKit.xcframework" >/dev/null
cp "$REPO_ROOT/ghostty/include/ghostty.h" "$REPO_ROOT/ghostty.h"
rm -rf "$REPO_ROOT/.ghostty-build"

LIB="$(find "$REPO_ROOT/GhosttyKit.xcframework" -name 'libghostty-fat.a' | head -1)"
# grep -c (not -q) consumes all of nm's output, avoiding a SIGPIPE that would
# trip `set -o pipefail`.
if [ "$(nm "$LIB" 2>/dev/null | grep -c ' T _ghostty_init' || true)" -eq 0 ]; then
  echo "Error: packaged xcframework is missing the ghostty C API" >&2
  exit 1
fi
echo "==> Done: GhosttyKit.xcframework + ghostty.h ready at repo root."
