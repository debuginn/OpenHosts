# iHosts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build iHosts — a macOS 26 menu-bar-first app for managing `/etc/hosts` with module stacking, profile switching, a syntax-highlighted editor, and a Widget Extension for quick toggling.

**Architecture:** MVVM with strict layer separation. Shared models compiled into all three targets (App, Helper, Widget) via a local Swift Package. PrivilegedHelper handles root writes via XPC + SMJobBless. App Group JSON is the single source of truth shared by App and Widget.

**Tech Stack:** Swift 6.3, SwiftUI (macOS 26 Liquid Glass), XCTest, ServiceManagement (SMJobBless), WidgetKit, AppIntents, CFNotificationCenter (Darwin)

**Bundle IDs:**
- App: `com.debuginn.iHosts`
- Helper: `com.debuginn.iHosts.Helper`
- Widget: `com.debuginn.iHosts.Widget`
- App Group: `group.com.debuginn.iHosts`

---

## File Map

```
iHosts/
├── SharedKit/                              # Local Swift Package (all targets)
│   ├── Package.swift
│   └── Sources/SharedKit/
│       ├── AppGroup.swift
│       ├── HostsEntry.swift
│       ├── HostsGroup.swift
│       ├── Profile.swift
│       ├── AppState.swift
│       ├── HostsHelperProtocol.swift
│       ├── HostsComposer.swift
│       └── HostsStore.swift
│
├── SharedKitTests/                         # XCTest for SharedKit
│   ├── HostsComposerTests.swift
│   └── HostsStoreTests.swift
│
├── iHosts/                                 # Main App Target
│   ├── App/iHostsApp.swift
│   ├── ViewModels/
│   │   ├── AppViewModel.swift
│   │   └── EditorViewModel.swift
│   ├── Views/MenuBar/
│   │   ├── MenuBarPopoverView.swift
│   │   ├── ModeToggleView.swift
│   │   ├── ModuleListView.swift
│   │   ├── ProfileListView.swift
│   │   └── ApplyButton.swift
│   ├── Views/Editor/
│   │   ├── EditorRootView.swift
│   │   ├── SidebarView.swift
│   │   ├── HostsEditorView.swift
│   │   └── EditorToolbarView.swift
│   └── Services/
│       ├── HelperXPCClient.swift
│       └── HelperInstaller.swift
│
├── iHostsHelper/                           # PrivilegedHelper Target
│   └── main.swift
│
└── iHostsWidget/                           # Widget Extension Target
    ├── HostsWidgetBundle.swift
    ├── HostsWidgetProvider.swift
    ├── HostsWidgetView.swift
    └── HostsToggleIntent.swift
```

---

## Task 1: Xcode Project Setup

**Files:**
- Create: Xcode project at `iHosts/iHosts.xcodeproj` (via Xcode GUI)

- [ ] **Step 1: Create the Xcode project**

  In Xcode → File → New → Project → macOS → App  
  - Product Name: `iHosts`  
  - Team: debuginn (personal team)  
  - Bundle Identifier: `com.debuginn.iHosts`  
  - Language: Swift  
  - Interface: SwiftUI  
  - Storage: None  
  - Uncheck "Include Tests" (we add them manually)  
  - Save to: `~/Code/src/github.com/debuginn/iHosts/`

- [ ] **Step 2: Set deployment target to macOS 26**

  Project navigator → Select `iHosts` project → `iHosts` target → General → Minimum Deployments → macOS 26.0

- [ ] **Step 3: Add iHostsHelper target**

  File → New → Target → macOS → Command Line Tool  
  - Product Name: `iHostsHelper`  
  - Language: Swift  
  - Bundle ID: `com.debuginn.iHosts.Helper`  
  - Set Deployment Target: macOS 26.0

- [ ] **Step 4: Add iHostsWidget target**

  File → New → Target → macOS → Widget Extension  
  - Product Name: `iHostsWidget`  
  - Bundle ID: `com.debuginn.iHosts.Widget`  
  - Uncheck "Include Configuration Intent"  
  - Deployment Target: macOS 26.0

- [ ] **Step 5: Add unit test target**

  File → New → Target → macOS → Unit Testing Bundle  
  - Product Name: `SharedKitTests`  
  - Target to be Tested: `iHosts`

- [ ] **Step 6: Commit skeleton**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts
  git add .
  git commit -m "chore: add Xcode project with App, Helper, Widget targets"
  ```

---

## Task 2: App Group & Entitlements

**Files:**
- Create: `iHosts/iHosts.entitlements`
- Create: `iHosts/iHostsWidget.entitlements`

- [ ] **Step 1: Add App Group capability to main App**

  Xcode → `iHosts` target → Signing & Capabilities → + Capability → App Groups  
  Add group: `group.com.debuginn.iHosts`

  This auto-creates `iHosts.entitlements` with:
  ```xml
  <key>com.apple.security.application-groups</key>
  <array>
      <string>group.com.debuginn.iHosts</string>
  </array>
  ```

- [ ] **Step 2: Add App Group to Widget target**

  Same steps for `iHostsWidget` target. Xcode creates `iHostsWidget.entitlements`.

- [ ] **Step 3: Add SMJobBless entitlement to main App**

  In `iHosts.entitlements`, manually add:
  ```xml
  <key>com.apple.developer.smjobbless</key>
  <true/>
  ```

- [ ] **Step 4: Create Helper Info.plist with SMJobBless keys**

  Create `iHostsHelper/Info.plist`:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>CFBundleIdentifier</key>
      <string>com.debuginn.iHosts.Helper</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>iHostsHelper</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>SMAuthorizedClients</key>
      <array>
          <string>identifier "com.debuginn.iHosts" and anchor apple generic and certificate leaf[subject.CN] = "Mac Developer: *"</string>
      </array>
  </dict>
  </plist>
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add .
  git commit -m "chore: configure App Group and SMJobBless entitlements"
  ```

---

## Task 3: SharedKit Local Swift Package

**Files:**
- Create: `SharedKit/Package.swift`
- Create: `SharedKit/Sources/SharedKit/AppGroup.swift`

- [ ] **Step 1: Create the Swift Package**

  ```bash
  mkdir -p ~/Code/src/github.com/debuginn/iHosts/SharedKit/Sources/SharedKit
  mkdir -p ~/Code/src/github.com/debuginn/iHosts/SharedKit/Tests/SharedKitTests
  ```

  Create `SharedKit/Package.swift`:
  ```swift
  // swift-tools-version: 6.0
  import PackageDescription

  let package = Package(
      name: "SharedKit",
      platforms: [.macOS(.v26)],
      products: [
          .library(name: "SharedKit", targets: ["SharedKit"]),
      ],
      targets: [
          .target(name: "SharedKit"),
          .testTarget(name: "SharedKitTests", dependencies: ["SharedKit"]),
      ]
  )
  ```

