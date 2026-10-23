---
name: skuff-build-run
description: Build, launch, and check the Skuff macOS app (Xcode project "Skuff App Launcher.xcodeproj", SwiftUI + AppKit). Use this whenever you change Swift code in this repo and need to confirm it compiles cleanly, when asked to run, start, relaunch, or try the app, when checking a fix "works in the real app", when reading Skuff's logs or a launch crash, or before telling the user a change is done. Prefer it over hand-written xcodebuild commands.
---

# Build and run Skuff

Skuff is a menu-bar/background app (`LSUIElement`), sandboxed, bundle ID `no.voq.skuff`. It shows a strip of tabs on a screen edge; there is no main window and no Dock icon. The scripts below wrap the exact commands so you don't have to rediscover the scheme, the build folder, or how to quit a background app.

All scripts live next to this file in `scripts/` and resolve the repo root themselves, so call them by path from anywhere.

## Build

```bash
.claude/skills/skuff-build-run/scripts/build.sh          # Debug
.claude/skills/skuff-build-run/scripts/build.sh Release
```

It prints only `warning:`/`error:` lines and the `** BUILD … **` result; the full log path is printed on failure. It builds into Xcode's own DerivedData, so the result is the same app the user runs from Xcode, signed with the project's team (sandbox and entitlements only apply to a signed build — don't pass `CODE_SIGNING_ALLOWED=NO` when you intend to launch it).

The project should build with **zero warnings**. The target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in Swift 5 mode, so most new warnings are concurrency warnings that become errors in Swift 6. Fix them rather than leaving them: mark value types and helpers that run off the main thread `nonisolated`, and capture `self` as a local (`guard let model = self else { return }`) before hopping into `Task { @MainActor in … }` from a `@Sendable` closure.

## Launch

```bash
.claude/skills/skuff-build-run/scripts/run.sh
```

It quits any running Skuff (AppleScript quit, then `pkill` if a debugger holds it), opens the built app, waits 3 seconds, and reports whether it is still alive. A Debug build runs `GeometrySafetyTests` via `precondition` at launch, so a shape change that produces NaN/infinite paths shows up here as an immediate exit; the script points to the newest crash report in `~/Library/Logs/DiagnosticReports/`.

Launching replaces whatever Skuff the user has open, including one started from Xcode (its debug session ends). If the user may be mid-test in Xcode, say that you are relaunching.

Launching with `open` does not use `Products.storekit`; the StoreKit test configuration only applies when run from Xcode. Purchases from a script-launched build go to the sandbox store, so test Pro via `SkuffProduct.paywallDisabled` or from Xcode instead.

## Logs

```bash
.claude/skills/skuff-build-run/scripts/logs.sh        # last 5 minutes
.claude/skills/skuff-build-run/scripts/logs.sh 1m
```

Shows `os.Logger` output for subsystem `no.voq.skuff` (for example `Logger.spaces`, which logs strip show/hide and full-screen coverage) plus faults from the process. `log stream` blocks, so prefer this after reproducing something. When you need logging to diagnose a bug, add a `Logger` with subsystem `no.voq.skuff` and a specific category instead of `print`, which does not reach the unified log.

## Click test

```bash
swift .claude/skills/skuff-build-run/scripts/clicktest.swift          # mid-tab, every 8 pt
swift .claude/skills/skuff-build-run/scripts/clicktest.swift 30 16    # 30 pt in from the edge, every 16 pt
```

It finds the strip window, clicks along it with synthetic mouse events, checks whether the folder panel appeared after each click (closing it with Esc), and prints a map such as `##.###` plus the coordinates that missed. Use it whenever clicks, hit areas, tab shapes, finishes, or the strip windows change. It moves the real pointer for about a minute, so tell the user before running it.

It needs Accessibility permission for the app hosting this session (on recent macOS the pane may be named differently; a prompt from `AXIsProcessTrustedWithOptions` adds the app to the right list). If the script says it has no permission, ask the user rather than working around it.

To see *why* a point misses, read `logs.sh 1m | grep input`. DEBUG builds log each mouse-down that reaches the strip (`strip down … inRects=`), the tab gesture (`tab press` / `tab release … as=click|drag`), and `toggleTab`. A click with no `strip down` line never reached Skuff: the window server sent it through, which happens on fully transparent pixels (glass finishes drawn with `glassEffect` leave the window buffer transparent; `TabBackground` keeps a 1% fill for this reason).

## What you can and can't verify

You can confirm it compiles, launches, stays alive, what it logs, and — with the click test — whether tabs open where they should. You still cannot see how things look, type into the folder panel, or judge animations and drags. For those, tell the user exactly what to try (which tab, which gesture, what they should see), based on what you changed.

## Before saying a change is done

1. `build.sh` reports `BUILD SUCCEEDED` with no warnings.
2. `run.sh` reports Skuff still running (for any change that touches layout, shapes, windows, or launch code).
3. `logs.sh 1m` shows no new faults.
4. Give the user a short manual test list for the parts you couldn't observe.
5. If the change is user-visible, check whether `Marketing/FEATURES.md` and `Marketing/CHANGELOG.md` need an update (they are written in Vietnamese; keep them that way).
6. If preparing a release build, `SkuffProduct.paywallDisabled` in `Models.swift` must be `false` — mention it if it is still `true`. Don't flip it unless the user asks.
