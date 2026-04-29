import XCTest
@testable import SharedKit

final class SharedKitTests: XCTestCase {
    func test_placeholder() {
        // SharedKit now only contains HostsHelperProtocol and AppGroup.
        XCTAssertEqual(AppGroup.identifier, "group.com.debuginn.OpenHosts")
    }
}
