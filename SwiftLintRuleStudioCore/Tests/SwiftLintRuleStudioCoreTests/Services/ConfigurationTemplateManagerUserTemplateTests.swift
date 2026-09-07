//
//  ConfigurationTemplateManagerUserTemplateTests.swift
//  SwiftLintRuleStudioTests
//
//  The user-template half of ConfigurationTemplateManager: saving, reloading and deleting.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

/// The user-template half of `ConfigurationTemplateManager`.
///
/// None of this could be tested before. The manager always stored templates under the real
/// `~/Library/Application Support/SwiftLintRuleStudio/Templates`, so a test of `saveAsTemplate`,
/// `deleteTemplate` or the reload path would have written into the user's own data — which is why
/// the 38 tests above only ever touch `builtInTemplates`.
@MainActor
struct ConfigurationTemplateManagerUserTemplateTests {
    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("template-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeConfig() -> YAMLConfigurationEngine.YAMLConfig {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.excluded = ["Carthage", ".build"]
        config.disabledRules = ["line_length"]
        return config
    }

    @Test("A saved template is written under its own identifier")
    func savedTemplateIsWrittenUnderItsIdentifier() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ConfigurationTemplateManager(templatesDirectory: directory)
        let identifier = UUID()

        let template = try manager.saveAsTemplate(
            ConfigurationTemplate.Draft(
                name: "House Style",
                description: "What we actually use",
                projectType: .swiftPackage,
                codingStyle: .balanced,
                identifier: identifier
            ),
            from: makeConfig()
        )

        #expect(template.id == identifier)
        #expect(template.isBuiltIn == false)
        let written = directory.appendingPathComponent("\(identifier.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: written.path))
    }

    @Test("A saved template comes back from a fresh manager over the same directory")
    func savedTemplateSurvivesAReload() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = UUID()

        let writer = ConfigurationTemplateManager(templatesDirectory: directory)
        _ = try writer.saveAsTemplate(
            ConfigurationTemplate.Draft(
                name: "House Style",
                description: "What we actually use",
                projectType: .swiftPackage,
                codingStyle: .balanced,
                identifier: identifier
            ),
            from: makeConfig()
        )

        let reader = ConfigurationTemplateManager(templatesDirectory: directory)
        let reloaded = try #require(reader.userTemplates.first { $0.id == identifier })
        #expect(reloaded.name == "House Style")
        #expect(reloaded.projectType == .swiftPackage)
        #expect(reloaded.codingStyle == .balanced)
        #expect(reloaded.yamlContent.contains("line_length"))
        #expect(reader.allTemplates.count == reader.builtInTemplates.count + 1)
    }

    @Test("Deleting a user template removes it from disk and from the list")
    func deletingRemovesTheFileAndTheEntry() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ConfigurationTemplateManager(templatesDirectory: directory)
        let identifier = UUID()

        let template = try manager.saveAsTemplate(
            ConfigurationTemplate.Draft(
                name: "Throwaway",
                description: "",
                projectType: .iOSApp,
                codingStyle: .lenient,
                identifier: identifier
            ),
            from: makeConfig()
        )
        let written = directory.appendingPathComponent("\(identifier.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: written.path))

        try manager.deleteTemplate(template)

        #expect(FileManager.default.fileExists(atPath: written.path) == false)
        #expect(manager.userTemplates.contains { $0.id == identifier } == false)
        #expect(ConfigurationTemplateManager(templatesDirectory: directory).userTemplates.isEmpty)
    }

    @Test("A built-in template cannot be deleted")
    func builtInTemplatesCannotBeDeleted() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ConfigurationTemplateManager(templatesDirectory: directory)
        let builtIn = try #require(manager.builtInTemplates.first)

        #expect(throws: TemplateError.cannotDeleteBuiltIn) {
            try manager.deleteTemplate(builtIn)
        }
    }

    @Test("Templates filtered by project type include saved user templates")
    func filteringByProjectTypeIncludesUserTemplates() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ConfigurationTemplateManager(templatesDirectory: directory)
        let identifier = UUID()

        _ = try manager.saveAsTemplate(
            ConfigurationTemplate.Draft(
                name: "Watch Style",
                description: "",
                projectType: .watchOSApp,
                codingStyle: .strict,
                identifier: identifier
            ),
            from: makeConfig()
        )

        // No built-in template covers watchOS, so this is the user template alone.
        let watchTemplates = manager.templates(for: ConfigurationTemplate.ProjectType.watchOSApp)
        #expect(watchTemplates.map(\.id) == [identifier])
    }
}
