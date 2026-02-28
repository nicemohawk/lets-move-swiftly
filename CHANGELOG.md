# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-28

### Added
- Initial public release as a Swift Package Manager library
- `LetsMoveSwiftly.moveToApplicationsIfNecessary()` — single-call entry point for prompting the user to move the app to `/Applications/`
- `LetsMoveSwiftly.shouldOfferToMove(...)` — injectable pure decision logic (sandboxed, App Store receipt, already in Applications, user preference)
- `LetsMoveSwiftly.isInApplicationsFolder(_:)` — checks whether a path is inside `/Applications/` or `~/Applications/`
- `LetsMoveSwiftly.relocateBundle(from:to:)` — moves (writable source) or copies (read-only DMG) an app bundle to a destination directory
- `LetsMoveSwiftly.authorizedRelocateBundle(from:to:)` — falls back to an admin-privileged AppleScript copy when a standard move fails
- `LetsMoveSwiftly.dontAskAgainKey` — `UserDefaults` key used to suppress future prompts when the user chooses "Don't Move"
- Automatic sandbox detection: the prompt is silently skipped when running inside the macOS app sandbox
- Automatic App Store detection: the prompt is silently skipped when a valid App Store receipt file exists on disk
- Native `NSAlert` dialogs: "Move to Applications", "Not Now", and "Don't Move" responses
- Replacement confirmation dialog when an existing copy is found in `/Applications/`
- Automatic relaunch from the new location after a successful move
- macOS 13 (Ventura) minimum deployment target
- Swift 5.9+ with `StrictConcurrency` upcoming feature enabled
- MIT License
