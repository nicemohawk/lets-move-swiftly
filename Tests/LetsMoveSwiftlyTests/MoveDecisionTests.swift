import XCTest
@testable import LetsMoveSwiftly

final class MoveDecisionTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LetsMoveSwiftlyTests")!
        defaults.removePersistentDomain(forName: "LetsMoveSwiftlyTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "LetsMoveSwiftlyTests")
        super.tearDown()
    }

    // MARK: - shouldOfferToMove: App Store Detection

    func testSkipsWhenAppStoreReceiptExistsOnDisk() throws {
        let temporaryReceipt = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-receipt-\(UUID().uuidString)")
        try Data().write(to: temporaryReceipt)
        defer { try? FileManager.default.removeItem(at: temporaryReceipt) }

        let result = LetsMoveSwiftly.shouldOfferToMove(
            bundlePath: "/Users/test/Downloads/MyApp.app",
            receiptURL: temporaryReceipt,
            defaults: defaults
        )

        XCTAssertFalse(result, "Should skip when App Store receipt exists on disk")
    }

    func testOffersToMoveWhenReceiptURLExistsButFileDoesNot() {
        let missingReceipt = URL(fileURLWithPath: "/nonexistent/path/receipt")

        let result = LetsMoveSwiftly.shouldOfferToMove(
            bundlePath: "/Users/test/Downloads/MyApp.app",
            receiptURL: missingReceipt,
            defaults: defaults
        )

        XCTAssertTrue(result, "Should offer to move when receipt URL is set but file doesn't exist")
    }

    func testOffersToMoveWhenReceiptURLIsNil() {
        let result = LetsMoveSwiftly.shouldOfferToMove(
            bundlePath: "/Users/test/Downloads/MyApp.app",
            receiptURL: nil,
            defaults: defaults
        )

        XCTAssertTrue(result, "Should offer to move when receipt URL is nil")
    }

    // MARK: - shouldOfferToMove: Already in Applications

    func testSkipsWhenInSystemApplicationsFolder() {
        let result = LetsMoveSwiftly.shouldOfferToMove(
            bundlePath: "/Applications/MyApp.app",
            receiptURL: nil,
            defaults: defaults
        )

        XCTAssertFalse(result, "Should skip when already in /Applications")
    }

    func testSkipsWhenInApplicationsSubfolder() {
        let result = LetsMoveSwiftly.shouldOfferToMove(
            bundlePath: "/Applications/Utilities/MyApp.app",
            receiptURL: nil,
            defaults: defaults
        )

        XCTAssertFalse(result, "Should skip when in /Applications subfolder")
    }

    func testSkipsWhenInUserApplicationsFolder() {
        let userApplicationsPath = NSHomeDirectory() + "/Applications/MyApp.app"

        let result = LetsMoveSwiftly.shouldOfferToMove(
            bundlePath: userApplicationsPath,
            receiptURL: nil,
            defaults: defaults
        )

        XCTAssertFalse(result, "Should skip when in ~/Applications")
    }

    // MARK: - shouldOfferToMove: User Preference

    func testSkipsWhenUserPreviouslyDeclined() {
        defaults.set(true, forKey: LetsMoveSwiftly.dontAskAgainKey)

        let result = LetsMoveSwiftly.shouldOfferToMove(
            bundlePath: "/Users/test/Downloads/MyApp.app",
            receiptURL: nil,
            defaults: defaults
        )

        XCTAssertFalse(result, "Should skip when user previously chose 'Don't Move'")
    }

    // MARK: - shouldOfferToMove: Should Prompt

    func testOffersToMoveFromDownloadsFolder() {
        let result = LetsMoveSwiftly.shouldOfferToMove(
            bundlePath: "/Users/test/Downloads/MyApp.app",
            receiptURL: nil,
            defaults: defaults
        )

        XCTAssertTrue(result, "Should offer to move when in Downloads")
    }

    func testOffersToMoveFromDesktop() {
        let result = LetsMoveSwiftly.shouldOfferToMove(
            bundlePath: "/Users/test/Desktop/MyApp.app",
            receiptURL: nil,
            defaults: defaults
        )

        XCTAssertTrue(result, "Should offer to move when on Desktop")
    }

    // MARK: - isInApplicationsFolder

    func testRecognizesSystemApplicationsFolder() {
        XCTAssertTrue(LetsMoveSwiftly.isInApplicationsFolder("/Applications/MyApp.app"))
    }

    func testRecognizesApplicationsSubfolder() {
        XCTAssertTrue(LetsMoveSwiftly.isInApplicationsFolder("/Applications/Utilities/SomeTool.app"))
    }

    func testRecognizesUserApplicationsFolder() {
        let path = NSHomeDirectory() + "/Applications/MyApp.app"
        XCTAssertTrue(LetsMoveSwiftly.isInApplicationsFolder(path))
    }

    func testRejectsDownloadsFolder() {
        XCTAssertFalse(LetsMoveSwiftly.isInApplicationsFolder("/Users/test/Downloads/MyApp.app"))
    }

    func testRejectsDesktopFolder() {
        XCTAssertFalse(LetsMoveSwiftly.isInApplicationsFolder("/Users/test/Desktop/MyApp.app"))
    }

    func testRejectsTmpFolder() {
        XCTAssertFalse(LetsMoveSwiftly.isInApplicationsFolder("/tmp/MyApp.app"))
    }
}