- [ ] **Step 2: Create AppGroup constants**

  Create `SharedKit/Sources/SharedKit/AppGroup.swift`:
  ```swift
  import Foundation

  public enum AppGroup {
      public static let identifier = "group.com.debuginn.iHosts"

      public static var containerURL: URL {
          FileManager.default
              .containerURL(forSecurityApplicationGroupIdentifier: identifier)!
      }

      public static var stateFileURL: URL {
          containerURL.appending(path: "state.json")
      }

      public static let darwinNotificationName = "com.debuginn.iHosts.stateChanged"
  }
  ```

- [ ] **Step 3: Add SharedKit to Xcode project**

  Xcode → `iHosts` project → Package Dependencies → + → Add Local…  
  Select `SharedKit/` folder  
  Link `SharedKit` library to: `iHosts`, `iHostsWidget` targets (NOT Helper — it uses its own copy via direct file refs)

- [ ] **Step 4: Commit**

  ```bash
  git add SharedKit/
  git commit -m "feat: add SharedKit local Swift package with AppGroup constants"
  ```

---

## Task 4: Data Models

**Files:**
- Create: `SharedKit/Sources/SharedKit/HostsEntry.swift`
- Create: `SharedKit/Sources/SharedKit/HostsGroup.swift`
- Create: `SharedKit/Sources/SharedKit/Profile.swift`
- Create: `SharedKit/Sources/SharedKit/AppState.swift`
- Create: `SharedKit/Sources/SharedKit/HostsHelperProtocol.swift`

- [ ] **Step 1: Create HostsEntry**

  `SharedKit/Sources/SharedKit/HostsEntry.swift`:
  ```swift
  import Foundation

  public struct HostsEntry: Identifiable, Codable, Sendable, Equatable {
      public var id: UUID
      public var ip: String
      public var hostname: String
      public var isComment: Bool
      public var isEnabled: Bool

      public init(id: UUID = UUID(), ip: String, hostname: String,
                  isComment: Bool = false, isEnabled: Bool = true) {
          self.id = id
          self.ip = ip
          self.hostname = hostname
          self.isComment = isComment
          self.isEnabled = isEnabled
      }
  }
  ```

- [ ] **Step 2: Create HostsGroup**

  `SharedKit/Sources/SharedKit/HostsGroup.swift`:
  ```swift
  import Foundation

  public struct HostsGroup: Identifiable, Codable, Sendable, Equatable {
      public var id: UUID
      public var name: String
      public var isEnabled: Bool
      public var entries: [HostsEntry]

      public init(id: UUID = UUID(), name: String,
                  isEnabled: Bool = true, entries: [HostsEntry] = []) {
          self.id = id
          self.name = name
          self.isEnabled = isEnabled
          self.entries = entries
      }
  }
  ```

- [ ] **Step 3: Create Profile**

  `SharedKit/Sources/SharedKit/Profile.swift`:
  ```swift
  import Foundation

  public struct Profile: Identifiable, Codable, Sendable, Equatable {
      public var id: UUID
      public var name: String
      public var groups: [HostsGroup]

      public init(id: UUID = UUID(), name: String, groups: [HostsGroup] = []) {
          self.id = id
          self.name = name
          self.groups = groups
      }
  }
  ```

- [ ] **Step 4: Create AppState**

  `SharedKit/Sources/SharedKit/AppState.swift`:
  ```swift
  import Foundation

  public struct AppState: Codable, Sendable, Equatable {
      public var modules: [HostsGroup]
      public var profiles: [Profile]
      public var activeProfileId: UUID?
      public var systemHostsHeader: String

      public init(modules: [HostsGroup] = [],
                  profiles: [Profile] = [],
                  activeProfileId: UUID? = nil,
                  systemHostsHeader: String = "") {
          self.modules = modules
          self.profiles = profiles
          self.activeProfileId = activeProfileId
          self.systemHostsHeader = systemHostsHeader
      }

      public static let empty = AppState()
  }
  ```

- [ ] **Step 5: Create XPC protocol**

  `SharedKit/Sources/SharedKit/HostsHelperProtocol.swift`:
  ```swift
  import Foundation

  @objc public protocol HostsHelperProtocol {
      func writeHosts(_ content: String, reply: @escaping (Error?) -> Void)
      func readHosts(reply: @escaping (String?, Error?) -> Void)
  }
  ```

- [ ] **Step 6: Build to verify no errors**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts/SharedKit
  swift build
  ```

  Expected: `Build complete!`

- [ ] **Step 7: Commit**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts
  git add SharedKit/
  git commit -m "feat: add data models (HostsEntry, HostsGroup, Profile, AppState)"
  ```

---

## Task 5: HostsComposer (TDD)

**Files:**
- Create: `SharedKit/Sources/SharedKit/HostsComposer.swift`
- Create: `SharedKit/Tests/SharedKitTests/HostsComposerTests.swift`

