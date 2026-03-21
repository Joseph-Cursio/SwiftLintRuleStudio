//
//  OnboardingView.swift
//  SwiftLintRuleStudio
//
//  Onboarding flow for first-time users
//

import SwiftUI

struct OnboardingView: View {
    var onboardingManager: OnboardingManager
    var workspaceManager: WorkspaceManager
    let swiftLintCLI: SwiftLintCLIProtocol

    @ScaledMetric(relativeTo: .largeTitle) var iconSizeLarge: CGFloat = 80
    @ScaledMetric(relativeTo: .title) var iconSizeMedium: CGFloat = 48
    @ScaledMetric(relativeTo: .largeTitle) var iconSizeStandard: CGFloat = 64
    @ScaledMetric(relativeTo: .title) var headingFontSize: CGFloat = 32
    @ScaledMetric(relativeTo: .title2) var subheadingFontSize: CGFloat = 28

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
            progressIndicator
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut, value: onboardingManager.currentStep)
            navigationButtons
        }
        .frame(width: 700, height: 500)
        .onAppear(perform: resetStepIfNeeded)
        .onChange(of: onboardingManager.currentStep) { _, newStep in
            handleStepChange(newStep)
        }
        .onChange(of: workspaceManager.currentWorkspace) { _, newValue in
            handleWorkspaceChange(newValue)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
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

    private func resetStepIfNeeded() {
        if !onboardingManager.hasCompletedOnboarding && onboardingManager.currentStep != .welcome {
            onboardingManager.currentStep = .welcome
        }
    }

    private func handleStepChange(_ newStep: OnboardingManager.OnboardingStep) {
        if newStep == .swiftLintCheck {
            Task {
                await checkSwiftLintInstallation()
            }
        }
    }

    private func handleWorkspaceChange(_ newValue: Workspace?) {
        if newValue != nil && onboardingManager.currentStep == .workspaceSelection {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                onboardingManager.nextStep()
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
