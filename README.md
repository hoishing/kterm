# kterm

A ghostty-based macOS terminal with vertical tabs.

Minimal native shell: SwiftUI around `libghostty` (GPU-rendered Ghostty core).
Sidebar tabs only — no horizontal strip, no splits.

## Features

- **Vertical tabs:** each sidebar row is one terminal
- **Git branch in sidebar:** active tab's branch, refreshed on `cd` / `git checkout` and window focus
- **⌘-hold shortcut hints:** hold ⌘ to reveal each row's ⌘-digit shortcut
- **Terminal bell notifications:** BEL (`\a`) or OSC 9/777 raises a macOS notification even when kterm is backgrounded
- **In-app notification cues:** unread sidebar dot; static content-area border if the tab is on screen
  - Clears on select, return-to-foreground, or content interaction (keystroke/click)
- **Dock bounce when unfocused:** pings bounce the dock icon when kterm isn't active
- **Smart notification suppression:** OS banner + dock bounce only when you're not already looking at that tab; in-app markers still set
- **Click-to-focus notifications:** notification tap focuses the issuing tab (restores minimized windows)
- **Drag & drop files:** drop inserts a shell-escaped path (e.g. Claude Code `[Image #1]`)
- **Open a folder:** `open -a kterm <dir>` (or Finder / drop on icon) opens a new tab in that cwd in the current window
  - Cold launch still gets its first window

## Shortcuts

| Key | Action |
| --- | --- |
| ⌘T | New tab |
| ⌘W | Close the active tab |
| ⌘B | Toggle the sidebar |
| ⌘1…⌘9 | Jump to tab by position |
| ⌘⇧[ / ⌘⇧] | Previous / next tab |
| ⌘⇧N | New window |
| ⌘` | Cycle windows |
| ⌘Q | Quit (no confirmation) |

Hold ⌘ alone ~0.5s to reveal each sidebar row's ⌘-digit hint.

## Configuration

File: `~/.config/kterm/config` (`key = value`).

- `kterm-` keys: app shell
- Everything else: passed through to libghostty

See [`config.example`](./config.example).

### Built-in options

Defaults baked in (override in your config):

| Key | Default | Meaning |
| --- | --- | --- |
| `macos-option-as-alt` | `left` | Left ⌥ acts as Alt/Meta (e.g. readline word-jump) |

`kterm-` keys (app shell only):

| Key | Default | Meaning |
| --- | --- | --- |
| `kterm-sidebar-width` | `160` | Vertical tab sidebar width, points |
| `kterm-new-tab-position` | `after-current` | New ⌘T tab lands after current, or `end` to append |
| `kterm-font-ligatures` | `false` | Programming ligatures; `true` enables. Off maps to Ghostty `font-feature = -calt, -liga, -dlig` |

New tabs inherit the opener's cwd (libghostty `window-inherit-working-directory`).

## Addressing a tab

Each tab's shell gets `KTERM_TAB_ID`. Opening `kterm://focus-tab?id=<id>` raises that tab (same path as notification taps):

```sh
open "kterm://focus-tab?id=$KTERM_TAB_ID"
```

## Build

Needs Xcode (Metal Toolchain) and [XcodeGen](https://github.com/yonsm/XcodeGen).

```sh
git submodule update --init ghostty   # pinned ghostty source
./scripts/build-ghosttykit.sh         # GhosttyKit.xcframework (Zig 0.15.2; auto-downloaded)
xcodegen generate                     # kterm.xcodeproj from project.yml
xcodebuild -project kterm.xcodeproj -scheme kterm -configuration Release
```

`build-ghosttykit.sh`:

- Downloads the exact Zig toolchain
- Pins Zig's macOS SDK to the CLT macOS 15 SDK (Zig 0.15.2 can't parse macOS 26 SDK)
- Emits `GhosttyKit.xcframework` from `ghostty/`

## Layout

```
Window
└─ HStack
   ├─ Sidebar          vertical tabs                 ⌘T adds, ⌘B toggles, resizable
   └─ SurfaceView      the active libghostty terminal
```

Tab titles track each terminal's working directory (`GHOSTTY_ACTION_PWD`).
