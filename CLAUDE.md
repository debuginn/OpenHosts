# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**OpenHosts** is a native macOS app for managing `/etc/hosts`. Users organize entries into named groups (modules or profiles), toggle them on/off, and apply changes to the system. A privileged helper daemon performs the actual file write.

## Build System

The project uses **XcodeGen** — `project.yml` is the source of truth; `OpenHosts.xcodeproj` is generated from it.

```bash
# Regenerate Xcode project after editing project.yml
xcodegen generate

# Build from command line
xcodebuild build -scheme OpenHosts -configuration Debug

# Run tests (SharedKit only — no UI tests yet)
xcodebuild test -scheme SharedKit -destination 'platform=macOS'
```

Open `OpenHosts.xcodeproj` in Xcode for day-to-day development. The macOS deployment target is **26.0** and the project uses **Swift 6** strict concurrency.

## Project Targets

| Target | Bundle ID | Purpose |
|--------|-----------|---------|
| `OpenHosts` | `com.debuginn.OpenHosts` | Main SwiftUI app (menu bar + editor window) |
| `OpenHostsHelper` | `com.debuginn.OpenHosts.Helper` | Privileged daemon — writes `/etc/hosts` |
| `OpenHostsWidget` | `com.debuginn.OpenHosts.Widget` | WidgetKit extension for quick toggles |
| `SharedKit` | — | SPM package; shared data models and business logic |

## Architecture Overview

### Data Flow

```
User action → AppViewModel (main app)
            → AppState mutated
            → HostsStore.save() → shared container JSON
            → Darwin notification posted
            → Auto-apply: HostsComposer.compose() → string
            → HelperXPCClient.writeHosts() via XPC
            → HostsHelperImpl writes /etc/hosts atomically
```

### Shared Container & Cross-Process Sync

All processes communicate through:
- **Shared container**: `group.com.debuginn.OpenHosts` → `state.json`
- **Darwin notification**: `com.debuginn.OpenHosts.stateChanged`

The widget's `ToggleModuleIntent` mutates the shared container directly, posts the notification, and reloads its timeline — no app launch required.

### Privileged Helper (XPC)

The helper is registered via `SMAppService` (requires user approval in System Settings → Login Items). `HelperInstaller` manages registration status. `HelperXPCClient` wraps async/await over `NSXPCConnection` using `CheckedThrowingContinuation`. The helper validates the caller's path via `proc_pidpath()` before accepting requests.

### SharedKit (Core Logic)

| File | Role |
|------|------|
| `AppState.swift` | Root model: modules, profiles, activeProfileId, systemHostsHeader |
| `HostsGroup.swift` / `HostsEntry.swift` | Per-group and per-entry models with `isEnabled` flags |
| `HostsStore.swift` | Atomic JSON read/write to shared container |
| `HostsComposer.swift` | Converts `AppState` → `/etc/hosts` file content; respects mode (Modules vs Profiles) |

### Two UI Modes

- **Modules mode**: flat list of independently toggleable groups
- **Profiles mode**: scenario sets (e.g., "Work", "Home"); only one profile active at a time

The `ModeToggleView` switches between them. `HostsComposer` branches on `AppState.mode`.

### Editor

`HostsEditorView` wraps `NSTextView` (via `NSViewRepresentable`) with custom syntax highlighting: comments in gray, IP addresses in blue. `EditorViewModel` owns parsing logic — converting raw text ↔ `[HostsEntry]`.

## Key Files

- `OpenHosts/App/OpenHostsApp.swift` — app entry point, `MenuBarExtra` scene
- `OpenHosts/ViewModels/AppViewModel.swift` — central state management, apply-hosts orchestration
- `OpenHosts/ViewModels/EditorViewModel.swift` — text ↔ model parsing
- `OpenHosts/Services/HelperXPCClient.swift` — async XPC wrapper
- `OpenHosts/Services/HelperInstaller.swift` — SMAppService registration
- `OpenHostsHelper/main.swift` — daemon entry point (XPC listener loop)
- `SharedKit/Sources/SharedKit/HostsComposer.swift` — hosts file assembly
- `project.yml` — XcodeGen config (targets, entitlements, build settings)

## Entitlements

The main app requires `com.apple.security.application-groups` for the shared container. The helper is authorized via `SMAuthorizedClients` in its `Info.plist`, which must list the main app's code-signing identity. Changes to signing or bundle IDs require updating both `project.yml` and the helper's `Info.plist`.
