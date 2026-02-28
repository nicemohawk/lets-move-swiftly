# LetsMoveSwiftly

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138.svg)](https://swift.org)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A lightweight Swift package that prompts users to move your macOS app to `/Applications/` on first launch.

When macOS apps are launched from Downloads, Desktop, or a mounted DMG, [App Translocation](https://developer.apple.com/documentation/security/translocation) runs them from a randomized read-only path. This breaks auto-updates, file associations, and Spotlight indexing. LetsMoveSwiftly fixes this with a single line of code.

## Installation

Add LetsMoveSwiftly to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nicemohawk/lets-move-swiftly.git", from: "1.0.0"),
]
```

Then add it to your target:

```swift
.target(name: "MyApp", dependencies: ["LetsMoveSwiftly"]),
```

Or in Xcode: **File > Add Package Dependencies...** and enter `https://github.com/nicemohawk/lets-move-swiftly.git`.

## Usage

### SwiftUI

```swift
import LetsMoveSwiftly
import SwiftUI

@main
struct MyApp: App {
    init() {
        LetsMoveSwiftly.moveToApplicationsIfNecessary()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### AppKit

```swift
import LetsMoveSwiftly

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        LetsMoveSwiftly.moveToApplicationsIfNecessary()
    }
}
```

That's it. The call:

1. Returns immediately if the app is already in `/Applications/`, was installed from the Mac App Store, or the user previously chose "Don't Move"
2. Shows a native dialog with three options: **Move to Applications**, **Not Now**, and **Don't Move**
3. Handles the file move (or copy from a read-only DMG), replaces any existing copy, and relaunches from the new location

## API

| Method | Description |
|--------|-------------|
| `moveToApplicationsIfNecessary()` | Main entry point. Call once at launch. |
| `shouldOfferToMove(...)` | Pure decision logic. All parameters are injectable for testing. |
| `isInApplicationsFolder(_:)` | Checks if a path is inside `/Applications/` or `~/Applications/`. |
| `relocateBundle(from:to:...)` | Moves or copies an app bundle to a destination directory. |
| `dontAskAgainKey` | The `UserDefaults` key for the "Don't Move" preference. Reset it to prompt again. |

## How It Works

- **App Store detection**: Checks if a valid App Store receipt file exists on disk. If so, the prompt is skipped entirely (the App Store handles placement).
- **Move vs. copy**: If the source directory is writable (ZIP extraction), the app is moved. If read-only (mounted DMG), it's copied.
- **Existing app replacement**: If a copy already exists in `/Applications/`, the user is asked to confirm before replacing.
- **Relaunch**: After moving, the app launches from its new location and the old process terminates.

## Requirements

- macOS 13.0+ (Ventura)
- Swift 5.9+
- Xcode 15+

## Acknowledgments

Inspired by [LetsMove](https://github.com/potionfactory/LetsMove) (public domain, Objective-C) and [AppMover](https://github.com/OskarGroth/AppMover) (Swift). Both libraries implemented this pattern but lack Swift Package Manager support. LetsMoveSwiftly is a simple, modern reimplementation built for SPM from the start.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License. See [LICENSE](LICENSE) for details.
