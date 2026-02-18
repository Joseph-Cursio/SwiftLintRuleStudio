//
//  Rule.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Represents a SwiftLint rule with all its metadata
struct Rule: Identifiable, Codable, Hashable, Sendable {
    nonisolated let id: String // rule identifier (e.g., "force_cast")
    nonisolated let name: String
    nonisolated let description: String
    nonisolated let category: RuleCategory
    nonisolated let isOptIn: Bool
    nonisolated var severity: Severity?
    nonisolated let parameters: [RuleParameter]?
    nonisolated let triggeringExamples: [String]
    nonisolated let nonTriggeringExamples: [String]
    nonisolated let documentation: URL?

    // Configuration state (not from SwiftLint, managed by app)
    nonisolated var isEnabled: Bool = false
    nonisolated var configuredSeverity: Severity?
    nonisolated var configuredParameters: [String: AnyCodable]?

    // Additional metadata from generate-docs
    nonisolated var supportsAutocorrection: Bool = false
    nonisolated var minimumSwiftVersion: String?
    nonisolated var defaultSeverity: Severity?
    nonisolated var markdownDocumentation: String?

    nonisolated init(
        id: String,
        name: String,
        description: String,
        category: RuleCategory,
        isOptIn: Bool,
        severity: Severity? = nil,
        parameters: [RuleParameter]? = nil,
        triggeringExamples: [String] = [],
        nonTriggeringExamples: [String] = [],
        documentation: URL? = nil,
        isEnabled: Bool = false,
        configuredSeverity: Severity? = nil,
        configuredParameters: [String: AnyCodable]? = nil,
        supportsAutocorrection: Bool = false,
        minimumSwiftVersion: String? = nil,
        defaultSeverity: Severity? = nil,
        markdownDocumentation: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.isOptIn = isOptIn
        self.severity = severity
        self.parameters = parameters
        self.triggeringExamples = triggeringExamples
        self.nonTriggeringExamples = nonTriggeringExamples
        self.documentation = documentation
        self.isEnabled = isEnabled
        self.configuredSeverity = configuredSeverity
        self.configuredParameters = configuredParameters
        self.supportsAutocorrection = supportsAutocorrection
        self.minimumSwiftVersion = minimumSwiftVersion
        self.defaultSeverity = defaultSeverity
        self.markdownDocumentation = markdownDocumentation
    }
}

/// Categories of SwiftLint rules
enum RuleCategory: String, Codable, CaseIterable, Identifiable {
    case style
    case lint
    case metrics
    case performance
    case idiomatic
    
    var id: String { rawValue }
    
    nonisolated var displayName: String {
        rawValue.capitalized
    }
}

/// Severity level for rule violations
enum Severity: String, Codable, CaseIterable, Identifiable {
    case warning
    case error
    
    var id: String { rawValue }
    
    nonisolated var displayName: String {
        rawValue.capitalized
    }
}

/// Parameter for configurable rules
struct RuleParameter: Codable, Hashable, Sendable {
    nonisolated let name: String
    nonisolated let type: ParameterType
    nonisolated let defaultValue: AnyCodable
    nonisolated let description: String?

    nonisolated init(name: String, type: ParameterType, defaultValue: AnyCodable, description: String? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.description = description
    }
}

enum ParameterType: String, Codable {
    case integer
    case string
    case boolean
    case array
}

// Helper for encoding/decoding Any values
// Safety invariant: Only stores JSON primitives (Int, String, Bool, Double, arrays thereof)
// which are all Sendable. The decoder enforces this by only accepting these types.
struct AnyCodable: Codable, Hashable, @unchecked Sendable {
    // Safety: Only stores JSON primitives (Int, String, Bool, Double, arrays thereof).
    // nonisolated(unsafe) is valid here: `let` prevents mutation after init,
    // and @unchecked Sendable documents this type's thread-safety guarantee.
    nonisolated(unsafe) let value: Any

    nonisolated init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int:
            try container.encode(int)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        default:
            let context = EncodingError.Context(
                codingPath: [],
                debugDescription: "Unsupported type"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}
