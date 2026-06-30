# kterm

> a ghostty-based macOS terminal with vertical and horizontal tabs

A minimal native macOS terminal: a SwiftUI app shell around `libghostty` (the
real GPU-rendered Ghostty core). Two levels of tabs, no splits.

## Shortcuts

| Key | Action |
| --- | --- |
| ⌘N | New **vertical** tab (a new group in the left sidebar) |
| ⌘T | New **horizontal** tab (a new terminal in the current group) |
| ⌘W | Close the active tab |
| ⌘Q | Quit (no confirmation) |

## Configuration

Text file at `~/.config/kterm/config` (`key = value`). `kterm-` keys configure
the app shell; everything else passes through to libghostty. See
[`config.example`](./config.example).

## Build

Requires Xcode (with the Metal Toolchain component) and
[XcodeGen](https://github.com/yonsm/XcodeGen).

```sh
git submodule update --init ghostty   # the pinned ghostty source
./scripts/build-ghosttykit.sh         # builds GhosttyKit.xcframework (needs Zig 0.15.2; auto-downloaded)
xcodegen generate                     # generates kterm.xcodeproj from project.yml
xcodebuild -project kterm.xcodeproj -scheme kterm -configuration Release
```

`build-ghosttykit.sh` downloads the exact Zig toolchain, pins Zig's macOS SDK to
the Command Line Tools' macOS 15 SDK (Zig 0.15.2 can't parse the macOS 26 SDK),
and emits `GhosttyKit.xcframework` from the `ghostty/` submodule.

## Layout

```
Window
└─ HStack
   ├─ Sidebar          vertical tabs (groups)        ⌘N adds
   └─ VStack
      ├─ TabStrip      horizontal tabs (terminals)   ⌘T adds, ⌘W closes
      └─ SurfaceView   the active libghostty terminal
```
