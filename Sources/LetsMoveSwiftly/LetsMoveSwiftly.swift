import AppKit
import OSLog

/// A lightweight utility that prompts users to move your macOS app to `/Applications/` on first launch.
///
/// macOS apps distributed outside the App Store (via ZIP, DMG, or direct download) can be launched
/// from anywhere — Downloads, Desktop, or even a mounted disk image. This causes problems:
/// - [App Translocation](https://developer.apple.com/documentation/security/translocation)
///   runs the app from a randomized read-only path, breaking auto-updates and file associations
/// - Spotlight indexing and Launch Services registration work best from `/Applications/`
/// - Users expect apps to live in `/Applications/`
///
/// `LetsMoveSwiftly` handles this with a single call at app launch. It shows a native dialog
/// asking the user to move the app, handles the file operation, and relaunches from the new location.
///
/// The feature is **automatically disabled** for Mac App Store installations, which handle
/// placement themselves.
///
/// ## Usage
///
/// ```swift
/// import LetsMoveSwiftly
/// import SwiftUI
///
/// @main
/// struct MyApp: App {
///     init() {
///         LetsMoveSwiftly.moveToApplicationsIfNecessary()
///     }
///
///     var body: some Scene {
///         WindowGroup { ContentView() }
///     }
/// }
/// ```
///
/// ## Design
///
/// The decision logic (``shouldOfferToMove(bundlePath:receiptURL:fileManager:defaults:)``)
/// and file operations (``relocateBundle(from:to:fileManager:)``) are separated from UI
/// and exposed as `public` methods, making them independently testable.
///
/// Inspired by [LetsMove](https://github.com/potionfactory/LetsMove) (public domain)
/// and [AppMover](https://github.com/OskarGroth/AppMover).
public enum LetsMoveSwiftly {

    /// `UserDefaults` key set to `true` when the user chooses "Don't Move".
    ///
    /// You can reset this to prompt the user again:
    /// ```swift
    /// UserDefaults.standard.removeObject(forKey: LetsMoveSwiftly.dontAskAgainKey)
    /// ```
    public static let dontAskAgainKey = "LetsMoveSwiftly.dontAskAgain"

    private static let logger = Logger(
        subsystem: "com.nicemohawk.LetsMoveSwiftly",
        category: "move"
    )

    // MARK: - Decision Logic

    /// Determines whether the app should offer to move to `/Applications/`.
    ///
    /// Returns `false` when any of these conditions are met:
    /// - The app was installed from the Mac App Store (a valid receipt file exists on disk)
    /// - The app is already running from `/Applications/` or `~/Applications/`
    /// - The user previously chose "Don't Move"
    ///
    /// All parameters have sensible defaults for production use. Override them in tests
    /// to exercise each code path without touching the real filesystem or user defaults.
    ///
    /// - Parameters:
    ///   - bundlePath: The app bundle's path. Defaults to `Bundle.main.bundlePath`.
    ///   - receiptURL: The App Store receipt URL. Defaults to `Bundle.main.appStoreReceiptURL`.
    ///   - fileManager: The file manager used to check file existence. Defaults to `.default`.
    ///   - defaults: The user defaults store for the "don't ask again" flag. Defaults to `.standard`.
    /// - Returns: `true` if the app should prompt the user to move.
    public static func shouldOfferToMove(
        bundlePath: String = Bundle.main.bundlePath,
        receiptURL: URL? = Bundle.main.appStoreReceiptURL,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> Bool {
        // App Store installations always land in /Applications — no prompt needed.
        // We check that the receipt file actually exists on disk, not just the URL property,
        // because non-App Store builds may still have a receiptURL that points nowhere.
        if let receiptURL, fileManager.fileExists(atPath: receiptURL.path) {
            return false
        }

        if isInApplicationsFolder(bundlePath) {
            return false
        }

        if defaults.bool(forKey: dontAskAgainKey) {
            return false
        }

        return true
    }

    /// Checks whether the given path is inside `/Applications/` or `~/Applications/`.
    ///
    /// Both the system-wide and per-user Applications folders are recognized.
    /// Paths are normalized before comparison to handle symlinks and trailing slashes.
    ///
    /// - Parameter path: An absolute filesystem path (typically a `.app` bundle path).
    /// - Returns: `true` if the path is inside an Applications folder.
    public static func isInApplicationsFolder(_ path: String) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath

        if normalizedPath.hasPrefix("/Applications/") {
            return true
        }

        let userApplicationsFolder = NSHomeDirectory() + "/Applications/"
        if normalizedPath.hasPrefix(userApplicationsFolder) {
            return true
        }

        return false
    }

