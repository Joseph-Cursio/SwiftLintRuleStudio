import Foundation
import SwiftLintInProcessBackend
import SwiftLintRuleStudioCore
import Testing

/// A workspace at `<base>/ws` holding `B.swift`, beside `<base>/real/inner/A.swift`, with links
/// and configs that exercise how SwiftLint treats symlinks.
enum SymlinkScenario: String, CaseIterable, Sendable, CustomTestStringConvertible {
    /// One `force_cast` per file, so the violations name the files SwiftLint linted.
    static let source = "import Foundation\n\nlet number = NSNumber(value: 1) as! Int\n"

    case nestedLinkWithoutExclusions
    case nestedLinkWithExclusions
    case linkToWalkedFolderWithExclusions
    case includedLinkWithoutExclusions
    case linkInsideIncludedLinkWithoutExclusions
    case linkInsideIncludedFolderWithExclusions
    case fileLinkWithoutExclusions
    case fileLinkWithExclusions
    case globstarIncludedWithExclusions
    case includedEntriesThroughLinkWithExclusions
    case globstarFilesIncluded
    case symlinkedNestedConfigWithExclusions
    case exclusionUnderLinkPath
    case exclusionUnderIncludedPathThroughLink
    case twoLinksToOneFolderWithExclusions
    case configAboveOutsideFolderWithExclusions
    case cyclicLinkWithoutExclusions
    case outsideFileLinkWithExclusions
    case outsideFileLinkWithoutExclusions
    case includedLinkIntoPrunedFolder

    var testDescription: String { rawValue }

    var config: String {
        switch self {
        case .nestedLinkWithoutExclusions, .fileLinkWithoutExclusions, .cyclicLinkWithoutExclusions,
             .outsideFileLinkWithoutExclusions:
            "disabled_rules:\n  - todo\n"
        case .outsideFileLinkWithExclusions: "excluded:\n  - Nothing\n"
        case .includedLinkIntoPrunedFolder: "included:\n  - Sources\n  - Generated\n"
        case .nestedLinkWithExclusions, .linkToWalkedFolderWithExclusions, .fileLinkWithExclusions,
             .configAboveOutsideFolderWithExclusions:
            "excluded:\n  - Nope\n"
        case .includedLinkWithoutExclusions, .linkInsideIncludedLinkWithoutExclusions: "included:\n  - Linked\n"
        case .linkInsideIncludedFolderWithExclusions: "included:\n  - Sources\nexcluded:\n  - Nope\n"
        case .globstarIncludedWithExclusions: "included:\n  - Sources/**\nexcluded:\n  - Sources/Generated\n"
        case .includedEntriesThroughLinkWithExclusions:
            "included:\n  - Sources\n  - Sources/Linked\nexcluded:\n  - Nope\n"
        case .globstarFilesIncluded: "included:\n  - Sources/**/*.swift\n"
        case .symlinkedNestedConfigWithExclusions: "excluded:\n  - Pods\n"
        case .exclusionUnderLinkPath: "excluded:\n  - Shared/Generated\n"
        case .exclusionUnderIncludedPathThroughLink:
            "included:\n  - Sources/Linked/inner\nexcluded:\n  - Sources/Linked/inner/Gen\n"
        case .twoLinksToOneFolderWithExclusions: "included:\n  - App\n  - Widget\nexcluded:\n  - Nope\n"
        }
    }

    /// The `force_cast` violations SwiftLint reports, so the case exercises what its name says
    /// rather than agreeing on nothing.
    var expectedCount: Int {
        switch self {
        case .nestedLinkWithoutExclusions: 1 // B; `subpaths` doesn't go into the link
        case .nestedLinkWithExclusions: 2 // B, A through the link
        case .linkToWalkedFolderWithExclusions: 2 // B, R once though reached twice
        case .includedLinkWithoutExclusions: 1 // A
        case .linkInsideIncludedLinkWithoutExclusions: 1 // A; not O behind the nested link
        case .linkInsideIncludedFolderWithExclusions: 2 // S, A through the nested link
        case .fileLinkWithoutExclusions, .fileLinkWithExclusions: 2 // B, A through the file link
        // A, through the link the walk of `Sources/` follows, and S twice: SwiftLint reaches it
        // from `Sources/` and from `Sources/*`, spelled differently, so its de-duplication misses.
        case .globstarIncludedWithExclusions: 3
        case .includedEntriesThroughLinkWithExclusions: 2 // S, A once
        case .globstarFilesIncluded: 1 // S; the expansion never enters the link
        case .symlinkedNestedConfigWithExclusions: 2 // B, T at the linked config's severity
        case .exclusionUnderLinkPath: 3 // B, A, G: G's real path isn't excluded
        case .exclusionUnderIncludedPathThroughLink: 2 // A, G likewise
        case .twoLinksToOneFolderWithExclusions: 2 // Main, A once
        case .configAboveOutsideFolderWithExclusions: 2 // B, A at the severity of the config above real/
        case .cyclicLinkWithoutExclusions: 1 // B
        // B, and E at its real path under the config beside it (a warning) — or, with no
        // `excluded`, at the link's path under the workspace's (an error).
        case .outsideFileLinkWithExclusions, .outsideFileLinkWithoutExclusions: 2
        case .includedLinkIntoPrunedFolder: 2 // S, and G through the link into `.build`
        }
    }

