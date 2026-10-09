import XCTest
@testable import WristMagiciOS

@MainActor final class ClipSharingTests: XCTestCase {
  func testRepeatedSaveIsIdempotentAndPersistsAcrossContainerRelocation() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    var writes = 0
    let saver = PhotoSaver(defaults: defaults, permission: { true }, write: { _ in writes += 1 })
    let original = URL(fileURLWithPath: "/old/container/clip.mp4")
    try await saver.save(url: original); try await saver.save(url: original)
    XCTAssertEqual(writes, 1)
    let relocated = PhotoSaver(defaults: defaults, permission: { XCTFail("Already saved must not request permission"); return false }, write: { _ in XCTFail("Already saved must not duplicate asset") })
    let newURL = URL(fileURLWithPath: "/new/container/clip.mp4")
    XCTAssertTrue(relocated.isSaved(newURL)); try await relocated.save(url: newURL)
  }
  func testPhotoDeniedPreservesVideoForSystemShare() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("clip.mp4"); try Data([1, 2, 3]).write(to: file)
    let saver = PhotoSaver(defaults: UserDefaults(suiteName: UUID().uuidString)!, permission: { false }, write: { _ in XCTFail("Denied Photos cannot write") })
    do { try await saver.save(url: file); XCTFail("Denied must throw") }
    catch PhotoSaveError.denied { }
    XCTAssertFalse(saver.isSaved(file)); XCTAssertFalse(saver.saving)
    XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
  }
}
