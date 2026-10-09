import WristMagicCore
import XCTest

final class CoreImportTests: XCTestCase {
  func testCoreModuleImportsOnBothPlatforms() {
    XCTAssertEqual(CoreBaseline.protocolVersion, 1)
  }
}
