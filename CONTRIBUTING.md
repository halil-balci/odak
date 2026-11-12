# Contributing

Thanks for helping out!

- Open an issue before large changes so we can agree on the approach.
- Keep it small and dependency-free: Swift, SwiftUI and Apple frameworks only; the browser extension is plain JavaScript with no build step.
- Reading logic (tokenizing, timing, playback, file extraction) lives in `OdakCore` and must be covered by tests (`swift test`). The SwiftUI app in `Sources/Odak` should stay thin.
- Code must build cleanly under Swift 6 strict concurrency.
- The extension's reading logic (`chrome-extension/core.js`) mirrors `OdakCore`; change both together and keep `chrome-extension/tests` in step with the Swift tests.
- Run `swift build && swift test` and `node --test chrome-extension/tests/*.test.mjs` before opening a pull request; CI runs the same.

By contributing you agree that your contributions are licensed under the MIT License.
