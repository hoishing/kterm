- refer cmux/ for the vertical + horizontal tab layout
- refer ghostling/ for how to use `libghostty`
- use swift, swiftUI for app shell, and `libghostty` for the core functionality
- new tabs inherit the triggering tab's cwd (via `ghostty_surface_inherited_config`)
  and default to opening right after it (`kterm-new-tab-position = after-current`)
- SwiftUI's WindowGroup auto-opens a window for any file/folder open, so the app
  sets `.handlesExternalEvents(matching: [])` and routes `open -a kterm <dir>`
  into the front window itself (`AppModel.openDirectory`); the cold-launch first
  window is opened manually via `AppModel.openNewWindow`
- "build the app" means: Release build for arm64 only (`ARCHS=arm64`;
  GhosttyKit.xcframework has no x86_64), then copy the product over
  `/Applications/kterm.app` (fixed path keeps its Full Disk Access grant)
- "publish the app" means: build the app, update README.md and this CLAUDE.md
  if necessary, commit, push
