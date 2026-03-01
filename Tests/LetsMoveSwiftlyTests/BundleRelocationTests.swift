import Foundation
import XCTest
@testable import LetsMoveSwiftly

// MARK: - Test Doubles

/// A `FileManager` subclass that fails the relocation move/copy but allows the
/// backup and restore moves, identified by URL rather than call order.
///
/// Set `targetAppName` to the `.app` bundle name at the destination. Any
/// `moveItem`/`copyItem` call whose destination matches that name (i.e. the
/// relocation step) will throw.
private class RelocationFailingFileManager: FileManager {
    let targetAppName: String

    init(targetAppName: String = "TestApp.app") {
        self.targetAppName = targetAppName
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// The relocation step moves/copies INTO the target name from a non-backup source.
    /// The restore step also targets the same name but comes FROM a `.backup-` path.
    private func isRelocation(source: URL, destination: URL) -> Bool {
        destination.lastPathComponent == targetAppName
            && !source.path.contains(".backup-")
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if isRelocation(source: srcURL, destination: dstURL) {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "Simulated relocation failure"]
            )
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if isRelocation(source: srcURL, destination: dstURL) {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "Simulated relocation failure"]
            )
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }
}

/// A `FileManager` subclass that fails both the relocation *and* the backup
/// restoration, exercising the `RelocationError` double-failure path.
private class DoubleFailingFileManager: FileManager {
    let targetAppName: String

    init(targetAppName: String = "TestApp.app") {
        self.targetAppName = targetAppName
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// Any move/copy whose destination is the target app name fails — both the
    /// relocation (from source) and the restore (from backup).
    private func isTargetDestination(_ url: URL) -> Bool {
        url.lastPathComponent == targetAppName && !url.path.contains(".backup-")
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if isTargetDestination(dstURL) {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "Simulated failure"]
            )
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if isTargetDestination(dstURL) {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "Simulated failure"]
            )
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }
}

/// A `FileManager` subclass that writes a partial target (creates the directory
/// but then fails), exercising the partial-copy cleanup path before restore.
private class PartialCopyFileManager: FileManager {
    let targetAppName: String

    init(targetAppName: String = "TestApp.app") {
        self.targetAppName = targetAppName
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    private func isRelocation(source: URL, destination: URL) -> Bool {
        destination.lastPathComponent == targetAppName
            && !source.path.contains(".backup-")
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if isRelocation(source: srcURL, destination: dstURL) {
            // Simulate a partial write: create the target directory, then fail.
            try FileManager.default.createDirectory(
                at: dstURL, withIntermediateDirectories: true
            )
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteOutOfSpaceError,
                userInfo: [NSLocalizedDescriptionKey: "Simulated out-of-space failure"]
            )
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if isRelocation(source: srcURL, destination: dstURL) {
            try FileManager.default.createDirectory(
                at: dstURL, withIntermediateDirectories: true
            )
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteOutOfSpaceError,
                userInfo: [NSLocalizedDescriptionKey: "Simulated out-of-space failure"]
            )
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }
}

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

    // MARK: - AppleScript Command Builder

    func testAppleScriptEscapesSingleQuotesInPaths() {
        let script = LetsMoveSwiftly.appleScriptForRelocate(
            sourcePath: "/tmp/Bob's App.app",
            destinationPath: "/Applications/Bob's App.app"
        )

        // The shell escape produces '\'' which the AppleScript escape then doubles
        // the backslash to '\\'' — AppleScript interprets \\\\ back to \\ at runtime,
        // restoring the correct shell escape sequence.
        XCTAssertTrue(script.contains("Bob'\\\\''s App.app"), "Single quotes should be shell-escaped")
    }

    func testAppleScriptEscapesDoubleQuotesInPaths() {
        let script = LetsMoveSwiftly.appleScriptForRelocate(
            sourcePath: "/tmp/My \"Cool\" App.app",
            destinationPath: "/Applications/My \"Cool\" App.app"
        )

        // Double quotes must be escaped for the AppleScript string literal.
        XCTAssertFalse(
            script.contains("My \"Cool\""),
            "Raw double quotes must not appear unescaped in the AppleScript string"
        )
        XCTAssertTrue(
            script.contains("My \\\"Cool\\\""),
            "Double quotes should be escaped for AppleScript"
        )
    }

    func testAppleScriptEscapesBackslashesInPaths() {
        let script = LetsMoveSwiftly.appleScriptForRelocate(
            sourcePath: "/tmp/Back\\slash.app",
            destinationPath: "/Applications/Back\\slash.app"
        )

        // Backslashes must be escaped for the AppleScript string literal.
        XCTAssertTrue(
            script.contains("Back\\\\slash.app"),
            "Backslashes should be escaped for AppleScript"
        )
    }

