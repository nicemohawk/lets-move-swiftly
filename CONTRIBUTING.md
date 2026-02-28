# Contributing to LetsMoveSwiftly

Thanks for your interest in contributing! This is a small, focused package and every improvement matters.

## Getting Started

```bash
git clone https://github.com/nicemohawk/lets-move-swiftly.git
cd lets-move-swiftly
swift build
swift test
```

## What We'd Love Help With

- **Localization** — The alert strings are currently English-only. LetsMove supported 21 languages; we'd love to match that.
- **Accessibility** — Ensuring the dialogs work well with VoiceOver and other assistive technologies.
- **Edge cases** — App Translocation behavior changes across macOS versions. If you find a case where the detection or move fails, please open an issue with your macOS version and steps to reproduce.
- **Documentation** — Improvements to DocC comments, README clarity, or usage examples.
- **Testing** — Additional test scenarios, especially around unusual filesystem configurations.

## Code Style

- Use descriptive, human-readable names: `destinationDirectory` not `destDir`, `applicationIcon` not `appIcn`
- Add `///` DocC comments to all `public` symbols
- Keep the public API surface small — prefer internal helpers over exposing implementation details
- Follow existing patterns in the codebase

## Pull Requests

1. Fork the repo and create a branch from `main`
2. Make your changes with clear, focused commits
3. Ensure `swift test` passes
4. Open a PR with a brief description of what changed and why

## Issues

Found a bug or have a feature idea? [Open an issue](https://github.com/nicemohawk/lets-move-swiftly/issues). Include your macOS version, Swift version, and steps to reproduce if reporting a bug.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
