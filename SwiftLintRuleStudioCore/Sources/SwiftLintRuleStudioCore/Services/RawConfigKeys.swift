//
//  RawConfigKeys.swift
//  SwiftLintRuleStudio
//
//  The keys of a `.swiftlint.yml` that decide which files SwiftLint lints, read as SwiftLint
//  reads them.
//

import Foundation
import Yams

/// The keys of a config that decide which files SwiftLint lints, which other configs it loads,
/// and which custom rules it defines, read from the raw YAML.
///
/// `YAMLConfigurationEngine` reads `included` and `excluded` the same way, but it is bound to
/// the main actor, and the mirror is planned off it; so the few keys the plan needs are read
/// here, as SwiftLint reads them: a list of strings, or one string as a list of one.
nonisolated struct RawConfigKeys: Sendable {
    let excluded: [String]
    let included: [String]
    /// `parent_config` and `child_config`, in that order, where present.
    let referencedConfigs: [String]
    /// The names `custom_rules` defines: SwiftLint reports each one's violations under its own
    /// name, not `custom_rules`.
    let customRuleIds: [String]

    /// The keys of the config at `url`, or nil when it can't be read as a YAML mapping.
    static func read(_ url: URL) -> Self? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let dictionary = (try? Yams.load(yaml: text)) as? [String: Any] else { return nil }
        return Self(
            excluded: strings(dictionary["excluded"]),
            included: strings(dictionary["included"]),
            referencedConfigs: ["parent_config", "child_config"].compactMap { dictionary[$0] as? String },
            customRuleIds: ((dictionary["custom_rules"] as? [String: Any])?.keys).map { Array($0).sorted() } ?? []
        )
    }

    /// Whether the YAML at `url` holds anything — a value, not just comments — or can't be read
    /// as YAML at all. SwiftLint reads one holding nothing as an empty config.
    static func hasContent(_ url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return true }
        do {
            return try Yams.compose(yaml: text) != nil
        } catch {
            return true
        }
    }

    /// A key's value as SwiftLint takes it: a list of strings, or one string as a list of one.
    /// A list with anything but strings in it — `2024`, unquoted — SwiftLint doesn't read at
    /// all, so neither is it read here: keeping its strings would apply a list SwiftLint ignores.
    private static func strings(_ value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        guard let list = value as? [Any] else { return [] }
        let strings = list.compactMap { $0 as? String }
        return strings.count == list.count ? strings : []
    }
}
