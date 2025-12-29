# Agent Instructions for Swift Project

## Environment Setup
Jules, you must install the Swift toolchain before running any tasks.
1. Run: `curl -L https://swift.org/swiftly/swiftly-install.sh | bash -s -- -y`
2. Run: `source $HOME/.local/share/swiftly/env.sh`
3. Run: `swiftly install latest`
4. Verify with: `swift --version`
- The project relies on Swift Package Manager (SPM).

## Development Workflow
- **Building:** Always run `swift build` after making changes to ensure syntax validity.
- **Testing:** Run `swift test` to verify logic. Do not skip tests.
- **Dependencies:** If adding a dependency, modify `Package.swift` and run `swift package resolve`.

## Constraints & Style
- **Linux Compatibility:** Avoid using `UIKit`, `AppKit`, or macOS-only APIs.
- **Concurrency:** Prefer `async/await` over completion handlers.
- **Documentation:** Use Triple-slash `///` comments for all public functions.