import AppKit

/// Internal alert presentation and app relaunch helpers.
///
/// These are separated from ``LetsMoveSwiftly`` to keep the public API surface clean.
/// All methods require the main thread (`@MainActor`) because they present `NSAlert` dialogs.
@MainActor
enum Alerts {

    /// Shows the primary "Move to Applications?" dialog.
    ///
    /// - Parameter appName: The app's display name, shown in the dialog text.
    /// - Returns: The user's choice.
    static func showMoveAlert(appName: String) -> LetsMoveSwiftly.MoveAlertResponse {
        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = """
            \(appName) needs to be in your Applications folder to work properly. \
            Would you like to move it now?
            """
        alert.alertStyle = .informational
        if let applicationIcon = NSApp.applicationIconImage {
            alert.icon = applicationIcon
        }

        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don't Move")

        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .move
        case .alertThirdButtonReturn:  return .dontMove
        default:                       return .notNow
        }
    }

    /// Shows a confirmation dialog when an existing copy is found in `/Applications/`.
    ///
    /// - Parameter appName: The app's display name.
    /// - Returns: `true` if the user confirms replacement.
    static func showReplaceAlert(appName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace existing copy?"
        alert.informativeText = """
            An older copy of \(appName) already exists in Applications. \
            Do you want to replace it?
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Shows an error alert when the move fails.
    ///
    /// - Parameter message: The error description to display.
    static func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Could not move to Applications"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Launches the app from its new location and terminates the current process.
    ///
    /// Uses a brief delay to allow the current process to exit before the new instance starts.
    ///
    /// - Parameter url: The URL of the relocated app bundle.
    static func relaunch(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait briefly for the current process to exit, then open the relocated app.
        process.arguments = ["-c", "sleep 0.5 && open \"\(url.path)\""]
        try? process.run()

        NSApp.terminate(nil)
    }
}
