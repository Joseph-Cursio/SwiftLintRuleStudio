import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

// YAMLConfigurationEngine is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct YAMLConfigEngineSavingDiffTests {
    @Test("YAMLConfigurationEngine saves configuration to file")
    func testSaveConfiguration() async throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: "")
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try? FileManager.default.removeItem(at: configFile)

        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.rules["force_cast"] = RuleConfiguration(enabled: true, severity: .error)
            config.disabledRules = ["todo"]
            config.included = ["Sources"]
            return config
        }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: false)
        }

        #expect(FileManager.default.fileExists(atPath: configFile.path))

        let (rulesCount, forceCastSeverity, disabledRules, included) = try
            YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
                try engine.load()
                let loadedConfig = engine.getConfig()
                return (
                    rulesCount: loadedConfig.rules.count,
                    forceCastSeverity: loadedConfig.rules["force_cast"]?.severity,
                    disabledRules: loadedConfig.disabledRules,
                    included: loadedConfig.included
                )
            }

        #expect(rulesCount == 1)
        #expect(forceCastSeverity == .error)
        #expect(disabledRules == ["todo"])
        #expect(included == ["Sources"])
    }

    @Test("YAMLConfigurationEngine creates backup when saving")
    func testSaveCreatesBackup() throws {
        let yamlContent = """
        rules:
          force_cast: false
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let config = try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules["line_length"] = RuleConfiguration(enabled: true)
            return config
        }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: true)
        }

        let configDir = configFile.deletingLastPathComponent()
        let backupFiles = try FileManager.default
            .contentsOfDirectory(at: configDir, includingPropertiesForKeys: nil)
            .filter {
                $0.lastPathComponent.hasPrefix(configFile.lastPathComponent)
                    && $0.lastPathComponent.hasSuffix(".backup")
            }
        #expect(backupFiles.isEmpty == false, "Backup file should be created")

        for backupFile in backupFiles {
            try? FileManager.default.removeItem(at: backupFile)
        }
    }

    @Test("YAMLConfigurationEngine performs atomic write")
    func testAtomicWrite() async throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: "")
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try? FileManager.default.removeItem(at: configFile)

        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.rules["test_rule"] = RuleConfiguration(enabled: true)
            return config
        }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: false)
        }

        let tempFile = configFile.appendingPathExtension("tmp")
        #expect(FileManager.default.fileExists(atPath: tempFile.path) == false)
        #expect(FileManager.default.fileExists(atPath: configFile.path))
    }

    @Test("YAMLConfigurationEngine generates diff for added rules")
    func testDiffAddedRules() throws {
        let yamlContent = """
        rules:
          force_cast: false
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let diffSnapshot = try YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules["line_length"] = RuleConfiguration(enabled: true)
            let diff = engine.generateDiff(proposedConfig: config)
            return (
                hasChanges: diff.hasChanges,
                addedRules: diff.addedRules,
                removedRules: diff.removedRules,
                modifiedRules: diff.modifiedRules
            )
        }

        #expect(diffSnapshot.hasChanges)
        #expect(diffSnapshot.addedRules.contains("line_length"))
        #expect(diffSnapshot.removedRules.isEmpty)
        #expect(diffSnapshot.modifiedRules.isEmpty)
    }

    @Test("YAMLConfigurationEngine generates diff for removed rules")
    func testDiffRemovedRules() throws {
        let yamlContent = """
        rules:
          force_cast: false
          line_length: true
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let removedSnapshot = try YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules.removeValue(forKey: "line_length")
            let diff = engine.generateDiff(proposedConfig: config)
            return (
                hasChanges: diff.hasChanges,
                removedRules: diff.removedRules,
                addedRules: diff.addedRules,
                modifiedRules: diff.modifiedRules
            )
        }

        #expect(removedSnapshot.hasChanges)
        #expect(removedSnapshot.removedRules.contains("line_length"))
        #expect(removedSnapshot.addedRules.isEmpty)
        #expect(removedSnapshot.modifiedRules.isEmpty)
    }

    @Test("YAMLConfigurationEngine generates diff for modified rules")
    func testDiffModifiedRules() throws {
        let yamlContent = """
        rules:
          force_cast:
            severity: warning
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let modifiedSnapshot = try YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules["force_cast"] = RuleConfiguration(enabled: true, severity: .error)
            let diff = engine.generateDiff(proposedConfig: config)
            return (
                hasChanges: diff.hasChanges,
                modifiedRules: diff.modifiedRules,
                addedRules: diff.addedRules,
                removedRules: diff.removedRules
            )
        }

        #expect(modifiedSnapshot.hasChanges)
        #expect(modifiedSnapshot.modifiedRules.contains("force_cast"))
        #expect(modifiedSnapshot.addedRules.isEmpty)
        #expect(modifiedSnapshot.removedRules.isEmpty)
    }

    @Test("YAMLConfigurationEngine round-trips analyzer_rules through save and load")
    func testRoundTripAnalyzerRules() async throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: "")
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try? FileManager.default.removeItem(at: configFile)

        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.analyzerRules = ["unused_declaration", "unused_import"]
            return config
        }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: false)
        }

        let savedYAML = try String(contentsOf: configFile, encoding: .utf8)
        #expect(savedYAML.contains("analyzer_rules"))
        // Should not leak into opt_in_rules
        #expect(savedYAML.contains("opt_in_rules") == false)

        let analyzerRules = try YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            return engine.getConfig().analyzerRules
        }

        #expect(analyzerRules?.contains("unused_declaration") == true)
        #expect(analyzerRules?.contains("unused_import") == true)
        #expect(analyzerRules?.count == 2)
    }

    @Test("YAMLConfigurationEngine detects no changes in diff")
    func testDiffNoChanges() throws {
        let yamlContent = """
        rules:
          force_cast: false
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let diffSnapshot = try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            let diff = engine.generateDiff(proposedConfig: config)
            return (
                diff.hasChanges,
                diff.addedRules,
                diff.removedRules,
                diff.modifiedRules
            )
        }

        #expect(diffSnapshot.0 == false)
        #expect(diffSnapshot.1.isEmpty)
        #expect(diffSnapshot.2.isEmpty)
        #expect(diffSnapshot.3.isEmpty)
    }
}
