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
