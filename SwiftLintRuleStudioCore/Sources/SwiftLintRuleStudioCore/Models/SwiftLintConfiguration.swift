//
//  SwiftLintConfiguration.swift
//  SwiftLintRuleStudio
//

import Foundation

/// Represents a SwiftLint configuration
public struct SwiftLintConfiguration: Codable, Sendable {
    public var rules: [String: RuleConfiguration]
    public var included: [String]?
    public var excluded: [String]?
    public var reporter: String?
    public var disabledRules: [String]?
    public var optInRules: [String]?
    public var analyzerRules: [String]?
    public var onlyRules: [String]?

    nonisolated public init() {
        self.rules = [:]
        self.included = nil
        self.excluded = nil
        self.reporter = nil
        self.disabledRules = nil
        self.optInRules = nil
        self.analyzerRules = nil
        self.onlyRules = nil
    }
}