    func testAppleScriptPlainPathsProduceValidCommand() {
        let script = LetsMoveSwiftly.appleScriptForRelocate(
            sourcePath: "/tmp/TestApp.app",
            destinationPath: "/Applications/TestApp.app"
        )

        XCTAssertTrue(script.hasPrefix("do shell script \""))
        XCTAssertTrue(script.hasSuffix("\" with administrator privileges"))
        XCTAssertTrue(script.contains("cp -pR"))
        // The script should back up the existing app, not delete it outright.
        XCTAssertTrue(
            script.contains(".backup-"),
            "Script should use a backup path for safe replacement"
        )
        XCTAssertTrue(
            script.contains("mv"),
            "Script should move (not delete) the existing app aside"
        )
    }

    func testRestoresExistingAppWhenRelocateFails() throws {
        let appBundle = try createFakeAppBundle(in: "source", markerContent: "new-version")
        let destinationDirectory = try createDirectory("destination")

        // Place an "old" copy at the destination that should survive a failed relocation.
        let existingApp = destinationDirectory.appendingPathComponent("TestApp.app")
        try FileManager.default.createDirectory(at: existingApp, withIntermediateDirectories: true)
        try "old-version".write(
            to: existingApp.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        // Use a FileManager subclass that allows the backup move but forces the
        // relocation move/copy to fail — exercising the actual rollback path.
        let failingFileManager = RelocationFailingFileManager()

        XCTAssertThrowsError(
            try LetsMoveSwiftly.relocateBundle(
                from: appBundle,
                to: destinationDirectory,
                fileManager: failingFileManager
            ),
            "Should throw when relocation fails"
        )

        // The original app must still be present and unmodified.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: existingApp.path),
            "Existing app should be restored after a failed relocation"
        )
        let content = try String(
            contentsOf: existingApp.appendingPathComponent("Info.plist"),
            encoding: .utf8
        )
        XCTAssertEqual(content, "old-version", "Restored app should contain the original content")
    }

    func testThrowsRelocationErrorWhenBothRelocationAndRestorationFail() throws {
        let appBundle = try createFakeAppBundle(in: "source", markerContent: "new-version")
        let destinationDirectory = try createDirectory("destination")

        // Place an existing app so the backup path is exercised.
        let existingApp = destinationDirectory.appendingPathComponent("TestApp.app")
        try FileManager.default.createDirectory(at: existingApp, withIntermediateDirectories: true)
        try "old-version".write(
            to: existingApp.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        let doubleFailingFileManager = DoubleFailingFileManager()

        XCTAssertThrowsError(
            try LetsMoveSwiftly.relocateBundle(
                from: appBundle,
                to: destinationDirectory,
                fileManager: doubleFailingFileManager
            ),
            "Should throw when both relocation and restoration fail"
        ) { error in
            guard let relocationError = error as? LetsMoveSwiftly.RelocationError else {
                XCTFail("Expected RelocationError, got \(type(of: error)): \(error)")
                return
            }
            XCTAssertTrue(
                relocationError.backupURL.path.contains(".backup-"),
                "backupURL should point to the backup location"
            )
            XCTAssertNotNil(relocationError.errorDescription, "Should provide a localized description")
            XCTAssertNotNil(relocationError.recoverySuggestion, "Should provide a recovery suggestion")
        }
    }

    func testCleansUpPartialCopyBeforeRestoringBackup() throws {
        let appBundle = try createFakeAppBundle(in: "source", markerContent: "new-version")
        let destinationDirectory = try createDirectory("destination")

        // Place an existing app so the backup path is exercised.
        let existingApp = destinationDirectory.appendingPathComponent("TestApp.app")
        try FileManager.default.createDirectory(at: existingApp, withIntermediateDirectories: true)
        try "old-version".write(
            to: existingApp.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        // This file manager creates a partial target directory before failing,
        // verifying the cleanup-before-restore logic.
        let partialCopyFileManager = PartialCopyFileManager()

        XCTAssertThrowsError(
            try LetsMoveSwiftly.relocateBundle(
                from: appBundle,
                to: destinationDirectory,
                fileManager: partialCopyFileManager
            ),
            "Should throw when copy fails"
        )

        // The original app must be restored despite the partial copy.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: existingApp.path),
            "Existing app should be restored after partial copy failure"
        )
        let content = try String(
            contentsOf: existingApp.appendingPathComponent("Info.plist"),
            encoding: .utf8
        )
        XCTAssertEqual(content, "old-version", "Restored app should contain the original content")
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
