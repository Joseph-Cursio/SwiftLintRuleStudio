//
//  YAMLConfigEngineLayoutTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Saving a configuration edits the file it replaces: what the user wrote survives
//  wherever the configuration didn't change.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct YAMLConfigEngineLayoutTests {
    /// A real `.swiftlint.yml`, with comments inside a list, blank lines between sections and
    /// rule settings in a hand-picked order — all of which a save used to discard.
    private static let handWritten = """
        excluded:
          - .build
          # swift-infer verify workdirs vendor whole dependency checkouts —
          # third-party code that must not gate this repo's lint.
          - .swiftinfer
          - Tests

        line_length:
          warning: 160
          error: 200
          ignores_urls: true
          ignores_function_declarations: true
          ignores_comments: true

        function_body_length:
          warning: 100
          error: 150

        disabled_rules:
          - redundant_string_enum_value
          - todo

        """

    private func edited(
        _ yaml: String,
        _ change: (inout YAMLConfigurationEngine.YAMLConfig) -> Void
    ) throws -> String {
        var config = try YAMLConfigurationEngine.parse(yaml)
        change(&config)
        return try YAMLConfigurationEngine.serialize(config, preservingLayoutOf: yaml)
    }

    @Test("Turning on opt-in rules adds their list and leaves the rest of the file as written")
    func addingASectionKeepsTheRest() throws {
        let result = try edited(Self.handWritten) { $0.optInRules = ["array_init", "empty_count"] }

        #expect(result == Self.handWritten + """

            opt_in_rules:
              - array_init
              - empty_count

            """)
    }

    @Test("A new list item goes after the last one, and comments between items stay")
    func appendingToAList() throws {
        let result = try edited(Self.handWritten) { $0.excluded?.append("Pods") }

        #expect(result.contains("""
              - .build
              # swift-infer verify workdirs vendor whole dependency checkouts —
              # third-party code that must not gate this repo's lint.
              - .swiftinfer
              - Tests
              - Pods

            line_length:
            """))
    }

    @Test("A list written flush left stays that way, new items included")
    func keepsIndentlessLists() throws {
        let yaml = "opt_in_rules:\n- empty_count\n"
        let result = try edited(yaml) { $0.optInRules?.append("array_init") }

        #expect(result == "opt_in_rules:\n- empty_count\n- array_init\n")
    }

    @Test("A file without a final newline gets one")
    func addsFinalNewline() throws {
        #expect(try edited("excluded:\n  - Pods") { _ in } == "excluded:\n  - Pods\n")
    }

    @Test("Removing a list item removes only its line")
    func removingFromAList() throws {
        let result = try edited(Self.handWritten) { $0.disabledRules = ["redundant_string_enum_value"] }

        #expect(result == Self.handWritten.replacingOccurrences(of: "  - todo\n", with: ""))
    }

    @Test("Changing one setting rewrites only its line, keeping the block's order")
    func changingASetting() throws {
        let result = try edited(Self.handWritten) {
            $0.rules["line_length"]?.parameters?["warning"] = AnyCodable(120)
        }

        #expect(result == Self.handWritten.replacingOccurrences(of: "warning: 160", with: "warning: 120"))
    }

    @Test("Removing a section removes it and nothing else")
    func removingASection() throws {
        let result = try edited(Self.handWritten) { $0.rules["function_body_length"] = nil }

        #expect(result == Self.handWritten.replacingOccurrences(
            of: "function_body_length:\n  warning: 100\n  error: 150\n\n",
            with: ""
        ))
    }

    @Test("An unchanged configuration is written back byte for byte")
    func unchangedRoundTrip() throws {
        #expect(try edited(Self.handWritten) { _ in } == Self.handWritten)
    }

    /// What a file means to the app, read back through the engine: the modeled settings, and
    /// every other top-level setting as a value. Comments, key order and quoting don't count;
    /// types do, since SwiftLint rejects a setting of the wrong type.
    private func meaning(of yaml: String) throws -> String {
        let config = try YAMLConfigurationEngine.parse(yaml)
        let lists = [
            config.included, config.excluded, config.disabledRules,
            config.optInRules, config.analyzerRules, config.onlyRules
        ].map { canonical($0) }
        let rules = config.rules.keys.sorted().map { id -> String in
            let rule = config.rules[id]
            let parameters = (rule?.parameters ?? [:]).mapValues(\.value)
            return "\(id)=\(rule?.enabled == true),\(rule?.severity?.rawValue ?? "-"),\(canonical(parameters))"
        }
        let others = try config.passthroughNodes.keys.sorted().map { key in
            "\(key)=\(canonical(try config.passthroughNodes[key].map(YAMLConfigurationEngine.nodeToAny)))"
        }
        return (lists + [canonical(config.reporter)] + rules + others).joined(separator: "\n")
    }

    private func canonical(_ value: Any?) -> String {
        guard let value else { return "nil" }
        return switch value {
        case let map as [String: Any]:
            "{" + map.keys.sorted().map { "\($0):\(canonical(map[$0]))" }.joined(separator: ",") + "}"
        case let list as [Any]:
            "[" + list.map(canonical).joined(separator: ",") + "]"
        case let bool as Bool:
            "bool:\(bool)"
        case let int as Int:
            "int:\(int)"
        case let double as Double:
            "double:\(double)"
        case let string as String:
            "str:\(string)"
        default:
            "\(type(of: value)):\(value)"
        }
    }

    @Test("Whatever the edit, the file means exactly what a full rewrite would", arguments: [
        "excluded:\n  - a\n",
        "line_length: 120\n",
        "excluded: [a, b]\nopt_in_rules:\n  - empty_count\n",
        "base: &base\n  warning: 1\nline_length: *base\n",
        "# header\n\nopt_in_rules:\n- empty_count\n- array_init\n",
        "custom_rules:\n  no_print:\n    regex: 'print\\('\n    message: \"No print\"\n",
        "line_length:\n  warning: 1.0\n  ignores_urls: 1\n  ignores_comments: on\n"
    ])
    func editsKeepTheMeaning(yaml: String) throws {
        var config = try YAMLConfigurationEngine.parse(yaml)
        config.optInRules = (config.optInRules ?? []) + ["closure_spacing"]
        config.excluded = ["b", "c"]
        config.rules["line_length"] = RuleConfiguration(
            enabled: true,
            parameters: [
                "warning": AnyCodable(90),
                "ignores_urls": AnyCodable(true),
                "ignores_comments": AnyCodable(true)
            ]
        )

        let edited = try YAMLConfigurationEngine.serialize(config, preservingLayoutOf: yaml)
        let rewritten = try YAMLConfigurationEngine.serialize(config)

        #expect(try meaning(of: edited) == meaning(of: rewritten))
    }

    @Test("A setting changed to a value of another type is rewritten, not kept", arguments: [
        ("ignores_comments: 1", "ignores_comments: true"),
        ("ignores_comments: on", "ignores_comments: true"),
        ("warning: 120.0", "warning: 120")
    ])
    func valuesKeepTheirTypes(old: String, new: String) throws {
        let yaml = "line_length:\n  \(old)\n  error: 200\n"
        let key = String(new.prefix { $0 != ":" })
        let value: AnyCodable = new.hasSuffix("true") ? AnyCodable(true) : AnyCodable(120)

        let result = try edited(yaml) { $0.rules["line_length"]?.parameters?[key] = value }

        #expect(result == "line_length:\n  \(new)\n  error: 200\n")
    }

    @Test("Removing a list item removes the comment that described it")
    func removingAnItemRemovesItsComment() throws {
        let yaml = "disabled_rules:\n  # hundreds of TODOs to fix first\n  - todo\n  - force_cast\n"

        let result = try edited(yaml) { $0.disabledRules = ["force_cast"] }

        #expect(result == "disabled_rules:\n  - force_cast\n")
    }

    @Test("Asterisks and ampersands in comments don't stop the file being edited in place")
    func punctuationInComments() throws {
        let yaml = "excluded:\n  # e.g. *Generated folders & vendored code\n  - Generated\n\n"
            + "disabled_rules:\n  - todo\n"

        let result = try edited(yaml) { $0.optInRules = ["empty_count"] }

        #expect(result.hasPrefix(yaml))
    }

    @Test("A section that uses another's anchor is regenerated; the rest is kept")
    func anchorsAndAliases() throws {
        let yaml = "# shared limits\nbase: &base\n  warning: 1\n\nline_length: *base\n"

        let result = try edited(yaml) { $0.optInRules = ["empty_count"] }

        #expect(result.hasPrefix("# shared limits\nbase: &base\n  warning: 1\n\n"))
        #expect(try meaning(of: result) == meaning(of: YAMLConfigurationEngine.serialize(
            YAMLConfigurationEngine.parse(yaml).with { $0.optInRules = ["empty_count"] }
        )))
    }

    @Test("Saving to a file edits what's already there")
    func saveEditsTheFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("YAMLConfigEngineLayoutTests-\(UUID().uuidString).yml")
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.handWritten.write(to: file, atomically: true, encoding: .utf8)

        var config = try YAMLConfigurationEngine.loadConfig(at: file)
        config.optInRules = ["empty_count"]
        try YAMLConfigurationEngine.save(config, to: file, createBackup: false)

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.hasPrefix(Self.handWritten))
        #expect(written.contains("# third-party code that must not gate this repo's lint."))
    }

    @Test("Replacing a config with an imported one keeps the imported file's comments")
    func importReplaceKeepsImportedLayout() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("YAMLConfigEngineLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".swiftlint.yml")
        try "# Pods is vendored by CocoaPods\nexcluded:\n  - Pods\n".write(to: file, atomically: true, encoding: .utf8)

        let imported = "# Org standard: never lint generated code\nexcluded:\n  - Generated\n"
        let preview = ConfigImportPreview(
            sourceURL: URL(fileURLWithPath: "/org/.swiftlint.yml"),
            fetchedYAML: imported,
            parsedConfig: try YAMLConfigurationEngine.parse(imported),
            diff: nil,
            validationErrors: []
        )
        try ConfigImportService().applyImport(preview: preview, mode: .replace, to: file)

        #expect(try String(contentsOf: file, encoding: .utf8) == imported)
    }
}

private extension YAMLConfigurationEngine.YAMLConfig {
    func with(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
    }
}
