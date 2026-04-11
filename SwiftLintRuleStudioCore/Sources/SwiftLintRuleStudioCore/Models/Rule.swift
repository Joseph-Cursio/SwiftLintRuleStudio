//
//  Rule.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Represents a SwiftLint rule with all its metadata
public struct Rule: Identifiable, Codable, Hashable, Sendable {
    public let id: String // rule identifier (e.g., "force_cast")
    public let name: String
    public let description: String
    public let category: RuleCategory
    public let isOptIn: Bool
    public var severity: Severity?
    public let parameters: [RuleParameter]?
    public let triggeringExamples: [String]
    public let nonTriggeringExamples: [String]
    public let documentation: URL?

    // Configuration state (not from SwiftLint, managed by app)
    public var isEnabled: Bool = false
    public var configuredSeverity: Severity?
    public var configuredParameters: [String: AnyCodable]?

    // Additional metadata from generate-docs
    public var supportsAutocorrection: Bool = false
    public var minimumSwiftVersion: String?
    public var defaultSeverity: Severity?
    public var markdownDocumentation: String?

    nonisolated public init(
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
public enum RuleCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case style
    case lint
    case metrics
    case performance
    case idiomatic

    nonisolated public var id: String { rawValue }

    nonisolated public var displayName: String {
        rawValue.capitalized
    }
}

/// Severity level for rule violations
public enum Severity: String, Codable, CaseIterable, Identifiable, Sendable {
    case warning
    case error

    nonisolated public var id: String { rawValue }

    nonisolated public var displayName: String {
        rawValue.capitalized
    }
}

/// Parameter for configurable rules
public struct RuleParameter: Codable, Hashable, Sendable {
    public let name: String
    public let type: ParameterType
    public let defaultValue: AnyCodable
    public let description: String?

    nonisolated public init(name: String, type: ParameterType, defaultValue: AnyCodable, description: String? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.description = description
    }
}

public enum ParameterType: String, Codable, Sendable {
    case integer
    case string
    case boolean
    case array
}

// Helper for encoding/decoding Any values
// Safety invariant: Only stores JSON primitives (Int, String, Bool, Double, arrays thereof)
// which are all Sendable. The decoder enforces this by only accepting these types.
public struct AnyCodable: Codable, Hashable, @unchecked Sendable {
    // Safety: Only stores JSON primitives (Int, String, Bool, Double, arrays thereof).
    // `let` prevents mutation after init, and @unchecked Sendable documents this
    // type's thread-safety guarantee.
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}
