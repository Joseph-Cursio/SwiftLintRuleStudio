//
//  OnboardingManager.swift
//  SwiftLintRuleStudio
//
//  Manages onboarding state and first-run detection
//

import Foundation
import Combine

/// Manages onboarding flow state and first-run detection
@MainActor
class OnboardingManager: ObservableObject {
    @Published var hasCompletedOnboarding: Bool
    @Published var currentStep: OnboardingStep
    
    private let userDefaults: UserDefaults
    private let onboardingKey = "com.swiftlintrulestudio.hasCompletedOnboarding"
    
    enum OnboardingStep: Int, CaseIterable {
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
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        // Onboarding always shows - never mark as permanently completed
        self.hasCompletedOnboarding = false
        // Always start at welcome step
        self.currentStep = .welcome
    }
    
    /// Mark onboarding as complete (dismisses for this session only)
    func completeOnboarding() {
        // Dismiss onboarding for this session only
        // It will show again on next launch
        hasCompletedOnboarding = true
        currentStep = .complete
        // Don't save to UserDefaults - always show onboarding on launch
    }
    
    /// Reset onboarding (useful for testing or re-showing)
    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentStep = .welcome
        userDefaults.removeObject(forKey: onboardingKey)
    }
    
    /// Move to next step
    func nextStep() {
        if let next = currentStep.next {
            currentStep = next
        }
    }
    
    /// Move to previous step
    func previousStep() {
        if let previous = currentStep.previous {
            currentStep = previous
        }
    }
    
    /// Skip to a specific step
    func skipToStep(_ step: OnboardingStep) {
        currentStep = step
    }
}
