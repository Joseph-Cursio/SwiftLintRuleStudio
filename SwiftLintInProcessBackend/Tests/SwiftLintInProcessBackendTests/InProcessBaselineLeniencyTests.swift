import Foundation
import SwiftLintFramework
@testable import SwiftLintInProcessBackend
import Testing

/// Writes what `swiftlint lint --write-baseline` would: every violation `workspace` has now,
/// keyed as SwiftLint keys them, by their path from the workspace. For a workspace whose config
/// sets neither `strict` nor `lenient` and that has no nested configs.
enum BaselineWriter {
    static func write(of workspace: URL, to file: URL) throws {
        SwiftLintInProcessActor.prepare()
        try CurrentWorkingDirectory.$url.withValue(workspace) {
            let root = try InProcessConfiguration.root(configPath: nil, workspacePath: workspace).configuration
            let storage = RuleStorage()
            let violations = root.lintableFiles(inPath: workspace, forceExclude: false, excludeByPrefix: false)
                .map { Linter(file: $0, configuration: root).collect(into: storage) }
                .flatMap { $0.styleViolations(using: storage) }
            try Baseline(violations: violations).write(toPath: file)
        }
    }
}

/// The root config's `baseline`, `strict` and `lenient`, which `swiftlint lint` applies to
/// what it reports — so Studio, which runs it, does. The expectations here are what
/// `swiftlint lint` reports for the same workspace.
@Suite(.serialized)
struct InProcessBaselineLeniencyTests {
    /// A `force_cast`, an error, on line 3; a `todo`, a warning, on line 4.
    private static let source = """
        import Foundation

        let number = NSNumber(value: 1) as! Int
        let value = 1 // TODO: tidy

        """

    /// A workspace in a fresh temporary folder holding `Old.swift`, and `config` when given.
    private func makeWorkspace(config: String?) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessBaselineLeniencyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(Self.source, to: folder.appendingPathComponent("Old.swift"))
        if let config {
            try write(config, to: folder.appendingPathComponent(".swiftlint.yml"))
        }
        return folder
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// What the workspace analysis reports, as `file rule severity`, sorted.
    private func reported(in workspace: URL) async throws -> [String] {
        let data = try await SwiftLintInProcessActor().executeLintCommand(configPath: nil, workspacePath: workspace)
        let report = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return report.compactMap { item -> String? in
            guard let file = item["file"] as? String,
                  let rule = item["rule_id"] as? String,
                  let severity = item["severity"] as? String else { return nil }
            return "\(URL(fileURLWithPath: file).lastPathComponent) \(rule) \(severity.lowercased())"
        }
        .sorted()
    }

    /// The lines `todo` is reported on, each with its severity.
    private func reportedTodos(in workspace: URL) throws -> [String] {
        let data = try SwiftLintInProcessActor.lint(configPath: nil, workspacePath: workspace)
        let report = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return report.compactMap { item -> String? in
            guard let line = item["line"] as? Int, let severity = item["severity"] as? String else { return nil }
            return "\(line) \(severity.lowercased())"
        }
        .sorted()
    }

    // MARK: - baseline

    @Test("A violation the baseline holds isn't reported; the same one in a new file is")
    func baselinedViolationIsHidden() async throws {
        let workspace = try makeWorkspace(config: nil)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try BaselineWriter.write(of: workspace, to: workspace.appendingPathComponent("baseline.json"))
        try write(Self.source, to: workspace.appendingPathComponent("New.swift"))
        try write("baseline: baseline.json\n", to: workspace.appendingPathComponent(".swiftlint.yml"))

        #expect(try await reported(in: workspace) == ["New.swift force_cast error", "New.swift todo warning"])
    }

    @Test("A baseline that isn't there is skipped, as swiftlint lint skips it with a warning")
    func missingBaselineIsSkipped() async throws {
        let workspace = try makeWorkspace(config: "baseline: missing.json\n")
        defer { try? FileManager.default.removeItem(at: workspace) }

        #expect(try await reported(in: workspace) == ["Old.swift force_cast error", "Old.swift todo warning"])
    }

