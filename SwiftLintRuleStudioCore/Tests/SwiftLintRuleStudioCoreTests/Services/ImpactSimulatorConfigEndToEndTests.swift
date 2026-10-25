//
//  ImpactSimulatorConfigEndToEndTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  A simulated rule counts what enabling it really would, through the configs that make that
//  hard to see: custom rules, deprecated names, baselines, a repository's config above a
//  package, `${PWD}`, and lists SwiftLint doesn't read. Drives the real swiftlint binary.
//

import Foundation
import SwiftLintCLIBackend
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

// SwiftLintCLIActor is an actor; CacheManager trips a Swift 6 false positive, so (as in
// ImpactSimulatorShadowEndToEndTests) the struct is marked @MainActor.
@MainActor
struct ImpactSimulatorConfigEndToEndTests {

    // MARK: - Helpers

    nonisolated private func isSwiftLintAvailable() -> Bool {
        ["/opt/homebrew/bin/swiftlint", "/usr/local/bin/swiftlint", "/usr/bin/swiftlint"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func makeTempFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigEndToEndTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func simulate(_ ruleId: String, in workspace: URL, isOptIn: Bool = false) async throws -> RuleImpactResult {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigEndToEndTests", isDirectory: true)
            .appendingPathComponent("cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let simulator = ImpactSimulator(
            swiftLintCLI: SwiftLintCLIActor(cacheManager: CacheManager(cacheDirectory: cacheDir))
        )
        return try await simulator.simulateRule(
            ruleId: ruleId,
            workspace: Workspace(path: workspace),
            baseConfigPath: workspace.appendingPathComponent(".swiftlint.yml"),
            options: RuleSimulationOptions(isOptIn: isOptIn)
        )
    }

    // MARK: - Tests

    @Test("custom_rules counts the violations of every custom rule, which SwiftLint reports by their own names")
    func customRules() async throws {
        guard isSwiftLintAvailable() else { return }
        let workspace = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try write(
            "disabled_rules:\n  - custom_rules\ncustom_rules:\n  no_number:\n    regex: \"NSNumber\"\n"
                + "    message: \"no NSNumber\"\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )
        try write(
            "import Foundation\nlet x = NSNumber(value: 1)\nlet y = NSNumber(value: 2)\n",
            to: workspace.appendingPathComponent("Sources/A.swift")
        )

        let result = try await simulate("custom_rules", in: workspace)

        #expect(result.isMeasured)
        #expect(result.violationCount == 2)
        #expect(result.violations.allSatisfy { $0.ruleID == "no_number" })
    }

    @Test("a rule disabled under a deprecated name, here or in a parent config, is enabled and counted")
    func deprecatedNames() async throws {
        guard isSwiftLintAvailable() else { return }
        let base = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = base.appendingPathComponent("App")
        // SwiftLint still reads `variable_name` as `identifier_name`.
        try write("disabled_rules:\n  - variable_name\n", to: base.appendingPathComponent("team.yml"))
        try write(
            "parent_config: ../team.yml\ndisabled_rules:\n  - variable_name\n  - todo\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )
        try write("let x = 1\nlet e = 2\n", to: workspace.appendingPathComponent("Sources/A.swift"))

        let result = try await simulate("identifier_name", in: workspace)

        #expect(result.violationCount == 2)
    }

    @Test("a baseline filters the simulated rule as it filters the real one, and write_baseline is never written")
    func baselines() async throws {
        guard isSwiftLintAvailable() else { return }
        // In a caches folder, not the temp folder: under /private SwiftLint keys a baseline by a
        // path naming the workspace's own location, which no copy of it can match.
        let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let base = caches.appendingPathComponent("ConfigEndToEndTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = base.appendingPathComponent("App")
        let source = "let anyValue: Any = 1\nlet casted = anyValue as! Int\n"
        try write(source, to: workspace.appendingPathComponent("Sources/Old.swift"))
        // A baseline of today's violations, force_cast's among them, as a team would keep one.
        try write("disabled_rules:\n  - todo\n", to: workspace.appendingPathComponent(".swiftlint.yml"))
        let make = Process()
        make.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        make.arguments = ["swiftlint", "lint", "--quiet", "--no-cache", "--write-baseline", "baseline.json"]
        make.currentDirectoryURL = workspace
        make.standardOutput = FileHandle.nullDevice
        make.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        make.environment = environment
        try make.run()
        make.waitUntilExit()
        try write(source, to: workspace.appendingPathComponent("Sources/New.swift"))
        let teamBaseline = base.appendingPathComponent("team-baseline.json")
        try write("[{\"keep\":\"me\"}]", to: teamBaseline)
        try write(
            "disabled_rules:\n  - force_cast\n  - todo\nbaseline: baseline.json\n"
                + "write_baseline: \(teamBaseline.path)\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )

        let result = try await simulate("force_cast", in: workspace)

        #expect(result.violationCount == 1, "Old.swift's is in the baseline; New.swift's isn't")
        #expect(result.affectedFiles == ["Sources/New.swift"])
        #expect(try String(contentsOf: teamBaseline, encoding: .utf8) == "[{\"keep\":\"me\"}]")
    }

    @Test("a package opened alone gets its repository's config, two folders up")
    func monorepoPackage() async throws {
        guard isSwiftLintAvailable() else { return }
        let repo = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: repo) }
        let package = repo.appendingPathComponent("Packages/Core")
        try write("line_length: 40\n", to: repo.appendingPathComponent(".swiftlint.yml"))
        try write(
            "parent_config: ../../.swiftlint.yml\ndisabled_rules:\n  - line_length\n",
            to: package.appendingPathComponent(".swiftlint.yml")
        )
        let long = "let text = \"" + String(repeating: "x", count: 50) + "\"\n"
        try write(long, to: package.appendingPathComponent("Sources/A.swift"))

        let result = try await simulate("line_length", in: package)

        #expect(result.isMeasured)
        #expect(result.violationCount == 1, "the repository's 40, not the default 120")
    }

    @Test("${PWD} in included names the lint root, as it names the workspace in a terminal there")
    func workingDirectoryVariable() async throws {
        guard isSwiftLintAvailable() else { return }
        let workspace = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try write(
            "included:\n  - ${PWD}/Sources\ndisabled_rules:\n  - force_cast\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )
        try write("let casted = (1 as Any) as! Int\n", to: workspace.appendingPathComponent("Sources/A.swift"))
        try write("let casted = (1 as Any) as! Int\n", to: workspace.appendingPathComponent("Other/B.swift"))

        let result = try await simulate("force_cast", in: workspace)

        #expect(result.affectedFiles == ["Sources/A.swift"])
    }

    @Test("an included list with an entry that isn't a string is ignored, as SwiftLint ignores it")
    func nonStringEntry() async throws {
        guard isSwiftLintAvailable() else { return }
        let workspace = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try write(
            "included:\n  - Sources\n  - 2024\ndisabled_rules:\n  - force_cast\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )
        try write("let a = 1\n", to: workspace.appendingPathComponent("Sources/A.swift"))
        try write("let casted = (1 as Any) as! Int\n", to: workspace.appendingPathComponent("2024/B.swift"))

        let result = try await simulate("force_cast", in: workspace)

        #expect(result.affectedFiles == ["2024/B.swift"], "SwiftLint lints the whole workspace")
    }

    @Test("a config holding a list of mappings is written readably, and the rule measured")
    func listOfMappingsConfig() async throws {
        guard isSwiftLintAvailable() else { return }
        let workspace = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        // The engine once wrote this list of mappings misaligned, which SwiftLint can't read; the
        // read-back check would then fail the rule rather than lint with SwiftLint's defaults.
        try write(
            "disabled_rules:\n  - force_cast\nnumber_separator:\n  minimum_length: 3\n  exclude_ranges:\n"
                + "    - min: 1900\n      max: 2030\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )
        try write("let casted = (1 as Any) as! Int\n", to: workspace.appendingPathComponent("Sources/A.swift"))

        let result = try await simulate("force_cast", in: workspace)

        #expect(result.isMeasured)
        #expect(result.violationCount == 1)
    }
}