    // MARK: - File Operations

    /// Moves or copies the app bundle into the destination directory.
    ///
    /// When the source directory is writable (e.g., the app was extracted from a ZIP into Downloads),
    /// the bundle is **moved**. When the source is read-only (e.g., a mounted DMG), the bundle is
    /// **copied** instead.
    ///
    /// If an app with the same name already exists at the destination, it is removed first.
    ///
    /// - Parameters:
    ///   - source: The current app bundle URL (e.g., `Bundle.main.bundleURL`).
    ///   - destinationDirectory: The target directory (typically `/Applications`).
    ///   - fileManager: The file manager to use for file operations. Defaults to `.default`.
    /// - Returns: The URL of the app in its new location.
    /// - Throws: Any `FileManager` error if the move/copy or cleanup fails.
    @discardableResult
    public static func relocateBundle(
        from source: URL,
        to destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let targetURL = destinationDirectory.appendingPathComponent(source.lastPathComponent)

        // Remove an existing copy so the move/copy doesn't fail with "file exists".
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }

        let sourceDirectory = source.deletingLastPathComponent().path
        if fileManager.isWritableFile(atPath: sourceDirectory) {
            try fileManager.moveItem(at: source, to: targetURL)
        } else {
            // Read-only source (e.g., mounted DMG) — copy instead.
            try fileManager.copyItem(at: source, to: targetURL)
        }

        return targetURL
    }

    // MARK: - Main Entry Point

    /// Checks whether the app should move to `/Applications/`, prompts the user, and handles
    /// the move and relaunch if they agree.
    ///
    /// Call this once at app launch — typically in your `App.init()` or
    /// `applicationWillFinishLaunching(_:)`. It runs synchronously and returns immediately
    /// if no action is needed.
    ///
    /// **Behavior:**
    /// - Returns silently if the app is already in `/Applications/`, was installed from the
    ///   App Store, or the user previously chose "Don't Move".
    /// - Shows a native `NSAlert` with three options: "Move to Applications", "Not Now",
    ///   and "Don't Move".
    /// - If an existing copy is found in `/Applications/`, shows a confirmation before replacing.
    /// - After a successful move, relaunches the app from its new location.
    /// - If the move fails, shows an error alert and continues running from the current location.
    ///
    /// ```swift
    /// // SwiftUI
    /// @main
    /// struct MyApp: App {
    ///     init() {
    ///         LetsMoveSwiftly.moveToApplicationsIfNecessary()
    ///     }
    ///     var body: some Scene { WindowGroup { ContentView() } }
    /// }
    ///
    /// // AppKit
    /// class AppDelegate: NSObject, NSApplicationDelegate {
    ///     func applicationWillFinishLaunching(_ notification: Notification) {
    ///         LetsMoveSwiftly.moveToApplicationsIfNecessary()
    ///     }
    /// }
    /// ```
    @MainActor
    public static func moveToApplicationsIfNecessary() {
        guard shouldOfferToMove() else { return }

        let appName = Bundle.main.localizedAppName

        switch Alerts.showMoveAlert(appName: appName) {
        case .move:
            let source = URL(fileURLWithPath: Bundle.main.bundlePath)
            let applicationsDirectory = URL(fileURLWithPath: "/Applications")

            // If a copy already exists in /Applications, confirm replacement.
            let target = applicationsDirectory.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                guard Alerts.showReplaceAlert(appName: appName) else { return }
            }

            do {
                let newURL = try relocateBundle(from: source, to: applicationsDirectory)
                logger.info("Moved app to \(newURL.path)")
                Alerts.relaunch(at: newURL)
            } catch {
                logger.error("Failed to move app: \(error.localizedDescription)")
                Alerts.showErrorAlert(message: error.localizedDescription)
            }
        case .dontMove:
            UserDefaults.standard.set(true, forKey: dontAskAgainKey)
        case .notNow:
            break
        }
    }

    // MARK: - Alert Response

    /// The user's response to the "Move to Applications?" dialog.
    public enum MoveAlertResponse: Sendable {
        /// The user chose to move the app.
        case move
        /// The user chose "Don't Move" — the prompt will not appear again.
        case dontMove
        /// The user chose "Not Now" — the prompt will appear on the next launch.
        case notNow
    }
}

// MARK: - Bundle Helpers

extension Bundle {
    /// The localized display name of the app, with sensible fallbacks.
    var localizedAppName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? "The Application"
    }
}
