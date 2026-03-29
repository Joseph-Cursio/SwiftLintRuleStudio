//
//  Configuration.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
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

    public nonisolated init() {
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

/// Configuration for a single rule
public struct RuleConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var severity: Severity?
    public var parameters: [String: AnyCodable]?

    public nonisolated init(enabled: Bool = true, severity: Severity? = nil, parameters: [String: AnyCodable]? = nil) {
        self.enabled = enabled
        self.severity = severity
        self.parameters = parameters
    }
}

/// Represents a workspace/project
public struct Workspace: Identifiable, Equatable, Sendable {
    public nonisolated let id: UUID
    public nonisolated let path: URL
    public nonisolated let name: String
    public nonisolated var configPath: URL?
    public nonisolated var lastAnalyzed: Date?

    public nonisolated init(id: UUID = UUID(), path: URL, name: String? = nil) {
        self.id = id
        self.path = path
        self.name = name ?? path.lastPathComponent
        self.configPath = path.appendingPathComponent(".swiftlint.yml")
    }

    public nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id && lhs.path == rhs.path
    }
}
