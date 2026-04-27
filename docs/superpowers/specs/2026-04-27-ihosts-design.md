# iHosts — Design Spec

**Date:** 2026-04-27  
**Author:** debuginn  
**Status:** Approved

---

## 1. Overview

iHosts is a macOS menu-bar-first app for managing and switching `/etc/hosts` configurations. It is open-source, personal-use, and does not target the App Store. It supports two complementary modes:

- **Module stacking mode** — multiple independent hosts fragments, each with an on/off toggle; the system hosts file is the merged result of all enabled modules.
- **Profile switching mode** — mutually exclusive full configurations; activating a Profile replaces the system hosts content entirely.

Key surface areas: macOS menu bar popover, a dedicated editor window, and a Widget Extension for quick switching.

---

## 2. Architecture

**Pattern:** MVVM, strictly layered. Each layer has one responsibility; no layer reaches across boundaries.

```
MenuBarExtra (Popover UI)
EditorWindow (on-demand)
Widget Extension
        │
        ▼
   AppViewModel / EditorViewModel   ← ViewModel layer
        │
        ▼
   HostsStore / HostsComposer       ← Service layer (pure logic)
        │
        ▼
   AppState / HostsGroup / Profile  ← Model layer (pure data)
        │
        ▼
   AppGroupContainer                ← Shared persistence (App Group)
        │
        ▼ (XPC)
   iHostsHelper (PrivilegedHelper)  ← Writes /etc/hosts as root
```

**Data flow:**
```
User action → ViewModel → HostsComposer (pure fn) → XPC → Helper → /etc/hosts
                       → AppGroupContainer → Widget refresh
```

---

## 3. Data Model

```swift
struct HostsEntry: Identifiable, Codable {
    var id: UUID
    var ip: String
    var hostname: String
    var isComment: Bool
    var isEnabled: Bool
}

struct HostsGroup: Identifiable, Codable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var entries: [HostsEntry]
}

struct Profile: Identifiable, Codable {
    var id: UUID
    var name: String
    var groups: [HostsGroup]
}

struct AppState: Codable {
    var modules: [HostsGroup]       // module stacking mode
    var profiles: [Profile]         // profile switching mode
    var activeProfileId: UUID?      // nil = use module stacking mode
    var systemHostsHeader: String   // preserve existing system comments
}
```

**Persistence:** `AppState` is serialized as JSON into the App Group container at `group.com.debuginn.iHosts/state.json`. All three targets (main App, Widget, Helper) share this container.

**HostsComposer** is a pure-function namespace with no side effects:

```swift
enum HostsComposer {
    // Merges enabled modules or active Profile into final /etc/hosts string
    static func compose(from state: AppState) -> String
}
```

Composition rules:
- If `activeProfileId` is set: output = `systemHostsHeader` + active Profile's enabled groups
- If `activeProfileId` is nil: output = `systemHostsHeader` + all enabled modules merged in list order
- Disabled entries are skipped; disabled groups are skipped entirely

---

## 4. ViewModel Layer

### AppViewModel

```swift
@MainActor
class AppViewModel: ObservableObject {
    @Published var state: AppState
    @Published var isApplyingHosts: Bool = false
    @Published var lastError: String?

    private let store: HostsStore
    private let helperClient: HelperXPCClient

    // Module stacking mode
    func toggleModule(_ id: UUID)
    func addModule(name: String)
    func deleteModule(_ id: UUID)
    func updateModule(_ group: HostsGroup)

    // Profile switching mode
    func activateProfile(_ id: UUID?)  // nil = exit Profile, return to module mode
    func addProfile(name: String)
    func deleteProfile(_ id: UUID)

    // Single write entry point
    func applyHosts() async
}
```

- Single global instance, injected via `.environmentObject` at the root
- `applyHosts()` is the **only** path that triggers a write to `/etc/hosts`
- All mutations go through ViewModel; Views never touch Model directly

### EditorViewModel

```swift
@MainActor
class EditorViewModel: ObservableObject {
    @Published var content: String
    @Published var isDirty: Bool = false

    func parse() -> [HostsEntry]
    func save(to group: inout HostsGroup)
}
```

- Created per editor session; released when editor window closes
- Owns the raw text string for the syntax-highlighted editor

---

## 5. View Layer

### Menu Bar Popover

```
MenuBarExtra
└── MenuBarPopoverView
    ├── ModeToggleView          // "Modules" / "Profile" segmented toggle
    ├── ModuleListView          // list of modules with Toggle per row
    │   └── ModuleRowView       // name + Toggle
    ├── ProfileListView         // list of profiles, single-select
    │   └── ProfileRowView      // name + checkmark
    ├── ApplyButton             // "Apply to System" + loading spinner
    └── OpenEditorButton        // opens EditorWindow
```

The popover appears attached to the menu bar icon. It shows current active state and allows quick toggling without opening the editor.

### Editor Window (on-demand)

```
EditorWindow
└── EditorRootView
    ├── SidebarView             // left: module/profile tree with add/delete
    ├── HostsEditorView         // right: syntax-highlighted NSTextView
    └── EditorToolbarView       // save, format, add entry shortcut
```

**Syntax highlighting** uses `NSTextView` + `NSTextStorageDelegate`:

