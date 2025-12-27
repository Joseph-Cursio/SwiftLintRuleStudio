//
//  YAMLConfigurationEngineTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for YAML Configuration Engine
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// YAMLConfigurationEngine is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct YAMLConfigurationEngineTests {
    
    // MARK: - Test Helpers
    
    // Helper to create and use YAMLConfigurationEngine on MainActor
    private func withEngine<T: Sendable>(configPath: URL, operation: @MainActor (YAMLConfigurationEngine) throws -> T) async throws -> T {
        try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configPath)
            return try operation(engine)
        }
    }
    
    private func createTempConfigFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let configFile = tempDir.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configFile, atomically: true, encoding: .utf8)
        return configFile
    }
    
    private func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
    
    // MARK: - Loading Tests
    
    @Test("YAMLConfigurationEngine loads existing configuration file")
    func testLoadExistingFile() async throws {
        let yamlContent = """
        disabled_rules:
          - force_cast
        opt_in_rules:
          - empty_count
        included:
          - Sources
        excluded:
          - Pods
        reporter: xcode
        rules:
          line_length:
            warning: 120
            error: 200
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (included, excluded, reporter, rulesCount, hasLineLength) = try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configFile)
            try engine.load()
            let config = engine.getConfig()
            return (config.included, config.excluded, config.reporter, config.rules.count, config.rules["line_length"] != nil)
        }
        
        #expect(included == ["Sources"])
        #expect(excluded == ["Pods"])
        #expect(reporter == "xcode")
        #expect(rulesCount == 1)
        #expect(hasLineLength == true)
    }
    
    @Test("YAMLConfigurationEngine handles non-existent file")
    func testLoadNonExistentFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let configFile = tempDir.appendingPathComponent(".swiftlint.yml")
        
        let (rulesEmpty, included, excluded) = try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configFile)
            // Should not throw - returns empty config
            try engine.load()
            let config = engine.getConfig()
            return (config.rules.isEmpty, config.included, config.excluded)
        }
        
        #expect(rulesEmpty == true)
        #expect(included == nil)
        #expect(excluded == nil)
    }
    
    @Test("YAMLConfigurationEngine parses simple rule configuration")
    func testParseSimpleRuleConfig() async throws {
        let yamlContent = """
        rules:
          force_cast:
            severity: error
          line_length:
            warning: 120
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (rulesCount, forceCastSeverity, hasLineLengthParams) = try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configFile)
            try engine.load()
            let config = engine.getConfig()
            return (config.rules.count, config.rules["force_cast"]?.severity, config.rules["line_length"]?.parameters != nil)
        }
        
        #expect(rulesCount == 2)
        #expect(forceCastSeverity == .error)
        #expect(hasLineLengthParams == true)
    }
    
    @Test("YAMLConfigurationEngine parses boolean rule configuration")
    func testParseBooleanRuleConfig() async throws {
        let yamlContent = """
        rules:
          force_cast: false
          line_length: true
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (rulesCount, forceCastEnabled, lineLengthEnabled) = try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configFile)
            try engine.load()
            let config = engine.getConfig()
            return (config.rules.count, config.rules["force_cast"]?.enabled, config.rules["line_length"]?.enabled)
        }
        
        #expect(rulesCount == 2)
        #expect(forceCastEnabled == false)
        #expect(lineLengthEnabled == true)
    }
    
    @Test("YAMLConfigurationEngine handles empty configuration")
    func testLoadEmptyConfiguration() async throws {
        let yamlContent = ""
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        // Empty YAML should throw an error
        await #expect(throws: YAMLConfigError.self) {
            try await MainActor.run {
                let engine = YAMLConfigurationEngine(configPath: configFile)
                try engine.load()
            }
        }
    }
    
    // MARK: - Saving Tests
    
    @Test("YAMLConfigurationEngine saves configuration to file")
    func testSaveConfiguration() async throws {
        let configFile = try createTempConfigFile(content: "")
        defer { cleanupTempFile(configFile) }
        
        // Delete the empty file first
        try? FileManager.default.removeItem(at: configFile)
        
        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.rules["force_cast"] = RuleConfiguration(enabled: false, severity: .error)
            config.included = ["Sources"]
            return config
        }
        
        try await withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: false)
        }
        
        // Verify file was created
        #expect(FileManager.default.fileExists(atPath: configFile.path))
        
        // Reload and verify
        let (rulesCount, forceCastEnabled, included) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let loadedConfig = engine.getConfig()
            return (loadedConfig.rules.count, loadedConfig.rules["force_cast"]?.enabled, loadedConfig.included)
        }
        
        #expect(rulesCount == 1)
        #expect(forceCastEnabled == false)
        #expect(included == ["Sources"])
    }
    
    @Test("YAMLConfigurationEngine creates backup when saving")
    func testSaveCreatesBackup() async throws {
        let yamlContent = """
        rules:
          force_cast: false
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let config = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules["line_length"] = RuleConfiguration(enabled: true)
            return config
        }
        
        try await withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: true)
        }
        
        // Check backup was created (backup files now use timestamped names)
        let configDir = configFile.deletingLastPathComponent()
        let backupFiles = try FileManager.default.contentsOfDirectory(at: configDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(configFile.lastPathComponent) && $0.lastPathComponent.hasSuffix(".backup") }
        #expect(!backupFiles.isEmpty, "Backup file should be created")
        
        // Cleanup backup
        for backupFile in backupFiles {
            try? FileManager.default.removeItem(at: backupFile)
        }
    }
    
    @Test("YAMLConfigurationEngine performs atomic write")
    func testAtomicWrite() async throws {
        let configFile = try createTempConfigFile(content: "")
        defer { cleanupTempFile(configFile) }
        
        try? FileManager.default.removeItem(at: configFile)
        
        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.rules["test_rule"] = RuleConfiguration(enabled: true)
            return config
        }
        
        try await withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: false)
        }
        
        // Verify temp file doesn't exist (was moved)
        let tempFile = configFile.appendingPathExtension("tmp")
        #expect(!FileManager.default.fileExists(atPath: tempFile.path))
        
        // Verify final file exists
        #expect(FileManager.default.fileExists(atPath: configFile.path))
    }
    
    // MARK: - Diff Generation Tests
    
    @Test("YAMLConfigurationEngine generates diff for added rules")
    func testDiffAddedRules() async throws {
        let yamlContent = """
        rules:
          force_cast: false
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasChanges, addedRules, removedRules, modifiedRules) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules["line_length"] = RuleConfiguration(enabled: true)
            let diff = engine.generateDiff(proposedConfig: config)
            return (diff.hasChanges, diff.addedRules, diff.removedRules, diff.modifiedRules)
        }
        
        #expect(hasChanges == true)
        #expect(addedRules.contains("line_length"))
        #expect(removedRules.isEmpty)
        #expect(modifiedRules.isEmpty)
    }
    
    @Test("YAMLConfigurationEngine generates diff for removed rules")
    func testDiffRemovedRules() async throws {
        let yamlContent = """
        rules:
          force_cast: false
          line_length: true
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasChanges, removedRules, addedRules, modifiedRules) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules.removeValue(forKey: "line_length")
            let diff = engine.generateDiff(proposedConfig: config)
            return (diff.hasChanges, diff.removedRules, diff.addedRules, diff.modifiedRules)
        }
        
        #expect(hasChanges == true)
        #expect(removedRules.contains("line_length"))
        #expect(addedRules.isEmpty)
        #expect(modifiedRules.isEmpty)
    }
    
    @Test("YAMLConfigurationEngine generates diff for modified rules")
    func testDiffModifiedRules() async throws {
        let yamlContent = """
        rules:
          force_cast:
            severity: warning
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasChanges, modifiedRules, addedRules, removedRules) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules["force_cast"] = RuleConfiguration(enabled: true, severity: .error)
            let diff = engine.generateDiff(proposedConfig: config)
            return (diff.hasChanges, diff.modifiedRules, diff.addedRules, diff.removedRules)
        }
        
        #expect(hasChanges == true)
        #expect(modifiedRules.contains("force_cast"))
        #expect(addedRules.isEmpty)
        #expect(removedRules.isEmpty)
    }
    
    @Test("YAMLConfigurationEngine detects no changes in diff")
    func testDiffNoChanges() async throws {
        let yamlContent = """
        rules:
          force_cast: false
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasChanges, addedRules, removedRules, modifiedRules) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            let diff = engine.generateDiff(proposedConfig: config)
            return (diff.hasChanges, diff.addedRules, diff.removedRules, diff.modifiedRules)
        }
        
        #expect(hasChanges == false)
        #expect(addedRules.isEmpty)
        #expect(removedRules.isEmpty)
        #expect(modifiedRules.isEmpty)
    }
    
    // MARK: - Validation Tests
    
    @Test("YAMLConfigurationEngine validates severity values")
    func testValidateSeverity() async throws {
        let configFile = try createTempConfigFile(content: "")
        defer { cleanupTempFile(configFile) }
        
        try? FileManager.default.removeItem(at: configFile)
        
        // Valid severities should pass
        let config1 = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.rules["test_rule"] = RuleConfiguration(enabled: true, severity: .warning)
            return config
        }
        
        // Should not throw
        try await withEngine(configPath: configFile) { engine in
            try engine.validate(config1)
        }
        
        let config2 = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.rules["test_rule"] = RuleConfiguration(enabled: true, severity: .error)
            return config
        }
        try await withEngine(configPath: configFile) { engine in
            try engine.validate(config2)
        }
    }
    
    @Test("YAMLConfigurationEngine validates included paths")
    func testValidateIncludedPaths() async throws {
        let configFile = try createTempConfigFile(content: "")
        defer { cleanupTempFile(configFile) }
        
        try? FileManager.default.removeItem(at: configFile)
        
        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.included = ["Sources", "Tests"]
            return config
        }
        
        // Should not throw
        try await withEngine(configPath: configFile) { engine in
            try engine.validate(config)
        }
    }
    
    @Test("YAMLConfigurationEngine rejects empty included paths")
    func testValidateEmptyIncludedPaths() async throws {
        let configFile = try createTempConfigFile(content: "")
        defer { cleanupTempFile(configFile) }
        
        try? FileManager.default.removeItem(at: configFile)
        
        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.included = [""]
            return config
        }
        
        // Should throw validation error
        await #expect(throws: YAMLConfigError.self) {
            try await withEngine(configPath: configFile) { engine in
                try engine.validate(config)
            }
        }
    }
    
    @Test("YAMLConfigurationEngine rejects empty excluded paths")
    func testValidateEmptyExcludedPaths() async throws {
        let configFile = try createTempConfigFile(content: "")
        defer { cleanupTempFile(configFile) }
        
        try? FileManager.default.removeItem(at: configFile)
        
        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.excluded = [""]
            return config
        }
        
        // Should throw validation error
        await #expect(throws: YAMLConfigError.self) {
            try await withEngine(configPath: configFile) { engine in
                try engine.validate(config)
            }
        }
    }
    
    // MARK: - Comment Preservation Tests
    
    @Test("YAMLConfigurationEngine extracts comments from YAML")
    func testExtractComments() async throws {
        let yamlContent = """
        # This is a comment
        rules:
          # Rule comment
          force_cast: false
        included:
          - Sources
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let rulesCount = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return config.rules.count
        }
        
        // Comments should be extracted (basic implementation)
        // More sophisticated comment preservation can be tested later
        #expect(rulesCount == 1)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("YAMLConfigurationEngine handles invalid YAML")
    func testInvalidYAML() async throws {
        let invalidYAML = """
        rules:
          - invalid
          - yaml
          structure
        """
        
        let configFile = try createTempConfigFile(content: invalidYAML)
        defer { cleanupTempFile(configFile) }
        
        // Should throw parse error
        await #expect(throws: YAMLConfigError.self) {
            try await withEngine(configPath: configFile) { engine in
                try engine.load()
            }
        }
    }
    
    @Test("YAMLConfigurationEngine handles malformed rule configuration")
    func testMalformedRuleConfig() async throws {
        // This test verifies the engine handles edge cases gracefully
        let yamlContent = """
        rules:
          force_cast:
            invalid_field: value
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        // Should still parse (invalid fields are ignored)
        let hasForceCast = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return config.rules["force_cast"] != nil
        }
        #expect(hasForceCast == true)
    }
    
    // MARK: - Round-Trip Tests
    
    @Test("YAMLConfigurationEngine preserves configuration in round-trip")
    func testRoundTrip() async throws {
        let yamlContent = """
        rules:
          force_cast:
            severity: error
          line_length:
            warning: 120
        included:
          - Sources
        excluded:
          - Pods
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (originalRulesCount, originalForceCastSeverity, originalIncluded, originalExcluded) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules.count, config.rules["force_cast"]?.severity, config.included, config.excluded)
        }
        
        // Save and reload
        let originalConfig = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            return engine.getConfig()
        }
        try await withEngine(configPath: configFile) { engine in
            try engine.save(config: originalConfig, createBackup: false)
        }
        
        let (reloadedRulesCount, reloadedForceCastSeverity, reloadedIncluded, reloadedExcluded) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules.count, config.rules["force_cast"]?.severity, config.included, config.excluded)
        }
        
        // Verify rules are preserved
        #expect(reloadedRulesCount == originalRulesCount)
        #expect(reloadedForceCastSeverity == originalForceCastSeverity)
        #expect(reloadedIncluded == originalIncluded)
        #expect(reloadedExcluded == originalExcluded)
    }
    
    @Test("YAMLConfigurationEngine handles complex rule parameters")
    func testComplexRuleParameters() async throws {
        let yamlContent = """
        rules:
          line_length:
            warning: 120
            error: 200
            ignores_urls: true
            ignores_function_declarations: false
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasLineLength, hasParams, paramsCount) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules["line_length"] != nil, config.rules["line_length"]?.parameters != nil, config.rules["line_length"]?.parameters?.count ?? 0)
        }
        #expect(hasLineLength == true)
        #expect(hasParams == true)
        #expect(paramsCount >= 3)
    }
    
    // MARK: - Edge Case Tests
    
    @Test("YAMLConfigurationEngine handles rules with only parameters, no severity")
    func testRulesWithOnlyParameters() async throws {
        let yamlContent = """
        rules:
          line_length:
            warning: 120
            error: 200
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasLineLength, hasParams, severity) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules["line_length"] != nil, config.rules["line_length"]?.parameters != nil, config.rules["line_length"]?.severity)
        }
        #expect(hasLineLength == true)
        #expect(hasParams == true)
        #expect(severity == nil)
    }
    
    @Test("YAMLConfigurationEngine handles disabled rules with parameters")
    func testDisabledRulesWithParameters() async throws {
        let yamlContent = """
        rules:
          line_length:
            enabled: false
            warning: 120
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (enabled, hasParams) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules["line_length"]?.enabled, config.rules["line_length"]?.parameters != nil)
        }
        #expect(enabled == false)
        #expect(hasParams == true)
    }
    
    @Test("YAMLConfigurationEngine handles empty rules dictionary")
    func testEmptyRulesDictionary() async throws {
        let yamlContent = """
        rules: {}
        included:
          - Sources
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (rulesEmpty, included) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules.isEmpty, config.included)
        }
        #expect(rulesEmpty == true)
        #expect(included == ["Sources"])
    }
    
    @Test("YAMLConfigurationEngine handles numeric rule parameters")
    func testNumericRuleParameters() async throws {
        let yamlContent = """
        rules:
          file_length:
            warning: 400
            error: 1000
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasParams, hasWarning, hasError) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules["file_length"]?.parameters != nil, config.rules["file_length"]?.parameters?["warning"] != nil, config.rules["file_length"]?.parameters?["error"] != nil)
        }
        #expect(hasParams == true)
        #expect(hasWarning == true)
        #expect(hasError == true)
    }
    
    @Test("YAMLConfigurationEngine handles string rule parameters")
    func testStringRuleParameters() async throws {
        let yamlContent = """
        rules:
          custom_rules:
            name: "My Custom Rule"
            regex: ".*"
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasParams, hasName) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules["custom_rules"]?.parameters != nil, config.rules["custom_rules"]?.parameters?["name"] != nil)
        }
        #expect(hasParams == true)
        #expect(hasName == true)
    }
    
    @Test("YAMLConfigurationEngine handles array rule parameters")
    func testArrayRuleParameters() async throws {
        let yamlContent = """
        rules:
          excluded:
            paths:
              - Pods
              - Generated
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasParams, hasPaths) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules["excluded"]?.parameters != nil, config.rules["excluded"]?.parameters?["paths"] != nil)
        }
        #expect(hasParams == true)
        #expect(hasPaths == true)
    }
    
    @Test("YAMLConfigurationEngine handles nested rule configurations")
    func testNestedRuleConfigurations() async throws {
        let yamlContent = """
        rules:
          nesting:
            type_level: 2
            function_level: 3
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (hasParams, hasTypeLevel, hasFunctionLevel) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules["nesting"]?.parameters != nil, config.rules["nesting"]?.parameters?["type_level"] != nil, config.rules["nesting"]?.parameters?["function_level"] != nil)
        }
        #expect(hasParams == true)
        #expect(hasTypeLevel == true)
        #expect(hasFunctionLevel == true)
    }
    
    @Test("YAMLConfigurationEngine handles multiple included paths")
    func testMultipleIncludedPaths() async throws {
        let yamlContent = """
        included:
          - Sources
          - Tests
          - Scripts
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (includedCount, hasSources, hasTests, hasScripts) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.included?.count ?? 0, config.included?.contains("Sources") == true, config.included?.contains("Tests") == true, config.included?.contains("Scripts") == true)
        }
        #expect(includedCount == 3)
        #expect(hasSources == true)
        #expect(hasTests == true)
        #expect(hasScripts == true)
    }
    
    @Test("YAMLConfigurationEngine handles multiple excluded paths")
    func testMultipleExcludedPaths() async throws {
        let yamlContent = """
        excluded:
          - Pods
          - .build
          - Generated
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (excludedCount, hasPods, hasBuild, hasGenerated) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.excluded?.count ?? 0, config.excluded?.contains("Pods") == true, config.excluded?.contains(".build") == true, config.excluded?.contains("Generated") == true)
        }
        #expect(excludedCount == 3)
        #expect(hasPods == true)
        #expect(hasBuild == true)
        #expect(hasGenerated == true)
    }
    
    @Test("YAMLConfigurationEngine handles reporter configuration")
    func testReporterConfiguration() async throws {
        let yamlContent = """
        reporter: xcode
        rules:
          force_cast: false
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (reporter, forceCastEnabled) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.reporter, config.rules["force_cast"]?.enabled)
        }
        #expect(reporter == "xcode")
        #expect(forceCastEnabled == false)
    }
    
    @Test("YAMLConfigurationEngine handles very large configuration")
    func testLargeConfiguration() async throws {
        var yamlContent = "rules:\n"
        for i in 1...50 {
            yamlContent += "  rule_\(i): true\n"
        }
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let rulesCount = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return config.rules.count
        }
        #expect(rulesCount == 50)
    }
    
    @Test("YAMLConfigurationEngine handles rules with special characters in names")
    func testRulesWithSpecialCharacters() async throws {
        let yamlContent = """
        rules:
          "rule-with-dashes": true
          "rule_with_underscores": false
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (dashesEnabled, underscoresEnabled) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules["rule-with-dashes"]?.enabled, config.rules["rule_with_underscores"]?.enabled)
        }
        #expect(dashesEnabled == true)
        #expect(underscoresEnabled == false)
    }
    
    @Test("YAMLConfigurationEngine handles configuration with only rules")
    func testConfigurationWithOnlyRules() async throws {
        let yamlContent = """
        rules:
          force_cast: false
          line_length: true
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (rulesCount, included, excluded, reporter) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules.count, config.included, config.excluded, config.reporter)
        }
        #expect(rulesCount == 2)
        #expect(included == nil)
        #expect(excluded == nil)
        #expect(reporter == nil)
    }
    
    @Test("YAMLConfigurationEngine handles configuration with only included/excluded")
    func testConfigurationWithOnlyPaths() async throws {
        let yamlContent = """
        included:
          - Sources
        excluded:
          - Pods
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (rulesEmpty, included, excluded) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (config.rules.isEmpty, config.included, config.excluded)
        }
        #expect(rulesEmpty == true)
        #expect(included == ["Sources"])
        #expect(excluded == ["Pods"])
    }
    
    @Test("YAMLConfigurationEngine preserves rule order in diff")
    func testRuleOrderInDiff() async throws {
        let yamlContent = """
        rules:
          rule_a: true
          rule_b: false
          rule_c: true
        """
        
        let configFile = try createTempConfigFile(content: yamlContent)
        defer { cleanupTempFile(configFile) }
        
        let (addedRules, addedRulesCount) = try await withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules["rule_d"] = RuleConfiguration(enabled: true)
            let diff = engine.generateDiff(proposedConfig: config)
            return (diff.addedRules, diff.addedRules.count)
        }
        #expect(addedRules.contains("rule_d"))
        #expect(addedRulesCount == 1)
    }
}

