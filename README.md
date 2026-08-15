# kterm

> a ghostty-based macOS terminal with vertical tabs, horizontal tabs, and splits

A minimal native macOS terminal: a SwiftUI app shell around `libghostty` (the
real GPU-rendered Ghostty core). Two levels of tabs, plus Ghostty-style pane
splits inside each horizontal tab.

## Features

- Two-level tabs: vertical tabs (sidebar groups) and horizontal tabs (split trees within a group)
- Pane splits: Ghostty-compatible `new_split` / `goto_split` / resize / equalize / zoom inside a horizontal tab
- Git branch in sidebar: active tab's branch plus Starship-style status (`[!?]` dirty/untracked, `[⇡]` ahead, …), refreshed on `cd`/`git checkout` and when the window regains focus
- ⌘-hold shortcut hints: hold ⌘ to reveal each sidebar row's ⌘-digit shortcut
- Terminal bell notifications: BEL (`\a`) or OSC 9/777 raises a macOS notification even when kterm is in the background
- In-app notification cues: 🔔 on the horizontal tab, a dot on its sidebar group, and a static border on the pane; clear on select, foreground return, or content interaction
- Dock bounce when unfocused: a ping while kterm isn't active bounces the dock icon
- Smart notification suppression: OS banner and dock bounce only when you're not already looking at that exact pane; in-app 🔔/border still mark it
- Click-to-focus notifications: desktop notification tap brings kterm forward and focuses the pane that raised it
- Drag & drop files: dropping a file onto the terminal inserts its shell-escaped path
- Open a folder: `open -a kterm <dir>` (or Finder "Open With" / drop on the icon) opens a new tab in that folder in the current window

## Shortcuts

| Key | Action |
| --- | --- |
| ⌘N | New **vertical** tab (a new group in the left sidebar) |
| ⌘T | New **horizontal** tab (a new split tree in the current group) |
| ⌘W | Close the focused **pane** (closes the tab when it was the last pane) |
| ⌘D | Split pane **right** (Ghostty `new_split:right`) |
| ⌘⇧D | Split pane **down** (Ghostty `new_split:down`) |
| ⌘[ / ⌘] | Previous / next pane (Ghostty `goto_split:previous` / `next`) |
| ⌘⌥↑↓←→ | Focus pane in that direction (`goto_split`) |
| ⌘⌃↑↓←→ | Resize focused split (`resize_split`, step 10) |
| ⌘⌃= | Equalize splits |
| ⌘⇧↩ | Toggle split zoom |
| ⌘B | Toggle the sidebar |
| ⌘1…⌘9 | Jump to vertical tab (group) by position |
| ⌘⇧[ / ⌘⇧] | Previous / next horizontal tab |
| ⌘⌃[ / ⌘⌃] | Previous / next vertical tab (group) |
| ⌘` | Cycle vertical tabs (alias of next vertical tab) |
| ⌘Q | Quit (no confirmation) |

Holding ⌘ alone for half a second reveals each sidebar row's ⌘-digit shortcut as a hint.

Split actions appear in the app menu (File / Window), with Ghostty-default
shortcuts. libghostty still accepts the same binds via passthrough
`keybind = …` lines in `~/.config/kterm/config` when the menu does not claim
the key. The tab-chip × closes the whole horizontal tab (all its panes).

## Configuration

Text file at `~/.config/kterm/config` (`key = value`). `kterm-` keys configure
the app shell; everything else passes through to libghostty. See
[`config.example`](./config.example).

### Built-in options

Baked-in defaults (override by setting the same key in your config):

| Key | Default | Meaning |
| --- | --- | --- |
| `macos-option-as-alt` | `left` | Left ⌥ acts as Alt/Meta (e.g. for readline word-jump) |
| `copy-on-select` | `clipboard` | Selecting text copies it to the system clipboard |
| `theme` | `Ghostty Default Style Dark` | Terminal color theme (bundled with kterm) |
| `font-family` | `JetBrainsMono Nerd Font Mono` | Terminal text. Missing glyphs (CJK, emoji, …) use Ghostty's CoreText fallback. Repeatable: a `font-family` line in the config file replaces this default |

`kterm-` keys (app shell, no libghostty default):

| Key | Default | Meaning |
| --- | --- | --- |
| `kterm-sidebar-width` | `160` | Width of the vertical tab sidebar, in points |
| `kterm-new-tab-position` | `after-current` | Where a new ⌘N/⌘T tab lands: `after-current` (right after the current tab, pushing the rest back) or `end` (append) |
| `kterm-font-ligatures` | `false` | Programming ligatures. Off by default; set `true` to enable. Disabling maps to Ghostty's `font-feature = -calt, -liga, -dlig` |
| `kterm-ui-font-family` | `JetBrainsMono Nerd Font Mono` | Font for app-shell chrome (sidebar, tab titles, shortcut pills, empty states). Falls back to the system UI font when the family isn't installed; `monospace` uses the system monospaced face. Terminal text still uses Ghostty's `font-family` |

New tabs and split panes inherit the working directory of the tab/pane they were
opened from (honouring libghostty's `window-inherit-working-directory`).

**Reload Configuration** (⌘⇧, in the app menu) re-reads `~/.config/kterm/config`
and applies it live: terminal settings (font, theme, …) via libghostty, plus
kterm's shell settings (UI font, sidebar width, new-tab position).

## Addressing a tab

Each pane's shell gets a `KTERM_TAB_ID` environment variable holding that pane's
id. Opening `kterm://focus-tab?id=<id>` raises that pane (the mechanism behind
click-to-focus notifications), so a script can jump you back to its own pane:

```sh
open "kterm://focus-tab?id=$KTERM_TAB_ID"
```

## Build

Requires Xcode (with the Metal Toolchain component) and
[XcodeGen](https://github.com/yonsm/XcodeGen).

```sh
git submodule update --init ghostty   # the pinned ghostty source
./scripts/build-ghosttykit.sh         # builds GhosttyKit.xcframework (needs Zig 0.16.0; auto-downloaded)
xcodegen generate                     # generates kterm.xcodeproj from project.yml
xcodebuild -project kterm.xcodeproj -scheme kterm -configuration Release
```

`build-ghosttykit.sh` downloads the exact Zig toolchain, pins Zig's macOS SDK to
the Command Line Tools' macOS 15 SDK (Zig 0.16.0 can't parse the macOS 26 SDK),
and emits `GhosttyKit.xcframework` from the `ghostty/` submodule.

## Layout

```
Window
└─ HStack
   ├─ Sidebar          vertical tabs (groups)        ⌘N adds, ⌘B toggles, resizable
   └─ VStack
      ├─ TabStrip      horizontal tabs               ⌘T adds; × closes tab
      └─ SplitTree     panes inside the active tab   ⌘D/⌘⇧D split; ⌘[/⌘] navigate
         └─ SurfaceView  libghostty terminal (per pane)
```

Tab titles track the focused pane's working directory (via `GHOSTTY_ACTION_PWD`).
