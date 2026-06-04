//
//  ConfigVerificationHarness.swift
//  SwiftLintRuleStudio
//
//  Reconciles the resolved-config merge engine against SwiftLint itself. For a
//  folder's ResolvedConfiguration, it lints a probe snippet per rule in that
//  folder's real context and confirms SwiftLint agrees with what the engine
//  claims is active. Divergences are surfaced loudly rather than shipped as
//  silent wrong answers. See docs/nested-config-visibility.md.
//

import Foundation

/// Built-in probes for rules with reliable, parameter-free syntactic triggers.
/// (Threshold rules like `line_length` are intentionally excluded: their firing
/// depends on a configured value, so they cannot answer a binary active/suppressed
/// question.)
public enum RuleProbeLibrary {
    /// The default probe set, covering both default-on and opt-in rules.
    nonisolated public static let all: [RuleProbe] = [
        RuleProbe(
            ruleIdentifier: "force_try",
            isOptIn: false,
            triggeringSource: "func probeMake() throws -> Int { 0 }\nlet probeValue = try! probeMake()\n"
        ),
        RuleProbe(
            ruleIdentifier: "force_cast",
            isOptIn: false,
            triggeringSource: "let probeAny: Any = 1\nlet probeCast = probeAny as! String\n"
        ),
        RuleProbe(
            ruleIdentifier: "todo",
            isOptIn: false,
            triggeringSource: "// TODO: probe marker\n"
        ),
        RuleProbe(
            ruleIdentifier: "force_unwrapping",
            isOptIn: true,
            triggeringSource: "let probeOptional: Int? = 1\nlet probeUnwrapped = probeOptional!\n"
        ),
        RuleProbe(
            ruleIdentifier: "empty_count",
            isOptIn: true,
            triggeringSource: "let probeArray: [Int] = []\nlet probeIsEmpty = probeArray.count == 0\n"
        )
    ]

    /// The probe for a given rule, if one exists.
    nonisolated public static func probe(for ruleIdentifier: String) -> RuleProbe? {
        all.first { $0.ruleIdentifier == ruleIdentifier }
    }
}

/// Minimal decode of a SwiftLint JSON violation — just the rule identifier.
private struct ProbeViolationRecord: Decodable {
    let ruleID: String

    enum CodingKeys: String, CodingKey {
        case ruleID = "rule_id"
    }
}

/// Verifies a folder's resolved configuration against SwiftLint.
public struct ConfigVerificationHarness: Sendable {
    /// Lints `probe` in `targetDirectory`'s context and reports whether the
    /// probe's rule fired. Injected so the reconciliation logic can be tested
    /// without invoking SwiftLint.
    public typealias ProbeLinter = @Sendable (_ probe: RuleProbe, _ targetDirectory: URL) async throws -> Bool

    nonisolated private let probeLinter: ProbeLinter

    nonisolated public init(probeLinter: @escaping ProbeLinter) {
        self.probeLinter = probeLinter
    }

    /// Reconciles `resolved` against SwiftLint for each probe, returning a report
    /// of matches and divergences.
    nonisolated public func verify(
        _ resolved: ResolvedConfiguration,
        probes: [RuleProbe] = RuleProbeLibrary.all
    ) async throws -> VerificationReport {
        var verifications: [RuleVerification] = []
        for probe in probes {
            let claimsActive = Self.engineClaimsRuleActive(probe, in: resolved)
            let reported = try await probeLinter(probe, resolved.targetDirectory)
            verifications.append(RuleVerification(
                ruleIdentifier: probe.ruleIdentifier,
                engineClaimsActive: claimsActive,
                swiftLintReported: reported
            ))
        }
        return VerificationReport(targetDirectory: resolved.targetDirectory, verifications: verifications)
    }

    /// Whether the resolved config says a probe's rule runs in the folder.
    ///
    /// - `only_rules` mode: active iff the rule is in the whitelist.
    /// - otherwise: a disabled rule is inactive; an opt-in rule is active only
    ///   when opted in; a default-on rule is active unless disabled.
    nonisolated static func engineClaimsRuleActive(
        _ probe: RuleProbe,
        in resolved: ResolvedConfiguration
    ) -> Bool {
        if let onlyRules = resolved.onlyRules {
            return onlyRules.value.contains(probe.ruleIdentifier)
        }
        if resolved.disabledRules.contains(where: { $0.identifier == probe.ruleIdentifier }) {
            return false
        }
        if probe.isOptIn {
            return resolved.optInRules.contains { $0.identifier == probe.ruleIdentifier }
        }
        return true
    }

    // MARK: - SwiftLint-backed probe linter

    /// Common install locations for the `swiftlint` executable.
    nonisolated public static let knownSwiftLintPaths: [String] = [
        "/opt/homebrew/bin/swiftlint",
        "/usr/local/bin/swiftlint",
        "/usr/bin/swiftlint"
    ]

    /// The first installed `swiftlint` executable, if any.
    nonisolated public static func defaultSwiftLintExecutable() -> URL? {
        knownSwiftLintPaths
            .first { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// A probe linter that writes the probe into the target folder and lints just
    /// that file with **`swiftlint` run from `workspaceRoot`**, then removes it.
    ///
    /// Running from the workspace root is essential: SwiftLint takes its *main*
    /// config from the working directory and merges nested configs for
    /// directories between it and the linted file — it does not walk upward. So
    /// the cwd must be the workspace root for the full root → … → folder chain to
    /// apply. (This is why `--config` is not used: it would disable nested
    /// resolution.) A generic runner that inherits an ambient working directory
    /// can be contaminated by an unrelated `.swiftlint.yml`, which is exactly the
    /// kind of silent wrong answer this harness exists to prevent.
    ///
    /// - Note: briefly writes a uniquely-named `.swift` file into `targetDirectory`,
    ///   removed immediately (even on error).
    nonisolated public static func swiftLintProbeLinter(
        executable: URL,
        workspaceRoot: URL
    ) -> ProbeLinter {
        { probe, targetDirectory in
            let probeURL = targetDirectory.appendingPathComponent(
                "_SwiftLintProbe_\(UUID().uuidString).swift"
            )
            try probe.triggeringSource.write(to: probeURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: probeURL) }

            let lintData = try runSwiftLint(
                executable: executable,
                workingDirectory: workspaceRoot,
                lintFile: probeURL
            )
            return parseFiredRuleIDs(from: lintData).contains(probe.ruleIdentifier)
        }
    }

    /// Runs `swiftlint lint --reporter json <lintFile>` from `workingDirectory`
    /// and returns stdout. stderr is discarded (it carries only progress noise
    /// and could otherwise fill its pipe and deadlock).
    nonisolated private static func runSwiftLint(
        executable: URL,
        workingDirectory: URL,
        lintFile: URL
    ) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["lint", "--reporter", "json", lintFile.path]
        process.currentDirectoryURL = workingDirectory
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    /// Extracts the set of rule identifiers SwiftLint reported from its JSON output.
    nonisolated static func parseFiredRuleIDs(from data: Data) -> Set<String> {
        guard let violations = try? JSONDecoder().decode([ProbeViolationRecord].self, from: data) else {
            return []
        }
        return Set(violations.map(\.ruleID))
    }
}