| Token | Color |
|-------|-------|
| Comment line (`#`) | Gray |
| IP address | Blue |
| Hostname | Primary (system default) |
| Disabled line | Dimmed gray (entire line) |

### Widget Extension

- **Small size:** current mode label + count of enabled modules/active profile name
- **Medium size:** list of modules with toggle buttons via `AppIntent`

Widget reads from App Group container. Toggle action uses `AppIntent` → updates `AppState` JSON → calls `WidgetCenter.shared.reloadAllTimelines()`.

> **Note:** Widget cannot write `/etc/hosts` directly (no XPC access). Widget toggle updates the App Group JSON only. The main app observes App Group changes via `CFNotificationCenter (Darwin)`; if it is running, it auto-applies immediately. If the app is not running, the toggle state is saved and applied on next app launch.

---

## 6. PrivilegedHelper (XPC)

**Principle:** the Helper does exactly one thing — write a string to `/etc/hosts`. No business logic lives here.

```swift
// Shared XPC protocol
protocol HostsHelperProtocol {
    func writeHosts(_ content: String, reply: @escaping (Error?) -> Void)
    func readHosts(reply: @escaping (String?, Error?) -> Void)
}

// Main App client
class HelperXPCClient {
    func writeHosts(_ content: String) async throws
    func readHosts() async throws -> String
}
```

**Installation:** `SMJobBless` registers the Helper as a `LaunchDaemon` on first launch. The user authorizes once via system dialog; subsequent writes require no password prompt.

**Security:** Helper validates that incoming XPC connections satisfy a code-signing requirement matching the main App's bundle identity. Connections from other processes are rejected.

---

## 7. Project Structure

```
iHosts/
├── iHosts/                         # Main App Target
│   ├── App/
│   │   └── iHostsApp.swift
│   ├── Models/
│   │   ├── AppState.swift
│   │   ├── HostsGroup.swift
│   │   ├── Profile.swift
│   │   └── HostsEntry.swift
│   ├── ViewModels/
│   │   ├── AppViewModel.swift
│   │   └── EditorViewModel.swift
│   ├── Views/
│   │   ├── MenuBar/
│   │   │   ├── MenuBarPopoverView.swift
│   │   │   ├── ModeToggleView.swift
│   │   │   ├── ModuleListView.swift
│   │   │   ├── ProfileListView.swift
│   │   │   └── ApplyButton.swift
│   │   ├── Editor/
│   │   │   ├── EditorRootView.swift
│   │   │   ├── SidebarView.swift
│   │   │   ├── HostsEditorView.swift
│   │   │   └── EditorToolbarView.swift
│   │   └── Shared/
│   ├── Services/
│   │   ├── HostsStore.swift
│   │   ├── HostsComposer.swift
│   │   └── HelperXPCClient.swift
│   └── Resources/
│
├── iHostsHelper/                   # PrivilegedHelper Target
│   └── main.swift
│
├── iHostsWidget/                   # Widget Extension Target
│   ├── HostsWidgetView.swift
│   ├── HostsWidgetProvider.swift
│   └── HostsWidgetIntent.swift
│
└── Shared/                         # Shared across all targets (local Swift package)
    ├── AppGroup.swift              # App Group path constants
    ├── AppState.swift
    └── HostsHelperProtocol.swift
```

---

## 8. Key Constraints

| Constraint | Decision |
|---|---|
| Distribution | Open source, direct download (not App Store) |
| Hosts sources | Local only, no remote URL subscriptions |
| Editor | Syntax highlighting (IP blue, comments gray, disabled dimmed) |
| Architecture | MVVM, strict layer separation |
| Root access | SMJobBless PrivilegedHelper, one-time authorization |
| Data sharing | App Group JSON, shared by App + Widget |
| Minimum macOS | macOS 26 (Tahoe) — Liquid Glass design language, latest `MenuBarExtra` and `AppIntent` APIs |

---

## 9. macOS 26 (Tahoe) UI Guidelines

Target: **macOS 26 minimum deployment**. All UI must follow the Liquid Glass design language.

**Materials:**
- Popover 面板：使用 `.glassBackground()` / `GlassEffectContainer`，背景模糊透明
- 侧边栏：`NavigationSplitView` + `.sidebar` list style，自动获得 Liquid Glass sidebar 材质
- 工具栏：`ToolbarItem` 使用系统默认渲染，macOS 26 自动应用 glass chrome
- Widget：使用 `WidgetBackground` glass 材质，与系统桌面深度融合

**Controls:**
- Toggle：系统原生 `Toggle`，macOS 26 风格自动适配
- Button：优先 `.bordered` + `.borderedProminent`，避免自定义样式
- 列表选中：使用 `List` selection binding，系统自动处理高亮态

**色彩与层次:**
- 不硬编码颜色，全部使用语义色（`.primary`、`.secondary`、`.accent`）
- 深色/浅色模式自动适配，不额外判断 `colorScheme`
- 状态图标（菜单栏）：使用 SF Symbols，`symbolRenderingMode(.hierarchical)` 增加层次感

**排版:**
- 标题：`.title3` + `.bold`
- 列表项：`.body`
- 辅助信息：`.caption` + `.secondary`

---

## 10. Out of Scope

- Remote/URL hosts sources
- App Store distribution
- Windows / Linux support
- Conflict detection between modules (duplicate hostnames)
- Import/export of hosts files (can be added later)
