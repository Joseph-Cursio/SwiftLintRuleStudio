//
//  OnboardingManager.swift
//  SwiftLintRuleStudio
//
//  Manages onboarding state and first-run detection
//

import Foundation
import Observation

/// Manages onboarding flow state and first-run detection
@MainActor
@Observable
public class OnboardingManager {
    public var hasCompletedOnboarding: Bool
    public var currentStep: OnboardingStep

    private let userDefaults: UserDefaults
    private let onboardingKey = "com.swiftlintrulestudio.hasCompletedOnboarding"

    public enum OnboardingStep: Int, CaseIterable, Sendable {
        case welcome = 0
        case swiftLintCheck = 1
        case workspaceSelection = 2
        case complete = 3

        var next: OnboardingStep? {
            switch self {
            case .welcome:
                return .swiftLintCheck
            case .swiftLintCheck:
                return .workspaceSelection
            case .workspaceSelection:
                return .complete
            case .complete:
                return nil
            }
        }

        var previous: OnboardingStep? {
            switch self {
            case .welcome:
                return nil
            case .swiftLintCheck:
                return .welcome
            case .workspaceSelection:
                return .swiftLintCheck
            case .complete:
                return .workspaceSelection
            }
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        // Onboarding always shows - never mark as permanently completed
        self.hasCompletedOnboarding = false
        // Always start at welcome step
        self.currentStep = .welcome
    }

    /// Mark onboarding as complete (dismisses for this session only)
    public func completeOnboarding() {
        // Dismiss onboarding for this session only
        // It will show again on next launch
        hasCompletedOnboarding = true
        currentStep = .complete
        // Don't save to UserDefaults - always show onboarding on launch
    }

    /// Reset onboarding (useful for testing or re-showing)
    public func resetOnboarding() {
        hasCompletedOnboarding = false
        currentStep = .welcome
        userDefaults.removeObject(forKey: onboardingKey)
    }

    /// Move to next step
    public func nextStep() {
        if let next = currentStep.next {
            currentStep = next
        }
    }

    /// Move to previous step
    public func previousStep() {
        if let previous = currentStep.previous {
            currentStep = previous
        }
    }

    /// Skip to a specific step
    public func skipToStep(_ step: OnboardingStep) {
        currentStep = step
    }
}
