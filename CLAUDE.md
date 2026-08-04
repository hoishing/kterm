# kterm agent rules

SwiftUI shell around `libghostty`. Vertical tabs only (sidebar).

## References

- Layout precedent: `cmux/`
- `libghostty` usage: `ghostling/`

## Stack

- App shell: Swift + SwiftUI
- Terminal core: `libghostty`

## Tabs

- New tabs inherit the triggering tab's cwd via `ghostty_surface_inherited_config`
- Default insert position: right after current (`kterm-new-tab-position = after-current`)
- Shortcuts: ⌘T new tab, ⌘⇧[ / ⌘⇧] cycle, ⌘W close, ⌘1…⌘9 jump

## Window / open routing

- SwiftUI `WindowGroup` auto-opens a window for any file/folder open
- App sets `.handlesExternalEvents(matching: [])` and routes `open -a kterm <dir>` into the front window (`AppModel.openDirectory`)
- Cold-launch first window is opened manually via `AppModel.openNewWindow`

## Build / publish

- **build the app:** Release, arm64 only (`ARCHS=arm64`; GhosttyKit.xcframework has no x86_64), then copy the product over `/Applications/kterm.app` (fixed path keeps its Full Disk Access grant)
- **publish the app:** build → update e2e / README.md / this file if needed → commit → push → run e2e (`./scripts/run-e2e.sh`) if e2e changed

## e2e tests

`ktermUITests` (XCUITest) drives the real macOS desktop and steals the screen if run locally with `xcodebuild test`.

- Fast-user-switching to a second account does **not** work around this
- testmanagerd's control channel requires the console (active/foreground) session
- Backgrounded sessions hang and never connect

Run via `./scripts/run-e2e.sh [TestClass[/testMethod]] [--wait]`:

- Dispatches `.github/workflows/e2e.yml` on a GitHub-hosted `macos-15` runner
- `scripts/create-virtual-display.m` (from `cmux/`) gives the runner a virtual display
- Local machine is never touched; xcresult uploads as a workflow artifact