    @Test("A baseline SwiftLint can't read fails the lint, naming the file")
    func unreadableBaselineFails() async throws {
        let workspace = try makeWorkspace(config: "baseline: baseline.json\n")
        defer { try? FileManager.default.removeItem(at: workspace) }
        try write("not a baseline", to: workspace.appendingPathComponent("baseline.json"))

        let error = await #expect(throws: InProcessConfigurationError.self) {
            _ = try await reported(in: workspace)
        }
        #expect(error?.localizedDescription.contains("baseline.json") == true)
    }

    // MARK: - strict and lenient

    @Test("strict reports every warning as an error")
    func strictRaisesWarnings() async throws {
        let workspace = try makeWorkspace(config: "strict: true\n")
        defer { try? FileManager.default.removeItem(at: workspace) }

        #expect(try await reported(in: workspace) == ["Old.swift force_cast error", "Old.swift todo error"])
    }

    @Test("lenient reports every error as a warning")
    func lenientLowersErrors() async throws {
        let workspace = try makeWorkspace(config: "lenient: true\n")
        defer { try? FileManager.default.removeItem(at: workspace) }

        #expect(try await reported(in: workspace) == ["Old.swift force_cast warning", "Old.swift todo warning"])
    }

    /// `swiftlint lint` ends the process for this; in-process, that would be the app.
    @Test("strict and lenient together fail the lint")
    func strictAndLenientFail() async throws {
        let workspace = try makeWorkspace(config: "strict: true\nlenient: true\n")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let error = await #expect(throws: (any Error).self) {
            _ = try await reported(in: workspace)
        }
        #expect(error?.localizedDescription.contains("mutually exclusive") == true)
    }

    // MARK: - Which config counts, and in what order

    /// The nested config's settings are ignored even when they'd fail the lint.
    @Test("Only the root config's settings count, not a nested config's", arguments: [
        ("strict: true\n", "lenient: true\n", "error"),
        ("lenient: true\n", "strict: true\n", "warning"),
        ("disabled_rules:\n  - trailing_newline\n", "strict: true\nlenient: true\n", nil),
        ("disabled_rules:\n  - trailing_newline\n", "baseline: ../baseline.json\n", nil)
    ])
    func onlyRootSettingsCount(root: String, nested: String, severity: String?) async throws {
        let workspace = try makeWorkspace(config: nil)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.removeItem(at: workspace.appendingPathComponent("Old.swift"))
        try write(Self.source, to: workspace.appendingPathComponent("Nested/Inner.swift"))
        try BaselineWriter.write(of: workspace, to: workspace.appendingPathComponent("baseline.json"))
        try write(root, to: workspace.appendingPathComponent(".swiftlint.yml"))
        try write(nested, to: workspace.appendingPathComponent("Nested/.swiftlint.yml"))

        // Every violation at `severity`, or, with none, at its rule's own.
        #expect(try await reported(in: workspace) == [
            "Inner.swift force_cast \(severity ?? "error")",
            "Inner.swift todo \(severity ?? "warning")"
        ])
    }

    /// A baseline drops what matches it exactly, severity and all, and compares the rest by
    /// their line's text. Line 2's `todo` matches exactly until `strict` raises it; then it and
    /// line 4's, which share its text, outnumber the baseline's one, and both are reported.
    @Test("strict applies before the baseline filters, as in swiftlint lint", arguments: [
        (false, ["4 warning"]),
        (true, ["2 error", "4 error"])
    ])
    func strictAppliesBeforeBaseline(strict: Bool, expected: [String]) throws {
        let workspace = try makeWorkspace(config: "only_rules:\n  - todo\n")
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.removeItem(at: workspace.appendingPathComponent("Old.swift"))
        try write("let a = 1\n// TODO: x\nlet b = 2\n", to: workspace.appendingPathComponent("A.swift"))
        try BaselineWriter.write(of: workspace, to: workspace.appendingPathComponent("baseline.json"))
        try write("let a = 1\n// TODO: x\nlet b = 2\n// TODO: x\n", to: workspace.appendingPathComponent("A.swift"))
        try write(
            "only_rules:\n  - todo\nbaseline: baseline.json\n" + (strict ? "strict: true\n" : ""),
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )

        #expect(try reportedTodos(in: workspace) == expected)
    }
}
