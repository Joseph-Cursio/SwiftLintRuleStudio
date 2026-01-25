//
//  Configuration.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Represents a SwiftLint configuration
struct SwiftLintConfiguration: Codable {
    var rules: [String: RuleConfiguration]
    var included: [String]?
    var excluded: [String]?
    var reporter: String?
    var disabledRules: [String]?
    var optInRules: [String]?
    var analyzerRules: [String]?
    var onlyRules: [String]?
    
    init() {
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
struct RuleConfiguration: Codable, Equatable {
    var enabled: Bool
    var severity: Severity?
    var parameters: [String: AnyCodable]?
    
    init(enabled: Bool = true, severity: Severity? = nil, parameters: [String: AnyCodable]? = nil) {
        self.enabled = enabled
        self.severity = severity
        self.parameters = parameters
    }
}

/// Represents a workspace/project
struct Workspace: Identifiable, Equatable {
    let id: UUID
    let path: URL
    let name: String
    var configPath: URL?
    var lastAnalyzed: Date?
    
    init(id: UUID = UUID(), path: URL, name: String? = nil) {
        self.id = id
        self.path = path
        self.name = name ?? path.lastPathComponent
        self.configPath = path.appendingPathComponent(".swiftlint.yml")
    }
    
    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id && lhs.path == rhs.path
    }
}