    /// One thing to set up, relative to the workspace (`ws/…`) or beside it (`base/…`).
    enum Step {
        /// A file holding a `force_cast`.
        case file(String)
        /// A file holding `content`.
        case text(String, content: String)
        /// A symlink at the path, to the destination as written.
        case link(String, destination: String)
    }

    var steps: [Step] {
        switch self {
        case .nestedLinkWithoutExclusions, .nestedLinkWithExclusions, .includedLinkWithoutExclusions:
            [.link("ws/Linked", destination: "../real")]
        case .linkToWalkedFolderWithExclusions: [.file("ws/Real/R.swift"), .link("ws/Linked", destination: "Real")]
        case .linkInsideIncludedLinkWithoutExclusions:
            [
                .file("base/other/O.swift"),
                .link("base/real/Nested", destination: "../other"),
                .link("ws/Linked", destination: "../real")
            ]
        case .linkInsideIncludedFolderWithExclusions, .includedEntriesThroughLinkWithExclusions:
            [.file("ws/Sources/S.swift"), .link("ws/Sources/Linked", destination: "../../real")]
        case .fileLinkWithoutExclusions, .fileLinkWithExclusions:
            [.link("ws/FileLink.swift", destination: "../real/inner/A.swift")]
        case .globstarIncludedWithExclusions, .globstarFilesIncluded:
            [.file("ws/Sources/S.swift"), .link("ws/Sources/Shared", destination: "../../real")]
        case .symlinkedNestedConfigWithExclusions:
            [
                .text("base/config/tests.yml", content: "force_cast:\n  severity: warning\n"),
                .file("ws/Tests/T.swift"),
                .link("ws/Tests/.swiftlint.yml", destination: "../../config/tests.yml")
            ]
        case .exclusionUnderLinkPath: [.file("base/real/Generated/G.swift"), .link("ws/Shared", destination: "../real")]
        case .exclusionUnderIncludedPathThroughLink:
            [.file("base/real/inner/Gen/G.swift"), .link("ws/Sources/Linked", destination: "../../real")]
        case .twoLinksToOneFolderWithExclusions:
            [
                .file("ws/App/Main.swift"),
                .link("ws/App/Shared", destination: "../../real"),
                .link("ws/Widget/Shared", destination: "../../real")
            ]
        case .configAboveOutsideFolderWithExclusions:
            [
                .text("base/.swiftlint.yml", content: "force_cast:\n  severity: warning\n"),
                .link("ws/Linked", destination: "../real")
            ]
        case .cyclicLinkWithoutExclusions: [.link("ws/Sources/loop", destination: "..")]
        case .outsideFileLinkWithExclusions, .outsideFileLinkWithoutExclusions:
            [
                .text("base/elsewhere/.swiftlint.yml", content: "force_cast:\n  severity: warning\n"),
                .file("base/elsewhere/E.swift"),
                .link("ws/Sources/E.swift", destination: "../../elsewhere/E.swift")
            ]
        case .includedLinkIntoPrunedFolder:
            [
                .file("ws/Sources/S.swift"),
                .file("ws/.build/plugins/outputs/gen/G.swift"),
                .link("ws/Generated", destination: ".build/plugins/outputs/gen")
            ]
        }
    }

    func build(base: URL) throws {
        let manager = FileManager.default
        for step in steps {
            switch step {
            case .file(let path), .text(let path, _):
                let url = base.appendingPathComponent(Self.location(path))
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let content = if case .text(_, let content) = step { content } else { Self.source }
                try content.write(to: url, atomically: true, encoding: .utf8)
            case let .link(path, destination):
                let url = base.appendingPathComponent(Self.location(path))
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
            }
        }
    }

