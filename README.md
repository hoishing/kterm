# kterm

> a ghostty-based macOS terminal with vertical and horizontal tabs

A minimal native macOS terminal: a SwiftUI app shell around `libghostty` (the
real GPU-rendered Ghostty core). Two levels of tabs, no splits.

## Features

- **Two-level tabs** — vertical tabs (sidebar groups) and horizontal tabs
  (terminals within a group)
- **Git branch in sidebar** — shows the active tab's branch, refreshed on
  `cd`/`git checkout` and when the window regains focus
- **⌘-hold shortcut hints** — hold ⌘ to reveal each sidebar row's ⌘-digit
  shortcut
- **Terminal bell notifications** — a terminal bell (BEL / `\a`) raises a macOS
  notification, so a bell-based cue (e.g. a CLI tool set to notify via the
  terminal bell) surfaces even when kterm is in the background
- **Smart notification suppression** — bell/OSC 9/OSC 777 notifications fire
  only when you're not already looking at that exact tab
- **Click-to-focus notifications** — clicking a desktop notification brings
  kterm forward and focuses the exact tab that raised it (restoring the window
  if minimized)
- **Drag & drop files** — dropping a file (e.g. an image) onto the terminal
  inserts its shell-escaped path into the buffer, so tools like the Claude Code
  CLI can pick it up as `[Image #1]`
- **Open a folder** — `open -a kterm <dir>` (or Finder "Open With" / dropping a
  folder on the app icon) opens a new tab whose shell starts in that folder,
  reusing the current window rather than spawning a new one (a cold launch still
  gets its first window)

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
| `kterm-new-tab-position` | `after-current` | Where a new ⌘N/⌘T tab lands: `after-current` (right after the current tab, pushing the rest back) or `end` (append) |

New tabs inherit the working directory of the tab they were opened from
(honouring libghostty's `window-inherit-working-directory`).

## Addressing a tab

Each tab's shell gets a `KTERM_TAB_ID` environment variable holding that tab's
id. Opening `kterm://focus-tab?id=<id>` raises that tab (the mechanism behind
click-to-focus notifications), so a script can jump you back to its own tab:

```sh
open "kterm://focus-tab?id=$KTERM_TAB_ID"
```

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
