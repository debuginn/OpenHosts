import XCTest
import Foundation
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
