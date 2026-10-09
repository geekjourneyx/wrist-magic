import XCTest
import WristMagicCore
final class CoreImportTests: XCTestCase {
    func testCoreModuleImportsOnBothPlatforms() {
        XCTAssertEqual(TestFactory.linkedProtocolVersion, TestFactory.expectedProtocolVersion)
        XCTAssertEqual(CoreBaseline.protocolVersion, 1)
    }
}
