import SwiftUI

extension OnboardingView {
    // MARK: - Progress Indicator
    var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingManager.OnboardingStep.allCases.filter { $0 != .complete }, id: \.rawValue) { step in
                let isCompleted = step.rawValue <= onboardingManager.currentStep.rawValue
                Circle()
                    .fill(isCompleted ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Steps
    var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .symbolEffect(.bounce, value: onboardingManager.currentStep)
                .accessibilityHidden(true)

            Text("Welcome to SwiftLint Rule Studio")
                .font(.system(size: 32, weight: .bold))
                .accessibilityIdentifier("OnboardingWelcomeTitle")

            Text("A powerful tool for managing and configuring SwiftLint rules in your Swift projects.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    icon: "list.bullet.rectangle",
                    title: "Browse Rules",
                    description: "Explore all available SwiftLint rules with detailed documentation"
                )
                featureRow(
                    icon: "exclamationmark.triangle",
                    title: "Inspect Violations",
                    description: "View and manage code violations in your workspace"
                )
                featureRow(
                    icon: "gearshape",
                    title: "Configure Rules",
                    description: "Enable, disable, and customize rules with live preview"
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }

    var swiftLintCheckStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 64))
                .foregroundColor(swiftLintStatus == .installed(URL(fileURLWithPath: ""), "") ? .green : .orange)
                .accessibilityHidden(true)

            Text("SwiftLint Installation")
                .font(.system(size: 28, weight: .bold))

            Group {
                switch swiftLintStatus {
                case .checking:
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Checking for SwiftLint installation...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                case .installed(let path, let version):
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                            .accessibilityHidden(true)

                        Text("SwiftLint is installed")
                            .font(.title2)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 8) {
                            infoRow(label: "Version", value: version)
                            infoRow(label: "Path", value: path.path)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                case .notInstalled:
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                            .accessibilityHidden(true)

                        Text("SwiftLint Not Found")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("SwiftLint Rule Studio requires SwiftLint to be installed on your system.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Installation Options:")
                                .font(.headline)

                            installationOption(
                                method: "Homebrew",
                                command: "brew install swiftlint",
                                description: "Recommended for most users"
                            )

                            installationOption(
                                method: "Mint",
                                command: "mint install realm/SwiftLint",
                                description: "Swift package manager"
                            )

                            installationOption(
                                method: "Direct Download",
                                command: "https://github.com/realm/SwiftLint/releases",
                                description: "Download from GitHub"
                            )
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .padding(.horizontal, 40)

                        Button {
                            Task {
                                await checkSwiftLintInstallation()
                            }
                        } label: {
                            Label("Check Again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.vertical, 40)
    }

    var workspaceSelectionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 64))
                .foregroundColor(.blue)
                .accessibilityHidden(true)

            Text("Select Your Workspace")
                .font(.system(size: 28, weight: .bold))

            Text("Choose a directory containing your Swift project to get started.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Embed the workspace selection view
            WorkspaceSelectionView(workspaceManager: workspaceManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 20)
        .onChange(of: workspaceManager.currentWorkspace) { _, newValue in
            if newValue != nil {
                // Workspace selected, can proceed
            }
        }
    }

    var completeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .symbolEffect(.bounce, value: onboardingManager.currentStep)
                .accessibilityHidden(true)

            Text("You're All Set!")
                .font(.system(size: 32, weight: .bold))

            Text("""
            SwiftLint Rule Studio is ready to use. Start by browsing rules or inspecting violations in your workspace.
            """)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }
}
