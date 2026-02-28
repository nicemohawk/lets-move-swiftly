import XCTest
@testable import LetsMoveSwiftly

final class BundleRelocationTests: XCTestCase {

    /// Creates a temporary directory tree for each test, cleaned up automatically.
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LetsMoveSwiftlyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        // Restore write permissions on any read-only directories before cleanup.
        if let temporaryDirectory {
            let enumerator = FileManager.default.enumerator(
                at: temporaryDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            while let itemURL = enumerator?.nextObject() as? URL {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: itemURL.path
                )
            }
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Creates a fake `.app` bundle directory with a marker file inside.
    private func createFakeAppBundle(
        named name: String = "TestApp.app",
        in directory: String,
        markerContent: String = "marker"
    ) throws -> URL {
        let parentDirectory = temporaryDirectory.appendingPathComponent(directory)
        let appBundle = parentDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)
        try markerContent.write(
            to: appBundle.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )
        return appBundle
    }

    /// Creates an empty directory at the given sub-path.
    private func createDirectory(_ subpath: String) throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent(subpath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Tests

    func testMovesAppWhenSourceIsWritable() throws {
        let appBundle = try createFakeAppBundle(in: "source")
        let destinationDirectory = try createDirectory("destination")

        let result = try LetsMoveSwiftly.relocateBundle(
            from: appBundle,
            to: destinationDirectory
        )

        XCTAssertEqual(result.lastPathComponent, "TestApp.app")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: result.path),
            "App should exist at destination"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: appBundle.path),
            "Source should be removed after move"
        )
    }

    func testCopiesAppWhenSourceIsReadOnly() throws {
        let appBundle = try createFakeAppBundle(in: "readonly-source")
        let destinationDirectory = try createDirectory("destination")

        // Make the source directory read-only to simulate a mounted DMG.
        let sourceParent = appBundle.deletingLastPathComponent()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: sourceParent.path
        )

        let result = try LetsMoveSwiftly.relocateBundle(
            from: appBundle,
            to: destinationDirectory
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: result.path),
            "Copy should exist at destination"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appBundle.path),
            "Source should still exist after copy (read-only source is not deleted)"
        )
    }

    func testReplacesExistingAppAtDestination() throws {
        let appBundle = try createFakeAppBundle(in: "source", markerContent: "new-version")
        let destinationDirectory = try createDirectory("destination")

        // Place an "old" copy at the destination.
        let existingApp = destinationDirectory.appendingPathComponent("TestApp.app")
        try FileManager.default.createDirectory(at: existingApp, withIntermediateDirectories: true)
        try "old-version".write(
            to: existingApp.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        let result = try LetsMoveSwiftly.relocateBundle(
            from: appBundle,
            to: destinationDirectory
        )

        let content = try String(
            contentsOf: result.appendingPathComponent("Info.plist"),
            encoding: .utf8
        )
        XCTAssertEqual(content, "new-version", "Old copy should be replaced with new one")
    }

    func testThrowsWhenDestinationIsNotWritable() throws {
        let appBundle = try createFakeAppBundle(in: "source")
        let destinationDirectory = try createDirectory("readonly-destination")

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: destinationDirectory.path
        )

        XCTAssertThrowsError(
            try LetsMoveSwiftly.relocateBundle(
                from: appBundle,
                to: destinationDirectory
            ),
            "Should throw when destination is not writable"
        )
    }
}
