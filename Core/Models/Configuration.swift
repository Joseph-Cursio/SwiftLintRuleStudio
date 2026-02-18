//
//  Configuration.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Represents a SwiftLint configuration
struct SwiftLintConfiguration: Codable, Sendable {
    nonisolated var rules: [String: RuleConfiguration]
    nonisolated var included: [String]?
    nonisolated var excluded: [String]?
    nonisolated var reporter: String?
    nonisolated var disabledRules: [String]?
    nonisolated var optInRules: [String]?
    nonisolated var analyzerRules: [String]?
    nonisolated var onlyRules: [String]?
    
    nonisolated init() {
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
struct RuleConfiguration: Codable, Equatable, Sendable {
    nonisolated var enabled: Bool
    nonisolated var severity: Severity?
    nonisolated var parameters: [String: AnyCodable]?
    
    nonisolated init(enabled: Bool = true, severity: Severity? = nil, parameters: [String: AnyCodable]? = nil) {
        self.enabled = enabled
        self.severity = severity
        self.parameters = parameters
    }
}

/// Represents a workspace/project
struct Workspace: Identifiable, Equatable, Sendable {
    nonisolated let id: UUID
    nonisolated let path: URL
    nonisolated let name: String
    nonisolated var configPath: URL?
    nonisolated var lastAnalyzed: Date?
    
    nonisolated init(id: UUID = UUID(), path: URL, name: String? = nil) {
        self.id = id
        self.path = path
        self.name = name ?? path.lastPathComponent
        self.configPath = path.appendingPathComponent(".swiftlint.yml")
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id && lhs.path == rhs.path
    }
}
