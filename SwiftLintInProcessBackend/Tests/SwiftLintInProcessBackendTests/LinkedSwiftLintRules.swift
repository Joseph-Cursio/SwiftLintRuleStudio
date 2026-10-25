import SwiftLintFramework
import SwiftLintInProcessBackend

/// The linked SwiftLint's rules, as plain values.
///
/// SwiftLintFramework and SwiftLintRuleStudioCore both declare `Rule`, `RuleRegistry` and
/// `Severity`, so this file imports SwiftLint and not Core, and a test that compares the two
/// reads SwiftLint through here.
enum LinkedSwiftLintRules {

    /// The linked SwiftLint's version, e.g. "0.65.0".
    static var version: String {
        SwiftLintInProcessActor.prepare()
        return Version.current.value
    }

    /// Every rule identifier the linked SwiftLint knows.
    static var identifiers: Set<String> {
        Set(ruleTypes.keys)
    }

    /// Each deprecated alias, mapped to the identifier of the rule that declares it.
    static var deprecatedAliases: [String: String] {
        var aliases: [String: String] = [:]
        for (identifier, ruleType) in ruleTypes {
            for alias in ruleType.description.deprecatedAliases {
                aliases[alias] = identifier
            }
        }
        return aliases
    }

    /// The in-process backend registers only `builtInRules`; the CLI also registers
    /// `coreRules` (`custom_rules`, `superfluous_disable_command`), so they are added here.
    private static var ruleTypes: [String: any Rule.Type] {
        SwiftLintInProcessActor.prepare()
        var types = RuleRegistry.shared.list.list
        for ruleType in coreRules {
            types[ruleType.identifier] = ruleType
        }
        return types
    }
}
