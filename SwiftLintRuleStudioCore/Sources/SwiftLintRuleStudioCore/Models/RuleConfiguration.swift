//
//  RuleConfiguration.swift
//  SwiftLintRuleStudio
//

/// Configuration for a single rule
public struct RuleConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var severity: Severity?
    public var parameters: [String: AnyCodable]?

    nonisolated public init(enabled: Bool = true, severity: Severity? = nil, parameters: [String: AnyCodable]? = nil) {
        self.enabled = enabled
        self.severity = severity
        self.parameters = parameters
    }
}
