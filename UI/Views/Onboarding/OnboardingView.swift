//
//  OnboardingView.swift
//  SwiftLintRuleStudio
//
//  Onboarding flow for first-time users
//

import SwiftLintCLISeam
import SwiftLintRuleStudioCore
import SwiftUI

struct OnboardingView: View {
    var onboardingManager: OnboardingManager
    var workspaceManager: WorkspaceManager
    let swiftLintCLI: SwiftLintCLIProtocol

    @Environment(\.appCapabilities) var capabilities: Set<AppCapability>

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
        case builtIn(String?) // in-process edition: the bundled SwiftLint's version, if known
        case notInstalled

        var isReady: Bool {
            switch self {
            case .installed, .builtIn: true
            case .checking, .notInstalled: false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressIndicator
            // Scrollable so the step content (notably the "SwiftLint Not Found"
            // branch) stays reachable at large Dynamic Type sizes or in a small
            // window. The content is at least viewport-tall, so it stays centred,
            // and it only scrolls or bounces when it actually overflows.
            GeometryReader { proxy in
                ScrollView {
                    stepContent
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        .animation(.easeInOut, value: onboardingManager.currentStep)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            navigationButtons
        }
        // Fill the window instead of floating a fixed-size box inside it.
        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
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
    let swiftLintCLI: SwiftLintCLIProtocol = UnconfiguredSwiftLintBackend()

    return OnboardingView(
        onboardingManager: onboardingManager,
        workspaceManager: workspaceManager,
        swiftLintCLI: swiftLintCLI
    )
}
