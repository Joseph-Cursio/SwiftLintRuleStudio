//
//  ConfigurationTemplateManager.swift
//  SwiftLintRuleStudio
//
//  Service for managing SwiftLint configuration templates
//
// swiftlint:disable file_length

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

// MARK: - Built-in Templates

/// Static definitions for built-in templates
enum BuiltInTemplates { // swiftlint:disable:this type_body_length
    /// Converts a known-valid UUID string literal into a UUID.
    /// Raises a precondition failure (not a crash in production) if the string is malformed.
    private static func builtInID(_ string: String) -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("Invalid built-in template UUID literal: \(string)")
        }
        return uuid
    }

    // MARK: - iOS App Templates

    static let iOSStrict = ConfigurationTemplate(
        id: builtInID("00000000-0000-0000-0000-000000000001"),
        name: "iOS App - Strict",
        description: "Maximum code quality for iOS applications",
        projectType: .iOSApp,
        codingStyle: .strict,
        yamlContent: """
        # SwiftLint Configuration - iOS App (Strict)
        # Generated by SwiftLint Rule Studio

        excluded:
          - Pods
          - Carthage
          - vendor
          - build
          - DerivedData
          - "*.generated.swift"

        opt_in_rules:
          - attributes
          - closure_end_indentation
          - closure_spacing
          - collection_alignment
          - contains_over_filter_count
          - contains_over_filter_is_empty
          - contains_over_first_not_nil
          - discouraged_object_literal
          - empty_collection_literal
          - empty_count
          - empty_string
          - enum_case_associated_values_count
          - explicit_init
          - first_where
          - flatmap_over_map_reduce
          - force_unwrapping
          - implicit_return
          - joined_default_parameter
          - last_where
          - modifier_order
          - multiline_arguments
          - multiline_parameters
          - operator_usage_whitespace
          - overridden_super_call
          - prefer_self_type_over_type_of_self
          - redundant_nil_coalescing
          - redundant_type_annotation
          - sorted_first_last
          - toggle_bool
          - trailing_closure
          - unneeded_parentheses_in_closure_argument
          - vertical_parameter_alignment_on_call
          - yoda_condition

        line_length:
          warning: 120
          error: 200
          ignores_urls: true
          ignores_function_declarations: false
          ignores_comments: true

        type_body_length:
          warning: 300
          error: 500

        file_length:
          warning: 500
          error: 1000
          ignore_comment_only_lines: true

        function_body_length:
          warning: 50
          error: 100

        cyclomatic_complexity:
          warning: 10
          error: 20

        nesting:
          type_level:
            warning: 2
            error: 3
          function_level:
            warning: 3
            error: 5
        """,
        isBuiltIn: true
    )

    static let iOSBalanced = ConfigurationTemplate(
        id: builtInID("00000000-0000-0000-0000-000000000002"),
        name: "iOS App - Balanced",
        description: "Good balance of quality and flexibility for iOS apps",
        projectType: .iOSApp,
        codingStyle: .balanced,
        yamlContent: """
        # SwiftLint Configuration - iOS App (Balanced)
        # Generated by SwiftLint Rule Studio

        excluded:
          - Pods
          - Carthage
          - vendor
          - build

        opt_in_rules:
          - empty_count
          - empty_string
          - first_where
          - last_where
          - modifier_order
          - sorted_first_last
          - contains_over_first_not_nil

        disabled_rules:
          - todo
          - trailing_whitespace

        line_length:
          warning: 140
          error: 250
          ignores_urls: true
          ignores_comments: true

        type_body_length:
          warning: 400
          error: 600

        file_length:
          warning: 600
          error: 1200

        function_body_length:
          warning: 60
          error: 150
        """,
        isBuiltIn: true
    )

    static let iOSLenient = ConfigurationTemplate(
        id: builtInID("00000000-0000-0000-0000-000000000003"),
        name: "iOS App - Lenient",
        description: "Minimal rules focused on critical issues",
        projectType: .iOSApp,
        codingStyle: .lenient,
        yamlContent: """
        # SwiftLint Configuration - iOS App (Lenient)
        # Generated by SwiftLint Rule Studio

        excluded:
          - Pods
          - Carthage

        disabled_rules:
          - line_length
          - file_length
          - type_body_length
          - function_body_length
          - cyclomatic_complexity
          - todo
          - trailing_whitespace
          - identifier_name
          - nesting

        force_cast: warning
        force_try: warning
        """,
        isBuiltIn: true
    )

    // MARK: - macOS App Templates

    static let macOSStrict = ConfigurationTemplate(
        id: builtInID("00000000-0000-0000-0000-000000000004"),
        name: "macOS App - Strict",
        description: "Maximum code quality for macOS applications",
        projectType: .macOSApp,
        codingStyle: .strict,
        yamlContent: """
        # SwiftLint Configuration - macOS App (Strict)
        # Generated by SwiftLint Rule Studio

        excluded:
          - Pods
          - Carthage
          - vendor
          - build
          - DerivedData

        opt_in_rules:
          - attributes
          - closure_end_indentation
          - closure_spacing
          - collection_alignment
          - contains_over_filter_count
          - empty_count
          - empty_string
          - explicit_init
          - first_where
          - force_unwrapping
          - implicit_return
          - last_where
          - modifier_order
          - overridden_super_call
          - redundant_nil_coalescing
          - sorted_first_last
          - trailing_closure
          - yoda_condition

        line_length:
          warning: 120
          error: 200
          ignores_urls: true

        type_body_length:
          warning: 300
          error: 500

        file_length:
          warning: 500
          error: 1000
        """,
        isBuiltIn: true
    )

    static let macOSBalanced = ConfigurationTemplate(
        id: builtInID("00000000-0000-0000-0000-000000000005"),
        name: "macOS App - Balanced",
        description: "Good balance for macOS applications",
        projectType: .macOSApp,
        codingStyle: .balanced,
        yamlContent: """
        # SwiftLint Configuration - macOS App (Balanced)
        # Generated by SwiftLint Rule Studio

        excluded:
          - Pods
          - Carthage
          - vendor

        opt_in_rules:
          - empty_count
          - first_where
          - last_where
          - modifier_order

        line_length:
          warning: 140
          error: 250
          ignores_urls: true
        """,
        isBuiltIn: true
    )

    static let macOSLenient = ConfigurationTemplate(
        id: builtInID("00000000-0000-0000-0000-000000000006"),
        name: "macOS App - Lenient",
        description: "Minimal rules for macOS applications",
        projectType: .macOSApp,
        codingStyle: .lenient,
        yamlContent: """
        # SwiftLint Configuration - macOS App (Lenient)
        # Generated by SwiftLint Rule Studio

        excluded:
          - Pods
          - Carthage

        disabled_rules:
          - line_length
          - file_length
          - todo
          - trailing_whitespace
        """,
        isBuiltIn: true
    )

    // MARK: - Swift Package Templates

    static let packageStrict = ConfigurationTemplate(
        id: builtInID("00000000-0000-0000-0000-000000000007"),
        name: "Swift Package - Strict",
        description: "Maximum code quality for Swift packages",
        projectType: .swiftPackage,
        codingStyle: .strict,
        yamlContent: """
        # SwiftLint Configuration - Swift Package (Strict)
        # Generated by SwiftLint Rule Studio

        excluded:
          - .build
          - Package.swift
          - Tests/LinuxMain.swift

        opt_in_rules:
          - attributes
          - closure_spacing
          - collection_alignment
          - contains_over_filter_count
          - empty_count
          - empty_string
          - explicit_init
          - first_where
          - force_unwrapping
          - implicit_return
          - last_where
          - missing_docs
          - modifier_order
          - redundant_nil_coalescing
          - sorted_first_last
          - yoda_condition

        line_length:
          warning: 120
          error: 200

        type_body_length:
          warning: 250
          error: 400

        file_length:
          warning: 400
          error: 800
        """,
        isBuiltIn: true
    )

    static let packageBalanced = ConfigurationTemplate(
        id: builtInID("00000000-0000-0000-0000-000000000008"),
        name: "Swift Package - Balanced",
        description: "Good balance for Swift packages",
        projectType: .swiftPackage,
        codingStyle: .balanced,
        yamlContent: """
        # SwiftLint Configuration - Swift Package (Balanced)
        # Generated by SwiftLint Rule Studio

        excluded:
          - .build
          - Package.swift

        opt_in_rules:
          - empty_count
          - first_where
          - last_where

        line_length:
          warning: 140
          error: 250
        """,
        isBuiltIn: true
    )

    static let packageLenient = ConfigurationTemplate(
        id: builtInID("00000000-0000-0000-0000-000000000009"),
        name: "Swift Package - Lenient",
        description: "Minimal rules for Swift packages",
        projectType: .swiftPackage,
        codingStyle: .lenient,
        yamlContent: """
        # SwiftLint Configuration - Swift Package (Lenient)
        # Generated by SwiftLint Rule Studio

        excluded:
          - .build

        disabled_rules:
          - line_length
          - todo
        """,
        isBuiltIn: true
    )

    // MARK: - All Templates

    static var all: [ConfigurationTemplate] {
        [
            iOSStrict, iOSBalanced, iOSLenient,
            macOSStrict, macOSBalanced, macOSLenient,
            packageStrict, packageBalanced, packageLenient
        ]
    }
}
