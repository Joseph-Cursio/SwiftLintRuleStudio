//
//  YAMLConfigEngineLayoutBoundaryTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Where editing a file in place stops: what it refuses to edit, and the lines inside a
//  section it has to step over or read through.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct YAMLConfigEngineLayoutBoundaryTests {
    private func edited(
        _ yaml: String,
        _ change: (inout YAMLConfigurationEngine.YAMLConfig) -> Void
    ) throws -> String {
        var config = try YAMLConfigurationEngine.parse(yaml)
        change(&config)
        return try YAMLConfigurationEngine.serialize(config, preservingLayoutOf: yaml)
    }

    @Test("A second document, a document end or a tab-indented line after the first key isn't edited in place",
          arguments: [
              "disabled_rules:\n  - todo\n---\nopt_in_rules:\n  - empty_count\n",
              "disabled_rules:\n  - todo\n...\n",
              "disabled_rules:\n  - todo\n\topt_in_rules: [empty_count]\n"
          ])
    func refusesWhatIsNotOneBlockMapping(existing: String) {
        let regenerated = "disabled_rules:\n  - todo\nopt_in_rules:\n  - empty_count\n"

        #expect(LayoutPreservingEdit.text(editing: existing, toMatch: regenerated) == nil)
    }

    @Test("A comment among a rule's settings stays when one of them changes")
    func commentAmongSettings() throws {
        let yaml = "line_length:\n  # house style\n  warning: 160\n  error: 200\n"

        let result = try edited(yaml) {
            $0.rules["line_length"]?.parameters?["warning"] = AnyCodable(120)
        }

        #expect(result == "line_length:\n  # house style\n  warning: 120\n  error: 200\n")
    }

    @Test("A quoted top-level key is matched by its name, keeping its quotes and its place")
    func quotedKeys() throws {
        let yaml = "\"disabled_rules\":\n  - todo\n'line_length': 120\n"

        let result = try edited(yaml) { $0.disabledRules = ["todo", "force_cast"] }

        #expect(result == "\"disabled_rules\":\n  - todo\n  - force_cast\n'line_length': 120\n")
    }
}
