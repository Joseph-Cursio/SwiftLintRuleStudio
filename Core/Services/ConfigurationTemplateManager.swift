//
//  ConfigurationTemplateManager.swift
//  SwiftLintRuleStudio
//
//  Service for managing SwiftLint configuration templates
//

import Foundation
import Combine

/// Represents a configuration template
struct ConfigurationTemplate: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: UUID
    let name: String
    let description: String
    let projectType: ProjectType
    let codingStyle: CodingStyle
    let yamlContent: String
    let isBuiltIn: Bool

    enum ProjectType: String, Codable, CaseIterable, Sendable {
        case iOSApp = "iOS App"
        case macOSApp = "macOS App"
        case swiftPackage = "Swift Package"
        case tvOSApp = "tvOS App"
        case watchOSApp = "watchOS App"

        var icon: String {
            switch self {
            case .iOSApp: return "iphone"
            case .macOSApp: return "desktopcomputer"
            case .swiftPackage: return "shippingbox"
            case .tvOSApp: return "appletv"
            case .watchOSApp: return "applewatch"
            }
        }
    }

    enum CodingStyle: String, Codable, CaseIterable, Sendable {
        case strict = "Strict"
        case balanced = "Balanced"
        case lenient = "Lenient"

        var description: String {
            switch self {
            case .strict:
                return "Maximum code quality enforcement with all recommended rules"
            case .balanced:
                return "Good balance between code quality and developer flexibility"
            case .lenient:
                return "Minimal rules focused on critical issues only"
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        projectType: ProjectType,
        codingStyle: CodingStyle,
        yamlContent: String,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.projectType = projectType
        self.codingStyle = codingStyle
        self.yamlContent = yamlContent
        self.isBuiltIn = isBuiltIn
    }
}

/// Protocol for configuration template management
@MainActor
protocol ConfigurationTemplateManagerProtocol {
    /// All built-in templates
    var builtInTemplates: [ConfigurationTemplate] { get }

    /// User-created templates
    var userTemplates: [ConfigurationTemplate] { get }

    /// All templates (built-in + user)
    var allTemplates: [ConfigurationTemplate] { get }

    /// Apply a template to a configuration path
    func applyTemplate(_ template: ConfigurationTemplate, to configPath: URL) throws

    /// Save a configuration as a user template
    func saveAsTemplate(
        name: String,
        description: String,
        projectType: ConfigurationTemplate.ProjectType,
        codingStyle: ConfigurationTemplate.CodingStyle,
        from config: YAMLConfigurationEngine.YAMLConfig
    ) throws -> ConfigurationTemplate

    /// Delete a user template
    func deleteTemplate(_ template: ConfigurationTemplate) throws

    /// Get templates filtered by project type
    func templates(for projectType: ConfigurationTemplate.ProjectType) -> [ConfigurationTemplate]

    /// Get templates filtered by coding style
    func templates(for codingStyle: ConfigurationTemplate.CodingStyle) -> [ConfigurationTemplate]
}

/// Service for managing configuration templates
@MainActor
class ConfigurationTemplateManager: ConfigurationTemplateManagerProtocol {
    private let fileManager = FileManager.default
    private let userTemplatesDirectory: URL

    @Published private(set) var userTemplates: [ConfigurationTemplate] = []

    init() {
        // Set up user templates directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        userTemplatesDirectory = appSupport
            .appendingPathComponent("SwiftLintRuleStudio")
            .appendingPathComponent("Templates")

        // Create directory if needed
        try? fileManager.createDirectory(at: userTemplatesDirectory, withIntermediateDirectories: true)

        // Load user templates
        loadUserTemplates()
    }

    var builtInTemplates: [ConfigurationTemplate] {
        BuiltInTemplates.all
    }

    var allTemplates: [ConfigurationTemplate] {
        builtInTemplates + userTemplates
    }

    func applyTemplate(_ template: ConfigurationTemplate, to configPath: URL) throws {
        try template.yamlContent.write(to: configPath, atomically: true, encoding: .utf8)
    }

    func saveAsTemplate(
        name: String,
        description: String,
        projectType: ConfigurationTemplate.ProjectType,
        codingStyle: ConfigurationTemplate.CodingStyle,
        from config: YAMLConfigurationEngine.YAMLConfig
    ) throws -> ConfigurationTemplate {
        // Serialize config to YAML
        let engine = YAMLConfigurationEngine(configPath: URL(fileURLWithPath: "/tmp/temp.yml"))
        let yamlContent = try engine.serialize(config)

        let template = ConfigurationTemplate(
            name: name,
            description: description,
            projectType: projectType,
            codingStyle: codingStyle,
            yamlContent: yamlContent,
            isBuiltIn: false
        )

        // Save to disk
        let templatePath = userTemplatesDirectory.appendingPathComponent("\(template.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(template)
        try data.write(to: templatePath)

        userTemplates.append(template)
        return template
    }

    func deleteTemplate(_ template: ConfigurationTemplate) throws {
        guard !template.isBuiltIn else {
            throw TemplateError.cannotDeleteBuiltIn
        }

        let templatePath = userTemplatesDirectory.appendingPathComponent("\(template.id.uuidString).json")
        try fileManager.removeItem(at: templatePath)
        userTemplates.removeAll { $0.id == template.id }
    }

    func templates(for projectType: ConfigurationTemplate.ProjectType) -> [ConfigurationTemplate] {
        allTemplates.filter { $0.projectType == projectType }
    }

    func templates(for codingStyle: ConfigurationTemplate.CodingStyle) -> [ConfigurationTemplate] {
        allTemplates.filter { $0.codingStyle == codingStyle }
    }

    // MARK: - Private Methods

    private func loadUserTemplates() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: userTemplatesDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        userTemplates = contents.compactMap { url -> ConfigurationTemplate? in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let template = try? decoder.decode(ConfigurationTemplate.self, from: data) else {
                return nil
            }
            return template
        }
    }
}

/// Errors for template operations
enum TemplateError: LocalizedError {
    case cannotDeleteBuiltIn
    case serializationFailed
    case templateNotFound

    var errorDescription: String? {
        switch self {
        case .cannotDeleteBuiltIn:
            return "Cannot delete built-in templates"
        case .serializationFailed:
            return "Failed to serialize configuration"
        case .templateNotFound:
            return "Template not found"
        }
    }
}
