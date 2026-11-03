# Repository Guidelines

## Project Structure & Module Organization

DockUnstick is a native macOS background app written in Swift. Application code lives in `Sources/`; `main.swift` is the entry point, while `Dock.swift`, `EventTap.swift`, and `Watcher.swift` separate Dock inspection, event recording, and fix logic. UI code is grouped by feature in `MainWindow.swift`, `MenuBar.swift`, `MenuBarIcon.swift`, `AccessibilityPermission.swift`, and `Settings.swift`.

`Assets/` contains the SVG and 1024 px master icon. `Info.plist` supplies bundle metadata, and `build.sh` assembles the app. Documentation is in `README.md` and `README.zh-CN.md`.

## Build, Test, and Development Commands

Requirements: macOS 13+, Xcode or Xcode Command Line Tools, and the standard `swiftc`, `lipo`, `sips`, `iconutil`, and `codesign` tools.

```sh
./build.sh                 # Build and ad-hoc sign DockUnstick.app
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./build.sh  # Stable signing
open DockUnstick.app       # Launch from the built app, not the terminal
open DockUnstick.app --args --dump 8   # Dump Dock accessibility state
open DockUnstick.app --args --tap 60   # Record Dock event traffic
```

There is no package manager or automated test target. Update both READMEs when installation or user behavior changes.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift formatting. Name files and types in UpperCamelCase, and functions, properties, and values in lowerCamelCase. Keep platform bridges and event-tap logic isolated from UI code.

Every user-facing string must be bilingual through `L("中文", "English")`; add the corresponding documentation update. For settings, use descriptive lowerCamelCase keys in the `local.dockunstick` domain.

Preserve the core privacy contract: use listen-only event taps, do not read screen contents, move the cursor, or access the network. Prefer the smallest reversible fix and check that new behavior works with Accessibility permission.

## Testing Guidelines

Testing is currently manual. Run `./build.sh` after every source change and verify the UI, Dock state, and `~/Library/Logs/DockUnstick.log`. Reproduce a full-screen Space switch with the cursor over the Dock, testing both cursor-left and cursor-still-on-Dock cases.

After an ad-hoc rebuild, recheck Accessibility permission because the changing code hash makes macOS treat the app as new. Prefer `CODESIGN_IDENTITY` when testing repeated grants.

## Commit & Pull Request Guidelines

Follow the existing Conventional Commit style: `feat:`, `fix:`, `refactor:`, `docs:`, `build:`, or `chore:`. Use a concise, imperative, lowercase summary, such as `fix: hide the stuck Dock after a Space change`.

Keep each commit focused. Pull requests should explain the problem and solution, list manual test coverage and macOS version, link related issues, and include screenshots or recordings for visible changes. Update version fields for release preparation.
