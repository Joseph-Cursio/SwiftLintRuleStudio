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
    
    @State var swiftLintStatus: SwiftLintStatus = .checking
    @State var swiftLintPath: URL?
    @State var swiftLintVersion: String?
    @State var errorMessage: String?
    
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
