import Foundation
import Testing
@testable import SwiftLIntRuleStudio

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
            config.rules["force_cast"] = RuleConfiguration(enabled: false, severity: .error)
            config.included = ["Sources"]
            return config
        }

        try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: false)
        }

        #expect(FileManager.default.fileExists(atPath: configFile.path))

        let (rulesCount, forceCastEnabled, included) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let loadedConfig = engine.getConfig()
            return (
                rulesCount: loadedConfig.rules.count,
                forceCastEnabled: loadedConfig.rules["force_cast"]?.enabled,
                included: loadedConfig.included
            )
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

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let config = try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules["line_length"] = RuleConfiguration(enabled: true)
            return config
        }

        try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: true)
        }

        let configDir = configFile.deletingLastPathComponent()
        let backupFiles = try FileManager.default
            .contentsOfDirectory(at: configDir, includingPropertiesForKeys: nil)
            .filter {
                $0.lastPathComponent.hasPrefix(configFile.lastPathComponent)
                    && $0.lastPathComponent.hasSuffix(".backup")
            }
        #expect(!backupFiles.isEmpty, "Backup file should be created")

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

        try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: false)
        }

        let tempFile = configFile.appendingPathExtension("tmp")
        #expect(!FileManager.default.fileExists(atPath: tempFile.path))
        #expect(FileManager.default.fileExists(atPath: configFile.path))
    }

    @Test("YAMLConfigurationEngine generates diff for added rules")
    func testDiffAddedRules() async throws {
        let yamlContent = """
        rules:
          force_cast: false
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let diffSnapshot = try await YAMLConfigurationEngineTestHelpers.withEngine(
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

        #expect(diffSnapshot.hasChanges == true)
        #expect(diffSnapshot.addedRules.contains("line_length"))
        #expect(diffSnapshot.removedRules.isEmpty)
        #expect(diffSnapshot.modifiedRules.isEmpty)
    }

    @Test("YAMLConfigurationEngine generates diff for removed rules")
    func testDiffRemovedRules() async throws {
        let yamlContent = """
        rules:
          force_cast: false
          line_length: true
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let removedSnapshot = try await YAMLConfigurationEngineTestHelpers.withEngine(
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

        #expect(removedSnapshot.hasChanges == true)
        #expect(removedSnapshot.removedRules.contains("line_length"))
        #expect(removedSnapshot.addedRules.isEmpty)
        #expect(removedSnapshot.modifiedRules.isEmpty)
    }

    @Test("YAMLConfigurationEngine generates diff for modified rules")
    func testDiffModifiedRules() async throws {
        let yamlContent = """
        rules:
          force_cast:
            severity: warning
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let modifiedSnapshot = try await YAMLConfigurationEngineTestHelpers.withEngine(
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

        #expect(modifiedSnapshot.hasChanges == true)
        #expect(modifiedSnapshot.modifiedRules.contains("force_cast"))
        #expect(modifiedSnapshot.addedRules.isEmpty)
        #expect(modifiedSnapshot.removedRules.isEmpty)
    }

    @Test("YAMLConfigurationEngine detects no changes in diff")
    func testDiffNoChanges() async throws {
        let yamlContent = """
        rules:
          force_cast: false
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let diffSnapshot = try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
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
