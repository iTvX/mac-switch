import XCTest
@testable import MacSwitch

final class XcodeCacheDirectoryTests: XCTestCase {
    private func fixture() throws -> (home: URL, cache: URL, outside: URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("cache-safety-\(UUID().uuidString)")
        let cache = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let outside = home.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: outside.appendingPathComponent("sentinel"))
        return (home, cache, outside)
    }

    func testRejectsSymlinkedCacheRootBeforeRemovingAnyFiles() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        try FileManager.default.removeItem(at: f.cache)
        try FileManager.default.createSymbolicLink(at: f.cache, withDestinationURL: f.outside)
        XCTAssertThrowsError(try XcodeCacheDirectory(homeDirectory: f.home))
        XCTAssertEqual(try String(contentsOf: f.outside.appendingPathComponent("sentinel"), encoding: .utf8), "keep")
    }

    func testRejectsSymlinkedAncestor() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        let parent = f.cache.deletingLastPathComponent()
        let moved = f.home.appendingPathComponent("moved-Xcode")
        try FileManager.default.moveItem(at: parent, to: moved)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
        XCTAssertThrowsError(try XcodeCacheDirectory(homeDirectory: f.home))
    }

    func testReplacingCacheRootAfterOpenCannotRedirectDeletion() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        try Data("cache".utf8).write(to: f.cache.appendingPathComponent("sentinel"))
        let cache = try XcodeCacheDirectory(homeDirectory: f.home)
        XCTAssertEqual(try cache.itemNames(), ["sentinel"])
        let moved = f.home.appendingPathComponent("original-cache")
        try FileManager.default.moveItem(at: f.cache, to: moved)
        try FileManager.default.createSymbolicLink(at: f.cache, withDestinationURL: f.outside)
        try cache.removeItem(named: "sentinel")
        XCTAssertEqual(try String(contentsOf: f.outside.appendingPathComponent("sentinel"), encoding: .utf8), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.appendingPathComponent("sentinel").path))
    }

    func testNestedCacheRemovalUnlinksSymlinksWithoutFollowingThem() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        let nested = f.cache.appendingPathComponent("Build/Products")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: nested.appendingPathComponent("object"))
        try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent("outside"), withDestinationURL: f.outside)
        let cache = try XcodeCacheDirectory(homeDirectory: f.home)
        try cache.removeItem(named: "Build")
        XCTAssertTrue(try cache.itemNames().isEmpty)
        XCTAssertEqual(try String(contentsOf: f.outside.appendingPathComponent("sentinel"), encoding: .utf8), "keep")
    }

    func testRejectsTraversalAndAbsoluteNames() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        let cache = try XcodeCacheDirectory(homeDirectory: f.home)
        for name in ["", ".", "..", "../../../../Documents", f.outside.path, "name\0suffix"] {
            XCTAssertThrowsError(try cache.removeItem(named: name))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.outside.appendingPathComponent("sentinel").path))
    }
}
