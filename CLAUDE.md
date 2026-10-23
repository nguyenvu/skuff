# CLAUDE.md

Skuff — a filing-cabinet launcher for macOS. Colored tabs sit on the screen edge; clicking a tab slides out a folder (an app grid). Native SwiftUI + AppKit, distributed through the Mac App Store, Free + Pro (one-time purchase).

## Reference docs

These docs are written in Vietnamese (with en/nb store copy). Keep them in that language when editing.

- [folder-tab-launcher_1.md](folder-tab-launcher_1.md) — original spec: concept, architecture, Free/Pro split, iCloud Sync, roadmap. It is direction, not an exact description of the current code.
- [Marketing/FEATURES.md](Marketing/FEATURES.md) — 1.0 features that actually ship, used for the website.
- [Marketing/CHANGELOG.md](Marketing/CHANGELOG.md) — changelog plus the pre-submission checklist.
- [Marketing/APP_STORE.md](Marketing/APP_STORE.md) — App Store Connect copy (en-US, nb) with character counts.

When adding or removing a user-visible feature, update FEATURES.md and CHANGELOG.md to match. Do not put anything from the "not in 1.0" lists (folder tabs, smart filters, iCloud Sync, multiple edges, More tab, Focus-based tab sets) into marketing copy — even where the code already has part of it (e.g. `FolderBrowserView`, `FolderAccess` for folder tabs).

## Build & configuration

- Open `Skuff App Launcher.xcodeproj`, scheme `Skuff App Launcher` (shared).
- CLI build: `xcodebuild -project "Skuff App Launcher.xcodeproj" -scheme "Skuff App Launcher" -configuration Debug build`
- Build, relaunch, and read logs with the project skill `skuff-build-run` (`.claude/skills/skuff-build-run/`), which wraps these commands and has the before-done checklist.
- macOS 27.0+, Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (everything is MainActor by default; code that runs off the main thread must be marked `nonisolated`, see `HotkeyCenter.swift`).
- `Skuff App Launcher/` is a file-system synchronized group: dropping a `.swift` file into the folder adds it to the target, no `project.pbxproj` edit needed.
- Bundle ID `no.voq.skuff`, `LSUIElement = YES` (background app, no Dock icon; opening Settings temporarily switches to `.regular`, closing it goes back to `.accessory`).
- App Sandbox is on — entitlements in [Skuff.entitlements](Skuff.entitlements): user-selected read-write, app-scope bookmarks, read-only access to `/Applications`, `/System/Applications`, `~/Applications`, `~/Library/Preferences/com.apple.dock.plist`. Any new file access must be added there.
- StoreKit testing: [Products.storekit](Products.storekit), product `no.voq.skuff.pro` (Non-Consumable, Family Sharing).
- There is no test target. `GeometrySafetyTests.testDegenerateRects()` runs via `precondition` at launch in DEBUG builds (from `PanelController.start()`), so a shape change that produces NaN/infinite paths crashes immediately on a Debug run.

## Architecture

Launch flow: `SkuffApp` (`MyApp.swift`) → `AppDelegate` creates `LibraryStore`, `PanelController`, `SettingsPresenter`, and the status item. The store calls back into the UI through closures (`onChange`, `presentSettings`, `presentTogglePanel`).

