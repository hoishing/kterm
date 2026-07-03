- refer cmux/ for the vertical + horizontal tab layout
- refer ghostling/ for how to use `libghostty`
- use swift, swiftUI for app shell, and `libghostty` for the core functionality
- "build the app" means: Release build for arm64 only (`ARCHS=arm64`;
  GhosttyKit.xcframework has no x86_64), then copy the product over
  `/Applications/kterm.app` (fixed path keeps its Full Disk Access grant)

## e2e tests

`ktermUITests` (XCUITest) drives the real macOS desktop, so it steals the
screen if run locally with `xcodebuild test`. Fast-user-switching to a second
account does NOT work around this — testmanagerd's control channel requires
the console (active/foreground) session, so tests just hang and never connect
in a backgrounded session.

Run e2e tests via `./scripts/run-e2e.sh [TestClass[/testMethod]] [--wait]`,
which dispatches `.github/workflows/e2e.yml` on a GitHub-hosted `macos-15`
runner (`scripts/create-virtual-display.m`, borrowed from `cmux/`, gives it a
virtual display since it has no physical one). Local machine is never
touched; xcresult is uploaded as a workflow artifact.
