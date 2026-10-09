import XCTest
import WristMagicCore
final class CoreImportTests: XCTestCase {
    func testCoreModuleImportsOnBothPlatforms() {
        XCTAssertEqual(CoreBaseline.protocolVersion, 1)
    }
}
