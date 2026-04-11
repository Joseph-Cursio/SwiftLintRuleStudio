//
//  DependencyContainer.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Observation

/// Dependency injection container
@MainActor
@Observable
public class DependencyContainer {
    /// Central manager for SwiftLint rules metadata
    public let ruleRegistry: RuleRegistry
    /// CLI wrapper for executing SwiftLint commands
    public let swiftLintCLI: SwiftLintCLIProtocol
    /// Cache manager for persisting rules and version data
    public let cacheManager: CacheManagerProtocol
    /// Actor-based SQLite storage for violations
    public let violationStorage: ViolationStorageProtocol
    /// Background analysis engine that runs SwiftLint
    public let workspaceAnalyzer: WorkspaceAnalyzer
    /// Service for workspace selection and recent workspace history
    public let workspaceManager: WorkspaceManager
    /// Manages first-run onboarding flow
    public let onboardingManager: OnboardingManager
    /// Simulates rule impact and discovers zero-violation rules
    public let impactSimulator: ImpactSimulator
    /// Opens violations in Xcode via URL schemes
    public let xcodeIntegrationService: XcodeIntegrationService

    // Phase 1 YAML Configuration Services
    /// Validates SwiftLint configuration files
    public let configurationValidator: ConfigurationValidatorProtocol
    /// Analyzes configuration health and provides recommendations
    public let configurationHealthAnalyzer: ConfigurationHealthAnalyzerProtocol
    /// Manages built-in and custom configuration templates
    public let configurationTemplateManager: ConfigurationTemplateManagerProtocol
    /// Generates PR comments for configuration changes
    public let prCommentGenerator: PRCommentGeneratorProtocol

    // Phase 2 YAML Configuration Services
    /// Browses and restores configuration version history
    public let configVersionHistoryService: ConfigVersionHistoryServiceProtocol
    /// Compares two configurations side by side
    public let configComparisonService: ConfigComparisonServiceProtocol

    // Phase 3 YAML Configuration Services
    /// Git operations service
    public let gitService: GitServiceProtocol
    /// Fetches configurations from URLs
    public let urlConfigFetcher: URLConfigFetcherProtocol
    /// Checks SwiftLint version compatibility
    public let versionCompatibilityChecker: VersionCompatibilityCheckerProtocol
    /// Imports configurations from external sources
    public let configImportService: ConfigImportServiceProtocol
    /// Computes diffs between git branches
    public let gitBranchDiffService: GitBranchDiffServiceProtocol
    /// Assists with SwiftLint version migrations
    public let migrationAssistant: MigrationAssistantProtocol

    /// Initialize the dependency container with optional overrides for each service
    public init(
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
        let cli = swiftLintCLI ?? SwiftLintCLIActor(cacheManager: cache)
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
                self.violationStorage = try ViolationStorageActor()
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
            ?? XcodeIntegrationService()

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
        let git = gitService ?? GitServiceActor()
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

    }
}
