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
| ⌘B | Toggle the sidebar |
| ⌘1…⌘9 | Jump to vertical tab (group) by position |
| ⌘⇧[ / ⌘⇧] | Previous / next horizontal tab (terminal) |
| ⌘⌃[ / ⌘⌃] | Previous / next vertical tab (group) |
| ⌘Q | Quit (no confirmation) |

Holding ⌘ alone for half a second reveals each sidebar row's ⌘-digit
shortcut as a hint.

## Configuration

Text file at `~/.config/kterm/config` (`key = value`). `kterm-` keys configure
the app shell; everything else passes through to libghostty. See
[`config.example`](./config.example).

### Built-in options

Baked-in defaults (override by setting the same key in your config):

| Key | Default | Meaning |
| --- | --- | --- |
| `macos-option-as-alt` | `left` | Left ⌥ acts as Alt/Meta (e.g. for readline word-jump) |

`kterm-` keys (app shell, no libghostty default):

| Key | Default | Meaning |
| --- | --- | --- |
| `kterm-sidebar-width` | `160` | Width of the vertical tab sidebar, in points |

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
   ├─ Sidebar          vertical tabs (groups)        ⌘N adds, ⌘B toggles, resizable
   └─ VStack
      ├─ TabStrip      horizontal tabs (terminals)   ⌘T adds, ⌘W closes, scrolls on overflow
      └─ SurfaceView   the active libghostty terminal
```

Tab titles track each terminal's working directory (via `GHOSTTY_ACTION_PWD`).