- [ ] **Step 1: Write failing tests**

  Create `SharedKit/Tests/SharedKitTests/HostsComposerTests.swift`:
  ```swift
  import XCTest
  @testable import SharedKit

  final class HostsComposerTests: XCTestCase {

      func test_moduleMode_mergesEnabledModules() {
          let entry1 = HostsEntry(ip: "127.0.0.1", hostname: "dev.local")
          let entry2 = HostsEntry(ip: "192.168.1.1", hostname: "staging.local")
          let mod1 = HostsGroup(name: "Dev", isEnabled: true, entries: [entry1])
          let mod2 = HostsGroup(name: "Staging", isEnabled: true, entries: [entry2])
          let state = AppState(modules: [mod1, mod2], systemHostsHeader: "# Header\n")

          let result = HostsComposer.compose(from: state)

          XCTAssertTrue(result.contains("127.0.0.1\tdev.local"))
          XCTAssertTrue(result.contains("192.168.1.1\tstaging.local"))
          XCTAssertTrue(result.hasPrefix("# Header\n"))
      }

      func test_moduleMode_skipsDisabledModules() {
          let entry = HostsEntry(ip: "127.0.0.1", hostname: "dev.local")
          let mod = HostsGroup(name: "Dev", isEnabled: false, entries: [entry])
          let state = AppState(modules: [mod])

          let result = HostsComposer.compose(from: state)

          XCTAssertFalse(result.contains("dev.local"))
      }

      func test_moduleMode_skipsDisabledEntries() {
          let enabled = HostsEntry(ip: "127.0.0.1", hostname: "a.local", isEnabled: true)
          let disabled = HostsEntry(ip: "127.0.0.2", hostname: "b.local", isEnabled: false)
          let mod = HostsGroup(name: "Mix", isEnabled: true, entries: [enabled, disabled])
          let state = AppState(modules: [mod])

          let result = HostsComposer.compose(from: state)

          XCTAssertTrue(result.contains("a.local"))
          XCTAssertFalse(result.contains("b.local"))
      }

      func test_moduleMode_rendersCommentEntries() {
          let comment = HostsEntry(ip: "", hostname: "This is a comment", isComment: true)
          let mod = HostsGroup(name: "Misc", isEnabled: true, entries: [comment])
          let state = AppState(modules: [mod])

          let result = HostsComposer.compose(from: state)

          XCTAssertTrue(result.contains("# This is a comment"))
      }

      func test_profileMode_usesActiveProfile() {
          let entry = HostsEntry(ip: "10.0.0.1", hostname: "prod.internal")
          let group = HostsGroup(name: "Prod", isEnabled: true, entries: [entry])
          let profile = Profile(name: "Production", groups: [group])
          let ignoredModule = HostsGroup(
              name: "Dev",
              isEnabled: true,
              entries: [HostsEntry(ip: "127.0.0.1", hostname: "dev.local")]
          )
          let state = AppState(
              modules: [ignoredModule],
              profiles: [profile],
              activeProfileId: profile.id
          )

          let result = HostsComposer.compose(from: state)

          XCTAssertTrue(result.contains("10.0.0.1\tprod.internal"))
          XCTAssertFalse(result.contains("dev.local"))
      }

      func test_profileMode_fallsBackToModulesWhenProfileIdNil() {
          let entry = HostsEntry(ip: "127.0.0.1", hostname: "dev.local")
          let mod = HostsGroup(name: "Dev", isEnabled: true, entries: [entry])
          let state = AppState(modules: [mod], activeProfileId: nil)

          let result = HostsComposer.compose(from: state)

          XCTAssertTrue(result.contains("dev.local"))
      }
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts/SharedKit
  swift test --filter HostsComposerTests
  ```

  Expected: `error: no such module 'SharedKit'` or compile failure (HostsComposer doesn't exist yet).

- [ ] **Step 3: Implement HostsComposer**

  Create `SharedKit/Sources/SharedKit/HostsComposer.swift`:
  ```swift
  import Foundation

  public enum HostsComposer {
      public static func compose(from state: AppState) -> String {
          var lines: [String] = []

          if !state.systemHostsHeader.isEmpty {
              lines.append(state.systemHostsHeader)
          }

          let groups: [HostsGroup]
          if let profileId = state.activeProfileId,
             let profile = state.profiles.first(where: { $0.id == profileId }) {
              groups = profile.groups
          } else {
              groups = state.modules
          }

          for group in groups where group.isEnabled {
              for entry in group.entries where entry.isEnabled {
                  if entry.isComment {
                      lines.append("# \(entry.hostname)")
                  } else {
                      lines.append("\(entry.ip)\t\(entry.hostname)")
                  }
              }
          }

          return lines.joined(separator: "\n")
      }
  }
  ```

- [ ] **Step 4: Run tests to verify they pass**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts/SharedKit
  swift test --filter HostsComposerTests
  ```

  Expected: `Test Suite 'HostsComposerTests' passed`

- [ ] **Step 5: Commit**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts
  git add SharedKit/
  git commit -m "feat: add HostsComposer with full test coverage"
  ```

---

## Task 6: HostsStore (TDD)

**Files:**
- Create: `SharedKit/Sources/SharedKit/HostsStore.swift`
- Create: `SharedKit/Tests/SharedKitTests/HostsStoreTests.swift`

- [ ] **Step 1: Write failing tests**

  Create `SharedKit/Tests/SharedKitTests/HostsStoreTests.swift`:
  ```swift
  import XCTest
  @testable import SharedKit

  final class HostsStoreTests: XCTestCase {
      var store: HostsStore!
      var tempURL: URL!

      override func setUp() {
          super.setUp()
          tempURL = FileManager.default.temporaryDirectory
              .appending(path: "ihosts-test-\(UUID().uuidString).json")
          store = HostsStore(fileURL: tempURL)
      }

      override func tearDown() {
          try? FileManager.default.removeItem(at: tempURL)
          super.tearDown()
      }

      func test_load_returnsEmptyStateWhenFileAbsent() {
          let state = store.load()
          XCTAssertEqual(state, AppState.empty)
      }

      func test_saveAndLoad_roundTrips() throws {
          let entry = HostsEntry(ip: "127.0.0.1", hostname: "test.local")
          let group = HostsGroup(name: "Test", entries: [entry])
          let original = AppState(modules: [group])

          try store.save(original)
          let loaded = store.load()

          XCTAssertEqual(loaded, original)
      }

      func test_save_overwritesPreviousState() throws {
          let state1 = AppState(modules: [HostsGroup(name: "A")])
          let state2 = AppState(modules: [HostsGroup(name: "B")])

          try store.save(state1)
          try store.save(state2)
          let loaded = store.load()

          XCTAssertEqual(loaded.modules.first?.name, "B")
      }
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts/SharedKit
  swift test --filter HostsStoreTests
  ```

  Expected: compile failure (HostsStore doesn't exist).

- [ ] **Step 3: Implement HostsStore**

  Create `SharedKit/Sources/SharedKit/HostsStore.swift`:
  ```swift
  import Foundation

  public final class HostsStore: @unchecked Sendable {
      private let fileURL: URL
      private let encoder = JSONEncoder()
      private let decoder = JSONDecoder()

      public init(fileURL: URL = AppGroup.stateFileURL) {
          self.fileURL = fileURL
      }

      public func load() -> AppState {
          guard let data = try? Data(contentsOf: fileURL),
                let state = try? decoder.decode(AppState.self, from: data) else {
              return .empty
          }
          return state
      }

      public func save(_ state: AppState) throws {
          let data = try encoder.encode(state)
          try data.write(to: fileURL, options: .atomic)
      }
  }
  ```

- [ ] **Step 4: Run tests to verify they pass**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts/SharedKit
  swift test
  ```

  Expected: all tests pass.

- [ ] **Step 5: Commit**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts
  git add SharedKit/
  git commit -m "feat: add HostsStore with JSON persistence and tests"
  ```

---

## Task 7: PrivilegedHelper

**Files:**
- Create: `iHostsHelper/main.swift`

- [ ] **Step 1: Implement Helper XPC listener**

  Replace default `iHostsHelper/main.swift` content with:
  ```swift
  import Foundation

  final class HostsHelperImpl: NSObject, HostsHelperProtocol {
      func writeHosts(_ content: String, reply: @escaping (Error?) -> Void) {
          do {
              try content.write(toFile: "/etc/hosts", atomically: true, encoding: .utf8)
              reply(nil)
          } catch {
              reply(error)
          }
      }

      func readHosts(reply: @escaping (String?, Error?) -> Void) {
          do {
              let content = try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
              reply(content, nil)
          } catch {
              reply(nil, error)
          }
      }
  }

  final class HelperDelegate: NSObject, NSXPCListenerDelegate {
      func listener(_ listener: NSXPCListener,
                    shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
          // Validate that the connecting process is our main app
          connection.exportedInterface = NSXPCInterface(with: HostsHelperProtocol.self)
          connection.exportedObject = HostsHelperImpl()
          connection.resume()
          return true
      }
  }

  let delegate = HelperDelegate()
  let listener = NSXPCListener.machService(withName: "com.debuginn.iHosts.Helper")
  listener.delegate = delegate
  listener.resume()
  RunLoop.main.run()
  ```

- [ ] **Step 2: Add `HostsHelperProtocol.swift` to Helper target**

  In Xcode: drag `SharedKit/Sources/SharedKit/HostsHelperProtocol.swift` into the `iHostsHelper` group.  
  In "Add to targets" dialog: check `iHostsHelper` only.

  This gives Helper access to the protocol without the full Swift Package.

- [ ] **Step 3: Build Helper target**

  In Xcode: select `iHostsHelper` scheme → Product → Build  
  Expected: Build succeeded.

- [ ] **Step 4: Commit**

  ```bash
  git add iHostsHelper/
  git commit -m "feat: implement PrivilegedHelper XPC listener for /etc/hosts writes"
  ```

---

## Task 8: HelperXPCClient & HelperInstaller

**Files:**
- Create: `iHosts/Services/HelperXPCClient.swift`
- Create: `iHosts/Services/HelperInstaller.swift`

- [ ] **Step 1: Implement HelperXPCClient**

  Create `iHosts/Services/HelperXPCClient.swift`:
  ```swift
  import Foundation

  final class HelperXPCClient: @unchecked Sendable {
      private var connection: NSXPCConnection?

      private func makeConnection() -> NSXPCConnection {
          let c = NSXPCConnection(machServiceName: "com.debuginn.iHosts.Helper",
                                  options: .privileged)
          c.remoteObjectInterface = NSXPCInterface(with: HostsHelperProtocol.self)
          c.invalidationHandler = { [weak self] in self?.connection = nil }
          c.resume()
          return c
      }

      private func proxy() -> HostsHelperProtocol {
          if connection == nil { connection = makeConnection() }
          return connection!.remoteObjectProxyWithErrorHandler { [weak self] _ in
              self?.connection = nil
          } as! HostsHelperProtocol
      }

      func writeHosts(_ content: String) async throws {
          try await withCheckedThrowingContinuation { continuation in
              proxy().writeHosts(content) { error in
                  if let error { continuation.resume(throwing: error) }
                  else { continuation.resume() }
              }
          }
      }

      func readHosts() async throws -> String {
          try await withCheckedThrowingContinuation { continuation in
              proxy().readHosts { content, error in
                  if let error { continuation.resume(throwing: error) }
                  else { continuation.resume(returning: content ?? "") }
              }
          }
      }
  }
  ```

- [ ] **Step 2: Implement HelperInstaller**

  Create `iHosts/Services/HelperInstaller.swift`:
  ```swift
  import Foundation
  import ServiceManagement

  enum HelperInstaller {
      static var isInstalled: Bool {
          SMAppService.daemon(plistName: "com.debuginn.iHosts.Helper.plist").status == .enabled
      }

      static func installIfNeeded() throws {
          guard !isInstalled else { return }
          let service = SMAppService.daemon(plistName: "com.debuginn.iHosts.Helper.plist")
          try service.register()
      }

      static func uninstall() throws {
          let service = SMAppService.daemon(plistName: "com.debuginn.iHosts.Helper.plist")
          try service.unregister()
      }
  }
  ```

- [ ] **Step 3: Build to verify no errors**

  Xcode → select `iHosts` scheme → Product → Build  
  Expected: Build succeeded.

- [ ] **Step 4: Commit**

  ```bash
  git add iHosts/Services/
  git commit -m "feat: add HelperXPCClient and HelperInstaller (SMAppService)"
  ```

---

## Task 9: AppViewModel

**Files:**
- Create: `iHosts/ViewModels/AppViewModel.swift`

- [ ] **Step 1: Implement AppViewModel**

  Create `iHosts/ViewModels/AppViewModel.swift`:
  ```swift
  import Foundation
  import SharedKit

  @MainActor
  final class AppViewModel: ObservableObject {
      @Published var state: AppState
      @Published var isApplyingHosts = false
      @Published var lastError: String?

      private let store: HostsStore
      private let helperClient: HelperXPCClient

      init(store: HostsStore = HostsStore(),
           helperClient: HelperXPCClient = HelperXPCClient()) {
          self.store = store
          self.helperClient = helperClient
          self.state = store.load()
          observeAppGroupChanges()
      }

      // MARK: - Module mode

      func toggleModule(_ id: UUID) {
          guard let idx = state.modules.firstIndex(where: { $0.id == id }) else { return }
          state.modules[idx].isEnabled.toggle()
          persist()
      }

      func addModule(name: String) {
          state.modules.append(HostsGroup(name: name))
          persist()
      }

      func deleteModule(_ id: UUID) {
          state.modules.removeAll { $0.id == id }
          persist()
      }

      func updateModule(_ group: HostsGroup) {
          guard let idx = state.modules.firstIndex(where: { $0.id == group.id }) else { return }
          state.modules[idx] = group
          persist()
      }

      // MARK: - Profile mode

      func activateProfile(_ id: UUID?) {
          state.activeProfileId = id
          persist()
      }

      func addProfile(name: String) {
          state.profiles.append(Profile(name: name))
          persist()
      }

      func deleteProfile(_ id: UUID) {
          state.profiles.removeAll { $0.id == id }
          if state.activeProfileId == id { state.activeProfileId = nil }
          persist()
      }

      func updateProfile(_ profile: Profile) {
          guard let idx = state.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
          state.profiles[idx] = profile
          persist()
      }

      // MARK: - Apply

      func applyHosts() async {
          isApplyingHosts = true
          lastError = nil
          defer { isApplyingHosts = false }
          do {
              let content = HostsComposer.compose(from: state)
              try await helperClient.writeHosts(content)
          } catch {
              lastError = error.localizedDescription
          }
      }

      // MARK: - Private

      private func persist() {
          try? store.save(state)
          notifyAppGroupChanged()
      }

      private func notifyAppGroupChanged() {
          CFNotificationCenterPostNotification(
              CFNotificationCenterGetDarwinNotifyCenter(),
              CFNotificationName(AppGroup.darwinNotificationName as CFString),
              nil, nil, true
          )
      }

      private func observeAppGroupChanges() {
          CFNotificationCenterAddObserver(
              CFNotificationCenterGetDarwinNotifyCenter(),
              Unmanaged.passUnretained(self).toOpaque(),
              { _, observer, _, _, _ in
                  guard let ptr = observer else { return }
                  let vm = Unmanaged<AppViewModel>.fromOpaque(ptr).takeUnretainedValue()
                  Task { @MainActor in
                      vm.reloadFromStore()
                      await vm.applyHosts()
                  }
              },
              AppGroup.darwinNotificationName as CFString,
              nil,
              .deliverImmediately
          )
      }

      private func reloadFromStore() {
          state = store.load()
      }
  }
  ```

- [ ] **Step 2: Build to verify no errors**

  Xcode → Product → Build  
  Expected: Build succeeded.

- [ ] **Step 3: Commit**

  ```bash
  git add iHosts/ViewModels/AppViewModel.swift
  git commit -m "feat: implement AppViewModel with module/profile management and auto-apply"
  ```

---

## Task 10: EditorViewModel

**Files:**
- Create: `iHosts/ViewModels/EditorViewModel.swift`

- [ ] **Step 1: Implement EditorViewModel**

  Create `iHosts/ViewModels/EditorViewModel.swift`:
  ```swift
  import Foundation
  import SharedKit

  @MainActor
  final class EditorViewModel: ObservableObject {
      @Published var content: String
      @Published var isDirty = false

      private let originalContent: String

      init(group: HostsGroup) {
          let text = group.entries.map { entry -> String in
              if entry.isComment { return "# \(entry.hostname)" }
              let prefix = entry.isEnabled ? "" : "# "
              return "\(prefix)\(entry.ip)\t\(entry.hostname)"
          }.joined(separator: "\n")
          self.content = text
          self.originalContent = text
      }

      func markDirty() {
          isDirty = content != originalContent
      }

      func parse() -> [HostsEntry] {
          content.components(separatedBy: "\n").compactMap { line in
              let trimmed = line.trimmingCharacters(in: .whitespaces)
              if trimmed.isEmpty { return nil }

              if trimmed.hasPrefix("#") {
                  let comment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                  // Check if it's a disabled entry: "# 127.0.0.1 hostname"
                  let parts = comment.split(separator: " ", maxSplits: 1)
                  if parts.count == 2, isValidIP(String(parts[0])) {
                      return HostsEntry(ip: String(parts[0]),
                                        hostname: String(parts[1]),
                                        isEnabled: false)
                  }
                  return HostsEntry(ip: "", hostname: comment, isComment: true)
              }

              let parts = trimmed.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
              guard parts.count >= 2 else { return nil }
              return HostsEntry(ip: String(parts[0]), hostname: String(parts[1]))
          }
      }

      func save(to group: inout HostsGroup) {
          group.entries = parse()
          isDirty = false
      }

      private func isValidIP(_ s: String) -> Bool {
          let parts = s.split(separator: ".")
          return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
      }
  }
  ```

- [ ] **Step 2: Build and commit**

  ```bash
  git add iHosts/ViewModels/EditorViewModel.swift
  git commit -m "feat: add EditorViewModel with hosts text parsing"
  ```

---

## Task 11: App Entry Point

**Files:**
- Modify: `iHosts/App/iHostsApp.swift`

- [ ] **Step 1: Implement app entry with MenuBarExtra**

  Replace `iHostsApp.swift` with:
  ```swift
  import SwiftUI
  import SharedKit

  @main
  struct iHostsApp: App {
      @StateObject private var vm = AppViewModel()

      var body: some Scene {
          MenuBarExtra {
              MenuBarPopoverView()
                  .environmentObject(vm)
          } label: {
              Label("iHosts", systemImage: "network.badge.shield.half.filled")
                  .symbolRenderingMode(.hierarchical)
          }
          .menuBarExtraStyle(.window)

          Window("Hosts Editor", id: "editor") {
              EditorRootView()
                  .environmentObject(vm)
          }
          .defaultSize(width: 900, height: 600)
          .commands {
              CommandGroup(replacing: .newItem) {}
          }
      }
  }
  ```

- [ ] **Step 2: Install helper on first launch**

  Add a task at the bottom of `iHostsApp.swift`, inside `var body`:
  ```swift
  // Inside iHostsApp, add after the Window scene:
  // (This goes at struct level, not inside body)
  ```

  Instead, add this to `AppViewModel.init()` at the end:
  ```swift
  // Inside AppViewModel.init(), after observeAppGroupChanges():
  Task { try? HelperInstaller.installIfNeeded() }
  ```

- [ ] **Step 3: Build and commit**

  ```bash
  git add iHosts/App/
  git commit -m "feat: wire up MenuBarExtra and editor Window scene"
  ```

---

## Task 12: ModeToggleView

**Files:**
- Create: `iHosts/Views/MenuBar/ModeToggleView.swift`

- [ ] **Step 1: Implement ModeToggleView**

  Create `iHosts/Views/MenuBar/ModeToggleView.swift`:
  ```swift
  import SwiftUI

  struct ModeToggleView: View {
      @EnvironmentObject var vm: AppViewModel

      private var isProfileMode: Bool { vm.state.activeProfileId != nil }

      var body: some View {
          Picker("Mode", selection: Binding(
              get: { isProfileMode ? 1 : 0 },
              set: { newValue in
                  if newValue == 0 {
                      vm.activateProfile(nil)
                  } else if let first = vm.state.profiles.first {
                      vm.activateProfile(first.id)
                  }
              }
          )) {
              Text("Modules").tag(0)
              Text("Profile").tag(1)
          }
          .pickerStyle(.segmented)
          .padding(.horizontal)
      }
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add iHosts/Views/MenuBar/ModeToggleView.swift
  git commit -m "feat: add ModeToggleView (Modules/Profile segmented control)"
  ```

---

## Task 13: ModuleListView

**Files:**
- Create: `iHosts/Views/MenuBar/ModuleListView.swift`

- [ ] **Step 1: Implement ModuleListView**

  Create `iHosts/Views/MenuBar/ModuleListView.swift`:
  ```swift
  import SwiftUI
  import SharedKit

  struct ModuleListView: View {
      @EnvironmentObject var vm: AppViewModel

      var body: some View {
          List {
              ForEach($vm.state.modules) { $module in
                  ModuleRowView(module: $module)
              }
              .onDelete { offsets in
                  offsets.forEach { vm.deleteModule(vm.state.modules[$0].id) }
              }
          }
          .listStyle(.sidebar)
          .frame(minHeight: 80)

          Button(action: addModule) {
              Label("Add Module", systemImage: "plus")
          }
          .buttonStyle(.borderless)
          .padding(.horizontal)
      }

      private func addModule() {
          vm.addModule(name: "New Module")
      }
  }

  struct ModuleRowView: View {
      @Binding var module: HostsGroup
      @EnvironmentObject var vm: AppViewModel

      var body: some View {
          Toggle(isOn: $module.isEnabled) {
              Text(module.name)
                  .font(.body)
          }
          .toggleStyle(.switch)
          .onChange(of: module.isEnabled) {
              vm.updateModule(module)
          }
      }
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add iHosts/Views/MenuBar/ModuleListView.swift
  git commit -m "feat: add ModuleListView and ModuleRowView"
  ```

---

## Task 14: ProfileListView

**Files:**
- Create: `iHosts/Views/MenuBar/ProfileListView.swift`

- [ ] **Step 1: Implement ProfileListView**

  Create `iHosts/Views/MenuBar/ProfileListView.swift`:
  ```swift
  import SwiftUI
  import SharedKit

  struct ProfileListView: View {
      @EnvironmentObject var vm: AppViewModel

      var body: some View {
          List(vm.state.profiles) { profile in
              ProfileRowView(profile: profile)
          }
          .listStyle(.sidebar)
          .frame(minHeight: 80)

          Button(action: addProfile) {
              Label("Add Profile", systemImage: "plus")
          }
          .buttonStyle(.borderless)
          .padding(.horizontal)
      }

      private func addProfile() {
          vm.addProfile(name: "New Profile")
      }
  }

  struct ProfileRowView: View {
      let profile: Profile
      @EnvironmentObject var vm: AppViewModel

      private var isActive: Bool { vm.state.activeProfileId == profile.id }

      var body: some View {
          Button {
              vm.activateProfile(isActive ? nil : profile.id)
          } label: {
              HStack {
                  Text(profile.name).font(.body)
                  Spacer()
                  if isActive {
                      Image(systemName: "checkmark")
                          .symbolRenderingMode(.hierarchical)
                          .foregroundStyle(.accent)
                  }
              }
          }
          .buttonStyle(.plain)
      }
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add iHosts/Views/MenuBar/ProfileListView.swift
  git commit -m "feat: add ProfileListView and ProfileRowView"
  ```

---

## Task 15: ApplyButton & MenuBarPopoverView

**Files:**
- Create: `iHosts/Views/MenuBar/ApplyButton.swift`
- Create: `iHosts/Views/MenuBar/MenuBarPopoverView.swift`

- [ ] **Step 1: Implement ApplyButton**

  Create `iHosts/Views/MenuBar/ApplyButton.swift`:
  ```swift
  import SwiftUI

  struct ApplyButton: View {
      @EnvironmentObject var vm: AppViewModel

      var body: some View {
          Button {
              Task { await vm.applyHosts() }
          } label: {
              HStack {
                  if vm.isApplyingHosts {
                      ProgressView().controlSize(.small)
                  }
                  Text(vm.isApplyingHosts ? "Applying…" : "Apply to System")
              }
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(vm.isApplyingHosts)
          .padding(.horizontal)

          if let err = vm.lastError {
              Text(err)
                  .font(.caption)
                  .foregroundStyle(.red)
                  .padding(.horizontal)
          }
      }
  }
  ```

- [ ] **Step 2: Implement MenuBarPopoverView**

  Create `iHosts/Views/MenuBar/MenuBarPopoverView.swift`:
  ```swift
  import SwiftUI

  struct MenuBarPopoverView: View {
      @EnvironmentObject var vm: AppViewModel
      @Environment(\.openWindow) private var openWindow

      private var isProfileMode: Bool { vm.state.activeProfileId != nil }

      var body: some View {
          VStack(alignment: .leading, spacing: 12) {
              HStack {
                  Text("iHosts")
                      .font(.title3.bold())
                  Spacer()
                  Button {
                      openWindow(id: "editor")
                  } label: {
                      Image(systemName: "pencil")
                  }
                  .buttonStyle(.borderless)
                  .help("Open Editor")
              }
              .padding(.horizontal)
              .padding(.top, 12)

              Divider()

              ModeToggleView()

              if isProfileMode {
                  ProfileListView()
              } else {
                  ModuleListView()
              }

              Divider()

              ApplyButton()
                  .padding(.bottom, 12)
          }
          .frame(width: 280)
          .glassBackground(in: .rect(cornerRadius: 12))
      }
  }
  ```

- [ ] **Step 3: Build and run**

  Xcode → Run (`⌘R`)  
  Expected: app appears in menu bar, clicking the icon shows the popover.

- [ ] **Step 4: Commit**

  ```bash
  git add iHosts/Views/MenuBar/
  git commit -m "feat: assemble MenuBarPopoverView with mode toggle, lists, and apply button"
  ```

---

## Task 16: HostsEditorView (Syntax Highlighting)

**Files:**
- Create: `iHosts/Views/Editor/HostsEditorView.swift`

- [ ] **Step 1: Implement syntax highlighter delegate**

  Create `iHosts/Views/Editor/HostsEditorView.swift`:
  ```swift
  import SwiftUI
  import AppKit

  struct HostsEditorView: NSViewRepresentable {
      @Binding var text: String
      var onChange: () -> Void = {}

      func makeCoordinator() -> Coordinator { Coordinator(self) }

      func makeNSView(context: Context) -> NSScrollView {
          let scrollView = NSTextView.scrollableTextView()
          let textView = scrollView.documentView as! NSTextView

          textView.isEditable = true
          textView.isRichText = false
          textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
          textView.isAutomaticQuoteSubstitutionEnabled = false
          textView.isAutomaticDashSubstitutionEnabled = false
          textView.delegate = context.coordinator
          textView.textStorage?.delegate = context.coordinator
          textView.string = text

          return scrollView
      }

      func updateNSView(_ scrollView: NSScrollView, context: Context) {
          let textView = scrollView.documentView as! NSTextView
          if textView.string != text {
              textView.string = text
              context.coordinator.highlight(textView.textStorage!)
          }
      }

      final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
          var parent: HostsEditorView

          init(_ parent: HostsEditorView) { self.parent = parent }

          func textDidChange(_ notification: Notification) {
              guard let tv = notification.object as? NSTextView else { return }
              parent.text = tv.string
              parent.onChange()
          }

          func textStorage(_ storage: NSTextStorage,
                            didProcessEditing editedMask: NSTextStorageEditActions,
                            range: NSRange, changeInLength: Int) {
              guard editedMask.contains(.editedCharacters) else { return }
              highlight(storage)
          }

          func highlight(_ storage: NSTextStorage) {
              let full = NSRange(location: 0, length: storage.length)
              let defaultAttrs: [NSAttributedString.Key: Any] = [
                  .foregroundColor: NSColor.labelColor,
                  .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
              ]
              storage.addAttributes(defaultAttrs, range: full)

              let text = storage.string
              text.enumerateSubstrings(in: text.startIndex..., options: .byLines) { _, range, _, _ in
                  let nsRange = NSRange(range, in: text)
                  let line = String(text[range]).trimmingCharacters(in: .whitespaces)

                  if line.hasPrefix("#") {
                      storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: nsRange)
                      return
                  }

                  let parts = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
                  guard parts.count >= 2 else { return }

                  let ipStr = String(parts[0])
                  if let ipRange = text.range(of: ipStr, range: range) {
                      storage.addAttribute(.foregroundColor,
                                           value: NSColor.systemBlue,
                                           range: NSRange(ipRange, in: text))
                  }
              }
          }
      }
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add iHosts/Views/Editor/HostsEditorView.swift
  git commit -m "feat: add HostsEditorView with NSTextView syntax highlighting"
  ```

---

## Task 17: SidebarView & EditorToolbarView

**Files:**
- Create: `iHosts/Views/Editor/SidebarView.swift`
- Create: `iHosts/Views/Editor/EditorToolbarView.swift`

- [ ] **Step 1: Implement SidebarView**

  Create `iHosts/Views/Editor/SidebarView.swift`:
  ```swift
  import SwiftUI
  import SharedKit

  enum SidebarItem: Hashable {
      case module(UUID)
      case profile(UUID)
  }

  struct SidebarView: View {
      @EnvironmentObject var vm: AppViewModel
      @Binding var selection: SidebarItem?

      var body: some View {
          List(selection: $selection) {
              Section("Modules") {
                  ForEach(vm.state.modules) { mod in
                      Label(mod.name, systemImage: "square.stack")
                          .tag(SidebarItem.module(mod.id))
                  }
                  .onDelete { offsets in
                      offsets.forEach { vm.deleteModule(vm.state.modules[$0].id) }
                  }
              }

              Section("Profiles") {
                  ForEach(vm.state.profiles) { profile in
                      Label(profile.name, systemImage: "person.crop.rectangle.stack")
                          .tag(SidebarItem.profile(profile.id))
                  }
                  .onDelete { offsets in
                      offsets.forEach { vm.deleteProfile(vm.state.profiles[$0].id) }
                  }
              }
          }
          .listStyle(.sidebar)
          .toolbar {
              ToolbarItem(placement: .automatic) {
                  Menu {
                      Button("Add Module") { vm.addModule(name: "New Module") }
                      Button("Add Profile") { vm.addProfile(name: "New Profile") }
                  } label: {
                      Image(systemName: "plus")
                  }
              }
          }
      }
  }
  ```

- [ ] **Step 2: Implement EditorToolbarView**

  Create `iHosts/Views/Editor/EditorToolbarView.swift`:
  ```swift
  import SwiftUI

  struct EditorToolbarView: View {
      @EnvironmentObject var vm: AppViewModel
      var onSave: () -> Void
      var onApply: () -> Void

      var body: some View {
          HStack {
              Button("Save", action: onSave)
                  .keyboardShortcut("s")
                  .buttonStyle(.bordered)

              Button(action: onApply) {
                  HStack(spacing: 4) {
                      if vm.isApplyingHosts { ProgressView().controlSize(.mini) }
                      Text("Apply to System")
                  }
              }
              .buttonStyle(.borderedProminent)
              .disabled(vm.isApplyingHosts)
          }
      }
  }
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add iHosts/Views/Editor/SidebarView.swift iHosts/Views/Editor/EditorToolbarView.swift
  git commit -m "feat: add SidebarView and EditorToolbarView"
  ```

---

## Task 18: EditorRootView

**Files:**
- Create: `iHosts/Views/Editor/EditorRootView.swift`

- [ ] **Step 1: Implement EditorRootView**

  Create `iHosts/Views/Editor/EditorRootView.swift`:
  ```swift
  import SwiftUI
  import SharedKit

  struct EditorRootView: View {
      @EnvironmentObject var vm: AppViewModel
      @State private var selection: SidebarItem? = nil
      @State private var editorVMs: [UUID: EditorViewModel] = [:]

      var body: some View {
          NavigationSplitView {
              SidebarView(selection: $selection)
          } detail: {
              if let selection {
                  editorContent(for: selection)
              } else {
                  ContentUnavailableView(
                      "Select a Module or Profile",
                      systemImage: "doc.text",
                      description: Text("Choose an item from the sidebar to edit its hosts entries.")
                  )
              }
          }
          .toolbar {
              if let selection {
                  EditorToolbarView(
                      onSave: { saveSelection(selection) },
                      onApply: { Task { await vm.applyHosts() } }
                  )
              }
          }
          .navigationTitle("Hosts Editor")
      }

      @ViewBuilder
      private func editorContent(for item: SidebarItem) -> some View {
          switch item {
          case .module(let id):
              if let idx = vm.state.modules.firstIndex(where: { $0.id == id }) {
                  editorView(for: vm.state.modules[idx])
              }
          case .profile(let id):
              if let profile = vm.state.profiles.first(where: { $0.id == id }),
                 let group = profile.groups.first {
                  editorView(for: group)
              } else {
                  Text("This profile has no groups yet.")
                      .foregroundStyle(.secondary)
              }
          }
      }

      private func editorView(for group: HostsGroup) -> some View {
          let evm = editorVMs[group.id, default: EditorViewModel(group: group)]
          return HostsEditorView(text: Binding(
              get: { evm.content },
              set: { evm.content = $0; evm.markDirty() }
          ))
          .onAppear { editorVMs[group.id] = evm }
      }

      private func saveSelection(_ item: SidebarItem) {
          switch item {
          case .module(let id):
              guard let idx = vm.state.modules.firstIndex(where: { $0.id == id }),
                    let evm = editorVMs[id] else { return }
              evm.save(to: &vm.state.modules[idx])
              vm.updateModule(vm.state.modules[idx])
          case .profile(let id):
              guard let pidx = vm.state.profiles.firstIndex(where: { $0.id == id }),
                    let group = vm.state.profiles[pidx].groups.first,
                    let evm = editorVMs[group.id] else { return }
              var g = group
              evm.save(to: &g)
              vm.state.profiles[pidx].groups[0] = g
              vm.updateProfile(vm.state.profiles[pidx])
          }
      }
  }
  ```

- [ ] **Step 2: Build and test editor window**

  Run app, click "Open Editor" in popover.  
  Expected: editor window opens with NavigationSplitView sidebar.

- [ ] **Step 3: Commit**

  ```bash
  git add iHosts/Views/Editor/EditorRootView.swift
  git commit -m "feat: assemble EditorRootView with NavigationSplitView and inline EditorViewModels"
  ```

---

## Task 19: Widget — HostsToggleIntent

**Files:**
- Create: `iHostsWidget/HostsToggleIntent.swift`

- [ ] **Step 1: Implement AppIntent for module toggle**

  Create `iHostsWidget/HostsToggleIntent.swift`:
  ```swift
  import AppIntents
  import WidgetKit
  import SharedKit

  struct ToggleModuleIntent: AppIntent {
      static var title: LocalizedStringResource = "Toggle Hosts Module"

      @Parameter(title: "Module ID")
      var moduleID: String

      init() {}
      init(moduleID: String) { self.moduleID = moduleID }

      func perform() async throws -> some IntentResult {
          let store = HostsStore()
          var state = store.load()

          guard let id = UUID(uuidString: moduleID),
                let idx = state.modules.firstIndex(where: { $0.id == id }) else {
              return .result()
          }

          state.modules[idx].isEnabled.toggle()
          try store.save(state)

          // Notify main app to auto-apply
          CFNotificationCenterPostNotification(
              CFNotificationCenterGetDarwinNotifyCenter(),
              CFNotificationName(AppGroup.darwinNotificationName as CFString),
              nil, nil, true
          )

          WidgetCenter.shared.reloadAllTimelines()
          return .result()
      }
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add iHostsWidget/HostsToggleIntent.swift
  git commit -m "feat: add ToggleModuleIntent for Widget interaction"
  ```

---

## Task 20: Widget — Provider & Views

**Files:**
- Create: `iHostsWidget/HostsWidgetBundle.swift`
- Create: `iHostsWidget/HostsWidgetProvider.swift`
- Create: `iHostsWidget/HostsWidgetView.swift`

- [ ] **Step 1: Implement timeline provider**

  Create `iHostsWidget/HostsWidgetProvider.swift`:
  ```swift
  import WidgetKit
  import SharedKit

  struct HostsWidgetEntry: TimelineEntry {
      let date: Date
      let state: AppState
  }

  struct HostsWidgetProvider: TimelineProvider {
      func placeholder(in context: Context) -> HostsWidgetEntry {
          HostsWidgetEntry(date: .now, state: .empty)
      }

      func getSnapshot(in context: Context, completion: @escaping (HostsWidgetEntry) -> Void) {
          let state = HostsStore().load()
          completion(HostsWidgetEntry(date: .now, state: state))
      }

      func getTimeline(in context: Context, completion: @escaping (Timeline<HostsWidgetEntry>) -> Void) {
          let state = HostsStore().load()
          let entry = HostsWidgetEntry(date: .now, state: state)
          completion(Timeline(entries: [entry], policy: .never))
      }
  }
  ```

- [ ] **Step 2: Implement widget views**

  Create `iHostsWidget/HostsWidgetView.swift`:
  ```swift
  import SwiftUI
  import WidgetKit
  import SharedKit

  struct HostsWidgetView: View {
      let entry: HostsWidgetEntry
      @Environment(\.widgetFamily) var family

      var body: some View {
          switch family {
          case .systemSmall:
              SmallWidgetView(state: entry.state)
          case .systemMedium:
              MediumWidgetView(state: entry.state)
          default:
              SmallWidgetView(state: entry.state)
          }
      }
  }

  struct SmallWidgetView: View {
      let state: AppState

      private var subtitle: String {
          if let id = state.activeProfileId,
             let profile = state.profiles.first(where: { $0.id == id }) {
              return profile.name
          }
          let count = state.modules.filter(\.isEnabled).count
          return "\(count) module\(count == 1 ? "" : "s") active"
      }

      var body: some View {
          VStack(alignment: .leading, spacing: 4) {
              Image(systemName: "network.badge.shield.half.filled")
                  .symbolRenderingMode(.hierarchical)
                  .font(.title2)
              Spacer()
              Text("iHosts").font(.caption.bold())
              Text(subtitle).font(.caption2).foregroundStyle(.secondary)
          }
          .padding()
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .containerBackground(.fill.tertiary, for: .widget)
      }
  }

  struct MediumWidgetView: View {
      let state: AppState

      var body: some View {
          VStack(alignment: .leading, spacing: 6) {
              Text("iHosts").font(.caption.bold())
              ForEach(state.modules.prefix(4)) { module in
                  Button(intent: ToggleModuleIntent(moduleID: module.id.uuidString)) {
                      HStack {
                          Image(systemName: module.isEnabled ? "checkmark.circle.fill" : "circle")
                              .symbolRenderingMode(.hierarchical)
                              .foregroundStyle(module.isEnabled ? .accent : .secondary)
                          Text(module.name).font(.caption)
                          Spacer()
                      }
                  }
                  .buttonStyle(.plain)
              }
              Spacer()
          }
          .padding()
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .containerBackground(.fill.tertiary, for: .widget)
      }
  }
  ```

- [ ] **Step 3: Create widget bundle**

  Create `iHostsWidget/HostsWidgetBundle.swift`:
  ```swift
  import WidgetKit
  import SwiftUI

  @main
  struct iHostsWidgetBundle: WidgetBundle {
      var body: some Widget {
          HostsWidget()
      }
  }

  struct HostsWidget: Widget {
      let kind = "com.debuginn.iHosts.Widget"

      var body: some WidgetConfiguration {
          StaticConfiguration(kind: kind, provider: HostsWidgetProvider()) { (entry: HostsWidgetEntry) in
              HostsWidgetView(entry: entry)
          }
          .configurationDisplayName("iHosts")
          .description("Quickly toggle your hosts modules.")
          .supportedFamilies([.systemSmall, .systemMedium])
      }
  }
  ```

- [ ] **Step 4: Build Widget target**

  Xcode → select `iHostsWidget` scheme → Product → Build  
  Expected: Build succeeded.

- [ ] **Step 5: Add Widget to Notification Center**

  Run app on device → right-click desktop → Edit Widgets → search "iHosts"

- [ ] **Step 6: Commit**

  ```bash
  git add iHostsWidget/
  git commit -m "feat: add Widget Extension with small/medium views and ToggleModuleIntent"
  ```

---

## Task 21: Final Integration Test

- [ ] **Step 1: Run all SharedKit unit tests**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts/SharedKit
  swift test
  ```

  Expected:
  ```
  Test Suite 'HostsComposerTests' passed
  Test Suite 'HostsStoreTests' passed
  ```

- [ ] **Step 2: Smoke test menu bar flow**

  1. Launch app → menu bar icon appears
  2. Click icon → popover opens with Liquid Glass background
  3. Toggle "Modules" / "Profile" → list switches
  4. Click "Apply to System" → loading spinner → hosts updated (check `cat /etc/hosts`)

- [ ] **Step 3: Smoke test editor flow**

  1. Click pencil icon → Editor window opens
  2. Add a module in sidebar → editor shows empty text area
  3. Type `127.0.0.1 myapp.local` → IP turns blue, hostname stays default
  4. Save → Apply → verify `/etc/hosts` contains new entry

- [ ] **Step 4: Smoke test widget**

  1. Add widget to Notification Center
  2. Toggle a module via widget button
  3. Main app auto-applies if running; `/etc/hosts` reflects change

- [ ] **Step 5: Final commit**

  ```bash
  cd ~/Code/src/github.com/debuginn/iHosts
  git add .
  git commit -m "feat: iHosts v1.0 - menu bar hosts manager with module/profile switching and Widget"
  ```
