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
    let xcodeIntegrationService: XcodeIntegrationService

    // Phase 1 YAML Configuration Services
    let configurationValidator: ConfigurationValidatorProtocol
    let configurationHealthAnalyzer: ConfigurationHealthAnalyzerProtocol
    let configurationTemplateManager: ConfigurationTemplateManagerProtocol
    let prCommentGenerator: PRCommentGeneratorProtocol

    // Phase 2 YAML Configuration Services
    let configVersionHistoryService: ConfigVersionHistoryServiceProtocol
    let configComparisonService: ConfigComparisonServiceProtocol

    // Phase 3 YAML Configuration Services
    let gitService: GitServiceProtocol
    let urlConfigFetcher: URLConfigFetcherProtocol
    let versionCompatibilityChecker: VersionCompatibilityCheckerProtocol
    let configImportService: ConfigImportServiceProtocol
    let gitBranchDiffService: GitBranchDiffServiceProtocol
    let migrationAssistant: MigrationAssistantProtocol

    private var cancellables = Set<AnyCancellable>()

    // swiftlint:disable:next function_body_length
    init(
        ruleRegistry: RuleRegistry? = nil,
        swiftLintCLI: SwiftLintCLIProtocol? = nil,
        cacheManager: CacheManagerProtocol? = nil,
        violationStorage: ViolationStorageProtocol? = nil,
        workspaceManager: WorkspaceManager? = nil,
        onboardingManager: OnboardingManager? = nil,
        impactSimulator: ImpactSimulator? = nil,
        xcodeIntegrationService: XcodeIntegrationService? = nil,
        configurationValidator: ConfigurationValidatorProtocol? = nil,
        configurationHealthAnalyzer: ConfigurationHealthAnalyzerProtocol? = nil,
        configurationTemplateManager: ConfigurationTemplateManagerProtocol? = nil,
        prCommentGenerator: PRCommentGeneratorProtocol? = nil,
        configVersionHistoryService: ConfigVersionHistoryServiceProtocol? = nil,
        configComparisonService: ConfigComparisonServiceProtocol? = nil,
        gitService: GitServiceProtocol? = nil,
        urlConfigFetcher: URLConfigFetcherProtocol? = nil,
        versionCompatibilityChecker: VersionCompatibilityCheckerProtocol? = nil,
        configImportService: ConfigImportServiceProtocol? = nil,
        gitBranchDiffService: GitBranchDiffServiceProtocol? = nil,
        migrationAssistant: MigrationAssistantProtocol? = nil,
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
        
        // Initialize Xcode integration service
        self.xcodeIntegrationService = xcodeIntegrationService
            ?? XcodeIntegrationService(workspaceManager: self.workspaceManager)

        // Initialize Phase 1 YAML Configuration Services
        self.configurationValidator = configurationValidator
            ?? ConfigurationValidator(ruleRegistry: registry)
        self.configurationHealthAnalyzer = configurationHealthAnalyzer
            ?? ConfigurationHealthAnalyzer()
        self.configurationTemplateManager = configurationTemplateManager
            ?? ConfigurationTemplateManager()
        self.prCommentGenerator = prCommentGenerator
            ?? PRCommentGenerator()

        // Initialize Phase 2 YAML Configuration Services
        self.configVersionHistoryService = configVersionHistoryService
            ?? ConfigVersionHistoryService()
        self.configComparisonService = configComparisonService
            ?? ConfigComparisonService()

        // Initialize Phase 3 YAML Configuration Services
        let git = gitService ?? GitService()
        self.gitService = git
        let fetcher = urlConfigFetcher ?? URLConfigFetcher()
        self.urlConfigFetcher = fetcher
        self.versionCompatibilityChecker = versionCompatibilityChecker
            ?? VersionCompatibilityChecker()
        self.configImportService = configImportService
            ?? ConfigImportService(fetcher: fetcher)
        self.gitBranchDiffService = gitBranchDiffService
            ?? GitBranchDiffService(gitService: git, comparisonService: self.configComparisonService)
        self.migrationAssistant = migrationAssistant
            ?? MigrationAssistant()

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
