//
//  ConfigurationTemplateManagerTests.swift
//  SwiftLintRuleStudioTests
//
//  Unit tests for ConfigurationTemplateManager
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct ConfigurationTemplateManagerTests {
    // MARK: - Built-in Templates Tests

    @Test("Built-in templates exist")
    func testBuiltInTemplatesExist() {
        let manager = ConfigurationTemplateManager()
        let templates = manager.builtInTemplates

        #expect(templates.count == 9) // 3 project types x 3 styles
    }

    @Test("Each covered project type has all coding styles")
    func testEachProjectTypeHasAllStyles() {
        let manager = ConfigurationTemplateManager()
        let templates = manager.builtInTemplates

        // Only check project types that have built-in templates
        let coveredProjectTypes = Set(templates.map(\.projectType))
        for projectType in coveredProjectTypes {
            let projectTemplates = templates.filter { $0.projectType == projectType }
            let styles = Set(projectTemplates.map(\.codingStyle))
            #expect(
                styles.count == ConfigurationTemplate.CodingStyle.allCases.count,
                "Project type \(projectType) should have all coding styles"
            )
        }
    }

    @Test("All built-in templates have unique IDs")
    func testBuiltInTemplatesHaveUniqueIds() {
        let manager = ConfigurationTemplateManager()
        let templates = manager.builtInTemplates

        let ids = Set(templates.map(\.id))
        #expect(ids.count == templates.count)
    }

    @Test("All built-in templates have valid YAML content")
    func testBuiltInTemplatesHaveValidYAML() {
        let manager = ConfigurationTemplateManager()
        let templates = manager.builtInTemplates

        for template in templates {
            #expect(template.yamlContent.isEmpty == false, "Template \(template.name) has empty YAML")
            #expect(
                template.yamlContent.contains("#") || template.yamlContent.contains(":"),
                "Template \(template.name) should have valid YAML structure"
            )
        }
    }

    @Test("All built-in templates are marked as built-in")
    func testBuiltInTemplatesAreMarkedAsBuiltIn() {
        let manager = ConfigurationTemplateManager()
        let templates = manager.builtInTemplates

        for template in templates {
            #expect(template.isBuiltIn, "Template \(template.name) should be marked as built-in")
        }
    }

    // MARK: - Filter Tests

    @Test("Can filter templates by project type")
    func testFilterByProjectType() {
        let manager = ConfigurationTemplateManager()

        let iosCount = manager.templates(for: .iOSApp).count
        let macOSCount = manager.templates(for: .macOSApp).count
        let packageCount = manager.templates(for: .swiftPackage).count

        #expect(iosCount == 3)
        #expect(macOSCount == 3)
        #expect(packageCount == 3)
    }

    @Test("Can filter templates by coding style")
    func testFilterByCodingStyle() {
        let manager = ConfigurationTemplateManager()

        let strictCount = manager.templates(for: .strict).count
        let balancedCount = manager.templates(for: .balanced).count
        let lenientCount = manager.templates(for: .lenient).count

        #expect(strictCount == 3)
        #expect(balancedCount == 3)
        #expect(lenientCount == 3)
    }

    // MARK: - ConfigurationTemplate Tests

    @Test("ConfigurationTemplate is equatable")
    func testConfigurationTemplateEquatable() {
        let template1 = BuiltInTemplates.iOSStrict
        let template2 = BuiltInTemplates.iOSStrict
        let template3 = BuiltInTemplates.iOSBalanced

        #expect(template1 == template2)
        #expect(template1 != template3)
    }

    @Test("ConfigurationTemplate is codable")
    func testConfigurationTemplateCodable() throws {
        let template = BuiltInTemplates.iOSStrict

        let encoder = JSONEncoder()
        let data = try encoder.encode(template)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ConfigurationTemplate.self, from: data)

        #expect(decoded.id == template.id)
        #expect(decoded.name == template.name)
        #expect(decoded.description == template.description)
        #expect(decoded.projectType == template.projectType)
        #expect(decoded.codingStyle == template.codingStyle)
        #expect(decoded.yamlContent == template.yamlContent)
        #expect(decoded.isBuiltIn == template.isBuiltIn)
    }

    // MARK: - ProjectType Tests

    @Test("ProjectType has display values")
    func testProjectTypeDisplayValues() {
        #expect(ConfigurationTemplate.ProjectType.iOSApp.rawValue == "iOS App")
        #expect(ConfigurationTemplate.ProjectType.macOSApp.rawValue == "macOS App")
        #expect(ConfigurationTemplate.ProjectType.swiftPackage.rawValue == "Swift Package")
        #expect(ConfigurationTemplate.ProjectType.tvOSApp.rawValue == "tvOS App")
        #expect(ConfigurationTemplate.ProjectType.watchOSApp.rawValue == "watchOS App")
    }

    @Test("ProjectType has icons")
    func testProjectTypeIcons() {
        #expect(ConfigurationTemplate.ProjectType.iOSApp.icon.isEmpty == false)
        #expect(ConfigurationTemplate.ProjectType.macOSApp.icon.isEmpty == false)
        #expect(ConfigurationTemplate.ProjectType.swiftPackage.icon.isEmpty == false)
        #expect(ConfigurationTemplate.ProjectType.tvOSApp.icon.isEmpty == false)
        #expect(ConfigurationTemplate.ProjectType.watchOSApp.icon.isEmpty == false)
    }

    // MARK: - CodingStyle Tests

    @Test("CodingStyle has display values")
    func testCodingStyleDisplayValues() {
        #expect(ConfigurationTemplate.CodingStyle.strict.rawValue == "Strict")
        #expect(ConfigurationTemplate.CodingStyle.balanced.rawValue == "Balanced")
        #expect(ConfigurationTemplate.CodingStyle.lenient.rawValue == "Lenient")
    }

    @Test("CodingStyle has descriptions")
    func testCodingStyleDescriptions() {
        #expect(ConfigurationTemplate.CodingStyle.strict.description.isEmpty == false)
        #expect(ConfigurationTemplate.CodingStyle.balanced.description.isEmpty == false)
        #expect(ConfigurationTemplate.CodingStyle.lenient.description.isEmpty == false)
    }

    // MARK: - TemplateError Tests

    @Test("TemplateError has error descriptions")
    func testTemplateErrorDescriptions() {
        #expect(TemplateError.cannotDeleteBuiltIn.errorDescription != nil)
        #expect(TemplateError.serializationFailed.errorDescription != nil)
        #expect(TemplateError.templateNotFound.errorDescription != nil)
    }

    // MARK: - Template Application Tests

    @Test("Can apply template to file")
    func testApplyTemplate() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test_\(UUID()).swiftlint.yml")

        defer {
            try? FileManager.default.removeItem(at: configPath)
        }

        let manager = ConfigurationTemplateManager()
        let template = BuiltInTemplates.iOSBalanced
        try manager.applyTemplate(template, to: configPath)

        let content = try String(contentsOf: configPath, encoding: .utf8)
        #expect(content == BuiltInTemplates.iOSBalanced.yamlContent)
    }

    // MARK: - BuiltInTemplates Specific Tests

    @Test("iOS Strict template has expected opt-in rules")
    func testIOSStrictTemplate() {
        let template = BuiltInTemplates.iOSStrict

        #expect(template.projectType == .iOSApp)
        #expect(template.codingStyle == .strict)
        #expect(template.yamlContent.contains("opt_in_rules"))
        #expect(template.yamlContent.contains("force_unwrapping"))
    }

    @Test("iOS Lenient template disables many rules")
    func testIOSLenientTemplate() {
        let template = BuiltInTemplates.iOSLenient

        #expect(template.projectType == .iOSApp)
        #expect(template.codingStyle == .lenient)
        #expect(template.yamlContent.contains("disabled_rules"))
        #expect(template.yamlContent.contains("line_length"))
    }

    @Test("Swift Package templates exclude .build directory")
    func testPackageTemplatesExcludeBuild() {
        let packageTemplates = [
            BuiltInTemplates.packageStrict,
            BuiltInTemplates.packageBalanced,
            BuiltInTemplates.packageLenient
        ]

        for template in packageTemplates {
            #expect(
                template.yamlContent.contains(".build"),
                "Package template \(template.name) should exclude .build"
            )
        }
    }

    @Test("All templates exclude common dependency directories")
    func testTemplatesExcludeCommonDirs() {
        let templates = BuiltInTemplates.all

        for template in templates {
            // At minimum, most should exclude something
            #expect(
                template.yamlContent.contains("excluded"),
                "Template \(template.name) should have excluded paths"
            )
        }
    }
}

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
            name: "House Style",
            description: "What we actually use",
            projectType: .swiftPackage,
            codingStyle: .balanced,
            from: makeConfig(),
            identifier: identifier
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
            name: "House Style",
            description: "What we actually use",
            projectType: .swiftPackage,
            codingStyle: .balanced,
            from: makeConfig(),
            identifier: identifier
        )

        let reader = ConfigurationTemplateManager(templatesDirectory: directory)
        let reloaded = try #require(reader.userTemplates.first(where: { $0.id == identifier }))
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
            name: "Throwaway",
            description: "",
            projectType: .iOSApp,
            codingStyle: .lenient,
            from: makeConfig(),
            identifier: identifier
        )
        let written = directory.appendingPathComponent("\(identifier.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: written.path))

        try manager.deleteTemplate(template)

        #expect(FileManager.default.fileExists(atPath: written.path) == false)
        #expect(manager.userTemplates.contains(where: { $0.id == identifier }) == false)
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
            name: "Watch Style",
            description: "",
            projectType: .watchOSApp,
            codingStyle: .strict,
            from: makeConfig(),
            identifier: identifier
        )

        // No built-in template covers watchOS, so this is the user template alone.
        let watchTemplates = manager.templates(for: ConfigurationTemplate.ProjectType.watchOSApp)
        #expect(watchTemplates.map(\.id) == [identifier])
    }
}

