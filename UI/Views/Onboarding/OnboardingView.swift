//
//  OnboardingView.swift
//  SwiftLintRuleStudio
//
//  Onboarding flow for first-time users
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var onboardingManager: OnboardingManager
    @ObservedObject var workspaceManager: WorkspaceManager
    let swiftLintCLI: SwiftLintCLIProtocol
    
    @State private var swiftLintStatus: SwiftLintStatus = .checking
    @State private var swiftLintPath: URL?
    @State private var swiftLintVersion: String?
    @State private var errorMessage: String?
    
    enum SwiftLintStatus: Equatable {
        case checking
        case installed(URL, String) // path and version
        case notInstalled
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
            
            // Content area
            Group {
                switch onboardingManager.currentStep {
                case .welcome:
                    welcomeStep
                case .swiftLintCheck:
                    swiftLintCheckStep
                case .workspaceSelection:
                    workspaceSelectionStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut, value: onboardingManager.currentStep)
            
            // Navigation buttons
            navigationButtons
        }
        .frame(width: 700, height: 500)
        .onAppear {
            // Ensure we start at welcome step if onboarding hasn't been completed
            if !onboardingManager.hasCompletedOnboarding && onboardingManager.currentStep != .welcome {
                onboardingManager.currentStep = .welcome
            }
        }
        .onChange(of: onboardingManager.currentStep) { _, newStep in
            if newStep == .swiftLintCheck {
                Task {
                    await checkSwiftLintInstallation()
                }
            }
        }
        .onChange(of: workspaceManager.currentWorkspace) { _, newValue in
            // Auto-advance to complete step when workspace is selected
            if newValue != nil && onboardingManager.currentStep == .workspaceSelection {
                // Small delay to show the workspace was selected, then advance
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    onboardingManager.nextStep() // Move to complete step
                }
            }
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingManager.OnboardingStep.allCases.filter { $0 != .complete }, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= onboardingManager.currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
    
    // MARK: - Steps
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .symbolEffect(.bounce, value: onboardingManager.currentStep)
                .accessibilityHidden(true)
            
            Text("Welcome to SwiftLint Rule Studio")
                .font(.system(size: 32, weight: .bold))
            
            Text("A powerful tool for managing and configuring SwiftLint rules in your Swift projects.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "list.bullet.rectangle", title: "Browse Rules", description: "Explore all available SwiftLint rules with detailed documentation")
                featureRow(icon: "exclamationmark.triangle", title: "Inspect Violations", description: "View and manage code violations in your workspace")
                featureRow(icon: "gearshape", title: "Configure Rules", description: "Enable, disable, and customize rules with live preview")
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }
    
    private var swiftLintCheckStep: some View {
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
    
    private var workspaceSelectionStep: some View {
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
    
    private var completeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .symbolEffect(.bounce, value: onboardingManager.currentStep)
                .accessibilityHidden(true)
            
            Text("You're All Set!")
                .font(.system(size: 32, weight: .bold))
            
            Text("SwiftLint Rule Studio is ready to use. Start by browsing rules or inspecting violations in your workspace.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Helper Views
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }
    
    private func installationOption(method: String, command: String, description: String) -> some View {
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
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
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
                        print("Complete button tapped - workspace: \(workspaceManager.currentWorkspace?.path.path ?? "nil")")
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
                            .foregroundColor(.secondary)
                    }
                }
            } else if onboardingManager.currentStep == .complete {
                Button("Get Started") {
                    // Complete onboarding and dismiss
                    onboardingManager.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Next") {
                    onboardingManager.nextStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(onboardingManager.currentStep == .swiftLintCheck && swiftLintStatus == .checking)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - SwiftLint Check
    
    @MainActor
    private func checkSwiftLintInstallation() async {
        swiftLintStatus = .checking
        
        // Run file checks in background to avoid blocking UI
        let result: URL? = await Task.detached(priority: .userInitiated) { @Sendable () -> URL? in
            // Check common paths directly - no actor, no async, just file checks
            let possiblePaths = [
                "/opt/homebrew/bin/swiftlint",  // Apple Silicon Homebrew (most common)
                "/usr/local/bin/swiftlint",     // Intel Homebrew
                "/usr/bin/swiftlint",           // System installation
            ]
            
            // Synchronous file checks - should be instant for local paths
            for pathString in possiblePaths {
                if FileManager.default.fileExists(atPath: pathString) {
                    return URL(fileURLWithPath: pathString)
                }
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
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
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
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

#Preview {
    let onboardingManager = OnboardingManager()
    let workspaceManager = WorkspaceManager()
    let swiftLintCLI: SwiftLintCLIProtocol = SwiftLintCLI(cacheManager: CacheManager())
    
    return OnboardingView(
        onboardingManager: onboardingManager,
        workspaceManager: workspaceManager,
        swiftLintCLI: swiftLintCLI
    )
}

