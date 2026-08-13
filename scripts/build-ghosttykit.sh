#!/usr/bin/env bash
# Build GhosttyKit.xcframework from the pinned `ghostty/` submodule.
# Downloads the exact Zig toolchain ghostty requires (0.16.0) into .zig-toolchain/
# if a matching `zig` is not already on PATH, then emits the native xcframework.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ZIG_VERSION="0.16.0"   # must match ghostty/build.zig.zon minimum_zig_version
ZIG_DIR="$REPO_ROOT/.zig-toolchain"

# --- ensure submodule is checked out ---
if [ ! -f "ghostty/build.zig" ]; then
  echo "==> Initializing ghostty submodule..."
  git submodule update --init ghostty
fi

# --- resolve a Zig 0.16.0 binary ---
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

# --- pick an SDK Zig 0.16.0 can parse ---
# macOS 26 (Tahoe) ships .tbd files that Zig 0.16.0 cannot parse, so every libc
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

# --- ensure the Metal Toolchain is installed ---
# Ghostty compiles Metal shaders (.metal -> .metallib). On Xcode 26 the Metal
# Toolchain is a separate, downloadable component; without it the build fails
# with "cannot execute tool 'metal' due to missing Metal Toolchain".
if ! /usr/bin/xcrun -f metal >/dev/null 2>&1; then
  echo "==> Metal Toolchain missing; downloading (~700 MB, one time)..."
  /usr/bin/xcodebuild -downloadComponent MetalToolchain
fi

# --- build Ghostty's native xcframework (libghostty-internal) ---
# Upstream now combines archives itself (ranlib-normalize + libtool) and
# rewrites compiler-rt so libc/libm bind to libSystem. We skip Ghostty.app.
echo "==> Building libghostty (this takes a few minutes)..."
(
  cd ghostty
  PATH="$SHIM_DIR:$PATH" "$ZIG_BIN" build \
    -Demit-xcframework=true \
    -Dxcframework-target=native \
    -Demit-macos-app=false \
    -Doptimize=ReleaseFast
)
rm -rf "$SHIM_DIR"

XCFW="$REPO_ROOT/ghostty/macos/GhosttyKit.xcframework"
[ -d "$XCFW" ] || {
  echo "Error: ghostty/macos/GhosttyKit.xcframework was not produced" >&2
  exit 1
}

echo "==> Packaging GhosttyKit.xcframework..."
rm -rf "$REPO_ROOT/GhosttyKit.xcframework"
cp -R "$XCFW" "$REPO_ROOT/GhosttyKit.xcframework"
cp "$REPO_ROOT/ghostty/include/ghostty.h" "$REPO_ROOT/ghostty.h"

# Compiled terminfo lives next to Contents/Resources/ghostty so libghostty
# can set TERMINFO=<resources>/../terminfo.
if [ -d "$REPO_ROOT/ghostty/zig-out/share/terminfo" ]; then
  rm -rf "$REPO_ROOT/Resources/terminfo"
  cp -R "$REPO_ROOT/ghostty/zig-out/share/terminfo" "$REPO_ROOT/Resources/terminfo"
fi

LIB="$(find "$REPO_ROOT/GhosttyKit.xcframework" -name '*.a' | head -1)"
# grep -c (not -q) consumes all of nm's output, avoiding a SIGPIPE that would
# trip `set -o pipefail`.
if [ "$(nm "$LIB" 2>/dev/null | grep -c ' T _ghostty_init' || true)" -eq 0 ]; then
  echo "Error: packaged xcframework is missing the ghostty C API" >&2
  exit 1
fi
echo "==> Done: GhosttyKit.xcframework + ghostty.h ready at repo root."
