//
//  DependencyContainer.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Combine

/// Dependency injection container
@MainActor
class DependencyContainer: ObservableObject {
    let ruleRegistry: RuleRegistry
    let swiftLintCLI: SwiftLintCLIProtocol
    let cacheManager: CacheManagerProtocol
    let violationStorage: ViolationStorageProtocol
    let workspaceAnalyzer: WorkspaceAnalyzer
    let workspaceManager: WorkspaceManager
    let onboardingManager: OnboardingManager
    let impactSimulator: ImpactSimulator
    
    private var cancellables = Set<AnyCancellable>()
    
    init(
        ruleRegistry: RuleRegistry? = nil,
        swiftLintCLI: SwiftLintCLIProtocol? = nil,
        cacheManager: CacheManagerProtocol? = nil,
        violationStorage: ViolationStorageProtocol? = nil,
        workspaceManager: WorkspaceManager? = nil,
        onboardingManager: OnboardingManager? = nil,
        impactSimulator: ImpactSimulator? = nil,
        userDefaults: UserDefaults? = nil
    ) {
        let cache = cacheManager ?? CacheManager()
        let cli = swiftLintCLI ?? SwiftLintCLI(cacheManager: cache)
        let registry = ruleRegistry ?? RuleRegistry(swiftLintCLI: cli, cacheManager: cache)
        
        self.ruleRegistry = registry
        self.swiftLintCLI = cli
        self.cacheManager = cache
        
        // Use provided UserDefaults or default to .standard
        let defaults = userDefaults ?? .standard
        
        // Initialize workspace manager
        self.workspaceManager = workspaceManager ?? WorkspaceManager(userDefaults: defaults)
        
        // Initialize onboarding manager
        self.onboardingManager = onboardingManager ?? OnboardingManager(userDefaults: defaults)
        
        // Initialize impact simulator
        self.impactSimulator = impactSimulator ?? ImpactSimulator(swiftLintCLI: cli)
        
        // Initialize violation storage
        if let providedStorage = violationStorage {
            self.violationStorage = providedStorage
        } else {
            do {
                self.violationStorage = try ViolationStorage()
            } catch {
                // Fallback: create in-memory storage or handle error
                fatalError("Failed to initialize violation storage: \(error)")
            }
        }
        
        // Initialize workspace analyzer with file tracker
        self.workspaceAnalyzer = WorkspaceAnalyzer(
            swiftLintCLI: cli,
            violationStorage: self.violationStorage,
            fileTracker: nil // Will create default file tracker
        )
        
        // Forward changes from child ObservableObjects to trigger view updates
        self.onboardingManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        self.workspaceManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