    /// `ws/…` is in the workspace, `base/…` beside it.
    private static func location(_ path: String) -> String {
        path.hasPrefix("base/") ? String(path.dropFirst("base/".count)) : path
    }
}

/// A rule simulation must count the files behind a symlink exactly when SwiftLint linting the
/// real workspace does, under the config SwiftLint applies there. Each case lints the real
/// workspace in-process, simulates the same rule over it, and requires the same files at the
/// same severities.
@MainActor
@Suite(.serialized)
struct InProcessSymlinkAgreementTests {
    private func makeWorkspace(for scenario: SymlinkScenario) throws -> (workspace: URL, base: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessSymlinkAgreementTests-\(UUID().uuidString)", isDirectory: true)
        let workspace = base.appendingPathComponent("ws", isDirectory: true)
        let inner = base.appendingPathComponent("real/inner", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        for file in [workspace.appendingPathComponent("B.swift"), inner.appendingPathComponent("A.swift")] {
            try SymlinkScenario.source.write(to: file, atomically: true, encoding: .utf8)
        }
        try scenario.config.write(
            to: workspace.appendingPathComponent(".swiftlint.yml"),
            atomically: true,
            encoding: .utf8
        )
        try scenario.build(base: base)
        return (workspace, base)
    }

    /// `path` as the real file it names, so a path through a link and the link's target agree.
    private func realFile(_ path: String, in workspace: URL) -> String {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : workspace.appendingPathComponent(path)
        return url.resolvingSymlinksInPath().path
    }

    /// The real files SwiftLint reports `force_cast` in, with the severity of each.
    private func lintedForceCasts(in workspace: URL) async throws -> [String] {
        let data = try await SwiftLintInProcessActor().executeLintCommand(configPath: nil, workspacePath: workspace)
        let report = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return report
            .filter { $0["rule_id"] as? String == "force_cast" }
            .compactMap { item -> String? in
                guard let file = item["file"] as? String, let severity = item["severity"] as? String else { return nil }
                return realFile(file, in: workspace) + " " + severity.lowercased()
            }
            .sorted()
    }

    @Test(
        "A simulation lints the files behind a symlink exactly when SwiftLint does, under the same config",
        arguments: SymlinkScenario.allCases
    )
    func simulationAgreesWithLint(_ scenario: SymlinkScenario) async throws {
        let (root, base) = try makeWorkspace(for: scenario)
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = Workspace(path: root)

        let linted = try await lintedForceCasts(in: root)
        let simulated = try await ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor()).simulateRule(
            ruleId: "force_cast",
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            options: RuleSimulationOptions()
        )
        let simulatedFiles = simulated.violations
            .map { realFile($0.filePath, in: root) + " " + $0.severity.rawValue }
            .sorted()

        #expect(linted.count == scenario.expectedCount, "SwiftLint on the real workspace: \(linted)")
        #expect(simulated.measurement == .measured)
        #expect(simulatedFiles == linted, "the simulation agrees with SwiftLint")
        #expect(
            !simulated.violations.contains { $0.filePath.contains("/SwiftLintRuleStudio/") },
            "no path into the mirror leaks out"
        )
    }

    /// An `included` entry that is itself a link yields nothing once `excluded` is set: the
    /// enumerator SwiftLint walks with doesn't open a link it is started on.
    @Test("An included link under exclusions lints nothing, and the simulation says so rather than counting")
    func includedLinkWithExclusionsAgrees() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessSymlinkAgreementTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("ws", isDirectory: true)
        let inner = base.appendingPathComponent("real/inner", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try SymlinkScenario.source.write(to: inner.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "included:\n  - Linked\nexcluded:\n  - Nope\n"
            .write(to: root.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Linked").path,
            withDestinationPath: "../real"
        )
        let workspace = Workspace(path: root)

        await #expect(throws: (any Error).self, "SwiftLint finds no lintable files") {
            _ = try await lintedForceCasts(in: root)
        }
        let simulated = try await ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor()).simulateRules(
            ruleIds: ["force_cast"],
            workspace: workspace,
            baseConfigPath: workspace.configPath
        )
        let result = try #require(simulated.results.first)
        guard case .failed(let reason) = result.measurement else {
            Issue.record("measured \(result.violationCount) where SwiftLint lints nothing")
            return
        }
        #expect(reason?.contains("No lintable files found") == true)
    }
}
