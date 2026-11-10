import SwiftLintCLISeam
import SwiftLintRuleStudioCore
import SwiftUI

extension OnboardingView {
    // MARK: - Helper Views
    func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }

    func installationOption(method: String, command: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(method)
                .font(.headline)

            Text(command)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(.rect(cornerRadius: 4))
                .textSelection(.enabled)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Navigation Buttons
    /// Back and the forward button; Next waits while the SwiftLint check runs.
    func navigationButtons(isCheckingSwiftLint: Bool) -> some View {
        HStack {
            if onboardingManager.currentStep != .welcome {
                Button("Back") {
                    onboardingManager.previousStep()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            forwardButton(isCheckingSwiftLint: isCheckingSwiftLint)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - SwiftLint Check
    /// Where SwiftLint is: built in, installed at a common path, or not found.
    @MainActor
    func detectSwiftLint() async -> SwiftLintStatus {
        // Sandboxed / in-process edition: SwiftLint is linked in, not detected on
        // disk. There is no external binary or path to report, so show the bundled
        // version and skip the path probing (which the sandbox would block anyway).
        if !capabilities.contains(.detectInstalledSwiftLint) {
            let version = try? await swiftLintCLI.getVersion()
            return .builtIn(version)
        }

        // Run file checks in background to avoid blocking UI
        let result: URL? = await Task.detached(priority: .userInitiated) { @Sendable () -> URL? in
            // Check common paths directly - no actor, no async, just file checks
            let possiblePaths = [
                "/opt/homebrew/bin/swiftlint",  // Apple Silicon Homebrew (most common)
                "/usr/local/bin/swiftlint",     // Intel Homebrew
                "/usr/bin/swiftlint",            // System installation
            ]

            // Synchronous file checks - should be instant for local paths
            for pathString in possiblePaths where FileManager.default.fileExists(atPath: pathString) {
                return URL(fileURLWithPath: pathString)
            }

            return nil
        }.value

        if let path = result {
            return .installed(path, "Installed")
        }
        return .notInstalled
    }

    /// Helper to add timeout to async operations
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Start the actual operation
            group.addTask { @Sendable in
                try await operation()
            }

            // Start timeout task
            group.addTask { @Sendable in
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SwiftLintError.executionFailed(message: "Operation timed out after \(seconds) seconds")
            }

            // Return first completed result (either success or timeout)
            guard let result = try await group.next() else {
                throw SwiftLintError.executionFailed(message: "Operation timed out after \(seconds) seconds")
            }
            group.cancelAll()
            return result
        }
    }

    /// The button that moves onboarding on: Complete, Get Started or Next, by step.
    @ViewBuilder
    private func forwardButton(isCheckingSwiftLint: Bool) -> some View {
        if onboardingManager.currentStep == .workspaceSelection {
            // Show "Complete" button if workspace is selected
            if workspaceManager.currentWorkspace != nil {
                Button("Complete") {
                    onboardingManager.nextStep() // Move to complete step
                }
                .buttonStyle(.borderedProminent)
            } else {
                // Show disabled button with helpful text
                VStack(spacing: 4) {
                    Button("Select a Workspace") {
                        // This shouldn't be clickable, but just in case
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    Text("Choose a directory to continue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if onboardingManager.currentStep == .complete {
            Button("Get Started") {
                // Complete onboarding and dismiss
                onboardingManager.completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("OnboardingGetStartedButton")
        } else {
            Button("Next") {
                onboardingManager.nextStep()
            }
            .buttonStyle(.borderedProminent)
            .disabled(onboardingManager.currentStep == .swiftLintCheck && isCheckingSwiftLint)
            .accessibilityIdentifier("OnboardingNextButton")
        }
    }
}
