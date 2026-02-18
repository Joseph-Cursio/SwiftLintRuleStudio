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
                .cornerRadius(4)
                .textSelection(.enabled)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Navigation Buttons
    var navigationButtons: some View {
        HStack {
            if onboardingManager.currentStep != .welcome {
                Button("Back") {
                    onboardingManager.previousStep()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if onboardingManager.currentStep == .workspaceSelection {
                // Show "Complete" button if workspace is selected
                if workspaceManager.currentWorkspace != nil {
                    Button("Complete") {
                        let workspacePath = workspaceManager.currentWorkspace?.path.path ?? "nil"
                        print("Complete button tapped - workspace: \(workspacePath)")
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
                .disabled(onboardingManager.currentStep == .swiftLintCheck && swiftLintStatus == .checking)
                .accessibilityIdentifier("OnboardingNextButton")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - SwiftLint Check
    @MainActor
    func checkSwiftLintInstallation() async {
        swiftLintStatus = .checking

        // Run file checks in background to avoid blocking UI
        let result: URL? = await Task.detached(priority: .userInitiated) { @Sendable () -> URL? in
            // Check common paths directly - no actor, no async, just file checks
            let possiblePaths = [
                "/opt/homebrew/bin/swiftlint",  // Apple Silicon Homebrew (most common)
                "/usr/local/bin/swiftlint",     // Intel Homebrew
                "/usr/bin/swiftlint"            // System installation
            ]

            // Synchronous file checks - should be instant for local paths
            for pathString in possiblePaths where FileManager.default.fileExists(atPath: pathString) {
                return URL(fileURLWithPath: pathString)
            }

            return nil
        }.value

        // Update UI (already on main actor)
        if let path = result {
            swiftLintPath = path
            swiftLintVersion = "Installed"
            swiftLintStatus = .installed(path, "Installed")
        } else {
            swiftLintStatus = .notInstalled
            errorMessage = "SwiftLint not found in common installation locations"
        }
    }

    /// Helper to add timeout to async operations
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
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
}
