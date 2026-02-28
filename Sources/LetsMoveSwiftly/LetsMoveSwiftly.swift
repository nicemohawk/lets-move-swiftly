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
    /// - The app is running inside the macOS app sandbox (sandboxed apps cannot move themselves)
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
    ///   - isSandboxed: Whether the app is running in the macOS app sandbox. Defaults to runtime detection.
    /// - Returns: `true` if the app should prompt the user to move.
    public static func shouldOfferToMove(
        bundlePath: String = Bundle.main.bundlePath,
        receiptURL: URL? = Bundle.main.appStoreReceiptURL,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        isSandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    ) -> Bool {
        // Sandboxed apps cannot perform the file operations needed to move themselves.
        // This covers App Store builds, development builds with sandbox enabled, and any
        // other sandboxed context. The admin-privilege fallback (NSAppleScript) is also
        // blocked by the sandbox, so there's no point in prompting.
        if isSandboxed {
            return false
        }

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
        let userApplicationsFolder = NSHomeDirectory() + "/Applications/"
        return normalizedPath.hasPrefix("/Applications/") || normalizedPath.hasPrefix(userApplicationsFolder)
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

    // MARK: - Authorized File Operations

    /// The result of an authorized (admin-privileged) file operation.
    public enum AuthorizedInstallResult: Sendable {
        /// The operation succeeded.
        case success
        /// The user cancelled the authentication dialog.
        case cancelled
        /// The operation failed with an error description.
        case failed(String)
    }

    /// Copies the app bundle to the destination using administrator privileges.
    ///
    /// This triggers the standard macOS authentication dialog (Touch ID / password) via
    /// AppleScript's `do shell script ... with administrator privileges`. The system Security
    /// framework handles the credential prompt — the app never sees the password.
    ///
    /// This is the same approach used by [AppMover](https://github.com/OskarGroth/AppMover)
    /// and is the standard pattern for non-sandboxed macOS apps that need one-time privilege
    /// escalation.
    ///
    /// - Parameters:
    ///   - source: The current app bundle URL.
    ///   - destination: The full target URL (e.g., `/Applications/MyApp.app`).
    /// - Returns: The result of the operation.
    public static func authorizedRelocateBundle(
        from source: URL,
        to destination: URL
    ) -> AuthorizedInstallResult {
        // Safety: only operate on .app bundles.
        guard destination.pathExtension == "app" else {
            return .failed("Destination is not an .app bundle.")
        }

        // Escape any single quotes in the paths so they are safe to embed in the
        // single-quoted shell arguments below (replace ' with '\'').
        let sourcePath = source.path.replacingOccurrences(of: "'", with: "'\\''")
        let destinationPath = destination.path.replacingOccurrences(of: "'", with: "'\\''")

        // Shell command: remove any existing copy, then copy the bundle preserving permissions.
        // Paths are wrapped in single quotes and any embedded single quotes are escaped above.
        let shellCommand = "rm -rf '\(destinationPath)' && cp -pR '\(sourcePath)' '\(destinationPath)'"
        let appleScriptSource = "do shell script \"\(shellCommand)\" with administrator privileges"

        guard let script = NSAppleScript(source: appleScriptSource) else {
            return .failed("Failed to create authorization script.")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            // Error -128 is userCanceledErr — the user dismissed the auth dialog.
            if (errorInfo[NSAppleScript.errorNumber] as? Int16) == -128 {
                return .cancelled
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "Authorization failed."
            return .failed(message)
        }

        return .success
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
    /// - Tries a standard `FileManager` move/copy first. If that fails (e.g., `/Applications/`
    ///   requires admin privileges), falls back to an authenticated copy via AppleScript
    ///   which presents the macOS Touch ID / password dialog.
    /// - After a successful move, relaunches the app from its new location.
    /// - If both approaches fail, shows an error alert and continues from the current location.
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
            let target = applicationsDirectory.appendingPathComponent(source.lastPathComponent)

            // If a copy already exists in /Applications, confirm replacement.
            if FileManager.default.fileExists(atPath: target.path) {
                guard Alerts.showReplaceAlert(appName: appName) else { return }
            }

            // Try the standard FileManager approach first (works when the user has write access).
            do {
                let newURL = try relocateBundle(from: source, to: applicationsDirectory)
                logger.info("Moved app to \(newURL.path)")
                Alerts.relaunch(at: newURL)
                return
            } catch {
                logger.info("Standard move failed (\(error.localizedDescription)), requesting admin privileges")
            }

            // Fall back to an authenticated copy (triggers Touch ID / password prompt).
            let result = authorizedRelocateBundle(from: source, to: target)
            switch result {
            case .success:
                logger.info("Moved app to \(target.path) (with admin privileges)")
                Alerts.relaunch(at: target)
            case .cancelled:
                logger.info("User cancelled authentication")
            case .failed(let message):
                logger.error("Authorized move failed: \(message)")
                Alerts.showErrorAlert(message: message)
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