| File | Role |
|---|---|
| `LibraryStore.swift` | Central state (`ObservableObject`, MainActor): tabs, installed apps, settings, per-screen anchors, every tab mutation, import/export, hotkeys, undo. |
| `Models.swift` | Data types: `SkuffProduct`, `TabKind`, `TabIcon`, `ScreenEdge`, `ThemePreset`, `ShapeTemplate`, `TabFinish`, `SkuffSettings`, `FolderTab` (Codable, used for JSON), `FolderTabRecord` (SwiftData `@Model`). |
| `PanelController.swift` | Windows: one `StripWindow` per screen (non-activating `NSPanel`, clicks pass through transparent areas) plus a separate folder panel. Handles Spaces, full screen (`FullscreenDetector`), the Dock (`DockMetrics`), relayout. |
| `EdgeStripView.swift`, `TabStripLayout.swift`, `TabMetrics.swift` | The tab strip: layout, shrinking/overlapping when crowded, vertical labels (`RotatedTabLabel` is a custom `Layout`). |
| `TrapezoidTabShape.swift`, `FolderPanelShape.swift`, `TabBackground.swift` | Tab shape, folder shape joined to its tab, Flat/Gradient/Liquid finishes. |
| `FolderSheetView.swift` | Folder contents (app grid, search, pinned apps, upgrade card). |
| `FolderBrowserView.swift`, `FolderListing.swift`, `FolderAccess.swift`, `FolderThumbnails.swift` | Folder tabs (Pro, not yet marketed): file listing, Quick Look, security-scoped bookmarks, thumbnail cache. Listing runs off the main thread (`FolderListing` is `nonisolated`); results carry a generation token so stale ones are dropped. Hidden files and excluded names always come from global Settings; view mode, sort, and type filter are per tab. |
| `AppLibrary.swift`, `DefaultTabs.swift` | Scans installed apps, categorizes by `LSApplicationCategoryType`, seeds default tabs on first launch. |
| `TabEditorView.swift`, `AppPickerView.swift`, `SettingsView.swift` | Tab editor, app picker, Settings UI. |
| `HotkeyCenter.swift` | Global hotkeys via Carbon `RegisterEventHotKey` (⌥1…⌥9 plus a toggle key), delivered through `NotificationCenter`. |
| `ProStore.swift` | StoreKit 2: purchase, restore (`AppStore.sync()`), listens to `Transaction.updates`. |
| `ConfigTransfer.swift`, `ConfigBackup.swift` | `SettingsStore` (UserDefaults), JSON export/import (`SkuffDocument`), automatic backups in Application Support (keeps 5) that back Undo. |
| `IconStore.swift`, `SFSymbolCatalog.swift` | PNG/SVG icons in Application Support; bundled curated SF Symbol list. |
| `GeometrySafety.swift` | Clamps geometry and blocks NaN/infinite values before drawing. |

## Persistence

- Tabs: SwiftData `FolderTabRecord`, `cloudKitDatabase: .none` (iCloud not enabled yet). If the store fails to open, it falls back to in-memory and reports via `ioMessage`.
- Keep the model CloudKit-compatible for later: every property has a default or is optional, no `@Attribute(.unique)`. Complex values are stored as JSON strings (`folderSourceJSON`, `filterJSON`).
- Settings, per-screen positions, app names, and the auto-organize flag live in UserDefaults under `skuff.*` keys (`SettingsStore`).
- Apps are stored by **bundle ID**, not by path.
- Security-scoped bookmarks only work on the Mac that created them. `FolderTab.folderBookmarks` is excluded from JSON (see `FolderTab.CodingKeys`), but `FolderSource.bookmark` is still encoded — automatic backups reuse `ConfigTransfer.exportData`, and Undo needs the bookmark to keep folder access. The `path` is kept so access can be re-requested on another Mac.
- When adding a field to a Codable type, decode it with `decodeIfPresent` plus a default (as `FolderSource` does) so older config files still import.

## Free / Pro

- Check entitlement via `store.pro.isPro`; Free limit is `SkuffProduct.freeAppTabLimit = 5`, enforced in `LibraryStore.isBeyondFreeLimit`.
- Principle: no blocking popups. Tabs over the limit show a lock and an Upgrade button inside the tab. Colors, emoji, SF Symbols, search, hotkeys, tab shrinking/overlap, and export/import are always Free.
- **Before release:** `SkuffProduct.paywallDisabled` (in `Models.swift`) is currently `true` for testing Pro — it must be set back to `false`.

## Conventions

- In-app UI text is English; internal and marketing docs are Vietnamese (with en/nb versions where needed).
- Don't steal focus: panels are non-activating; only Settings and sheets that need text input should activate the app. An open folder panel becomes key without activating Skuff (`store.folderWantsKeyboard`, set when a tab is opened by click or hotkey), so typing goes straight to its search field. It does not take the keyboard if a full-screen app covers that same screen.
- Actions that can fail should say so: use `store.flash(_:)` for a short notice in the strip banner, or show the error inline where the user acted. Don't route errors to `ioMessage` unless Settings is open.
- Respect Reduce Motion and keep VoiceOver labels/actions intact when changing tabs or app cells.
- New drawing code (Shapes, hand-computed frames) should go through `GeometrySafety`, and ideally add a case to `GeometrySafetyTests`.
- Log with `os.Logger` using subsystem `no.voq.skuff`.
