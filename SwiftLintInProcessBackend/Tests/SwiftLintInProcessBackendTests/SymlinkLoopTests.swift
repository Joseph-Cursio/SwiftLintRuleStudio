import Foundation
import SwiftLintFramework
@testable import SwiftLintInProcessBackend
import Testing

/// A workspace with `Sources/A.swift`, `App/Feature/B.swift`, and — unless `loop` is nil — a
/// link at `loop` back to the workspace's root. With `underPrivate`, it is spelled by its real
/// path, under `/private`, as an open panel gives a folder in `/tmp` or `/var`.
private struct LoopWorkspace {
    let root: URL
    let config: URL

    init(config yaml: String, loop: String? = "Sources/loop", underPrivate: Bool = false) throws {
        var temporary = FileManager.default.temporaryDirectory
        if underPrivate, let real = realpath(temporary.path, nil) {
            defer { free(real) }
            temporary = URL(fileURLWithPath: String(cString: real), isDirectory: true)
        }
        root = temporary.appendingPathComponent("slintloop-\(UUID().uuidString)", isDirectory: true)
        config = root.appendingPathComponent(".swiftlint.yml")
        try folder("Sources")
        try folder("App/Feature")
        try "class foo {}\n".write(
            to: root.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8
        )
        try "let value = 1\n".write(
            to: root.appendingPathComponent("App/Feature/B.swift"), atomically: true, encoding: .utf8
        )
        try yaml.write(to: config, atomically: true, encoding: .utf8)
        if let loop {
            try link(loop, to: "..")
        }
    }

    func folder(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(path), withIntermediateDirectories: true
        )
    }

    func link(_ path: String, to destination: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A folder symlink back into a folder holding it. SwiftLint, collecting files with `excluded`
/// set, follows such a link round for ever until the stack overflows — `SIGBUS` — and in-process
/// that is the app. The lints that could reach SwiftLint's walk run in a child process (exit
/// tests), so a regression fails the test instead of taking the test runner down.
@Suite
struct SymlinkLoopTests {

    // MARK: - Through the lint

    @Test("Linting a looping link with `excluded` set fails with an error, not a crash")
    func lintRefusesLoop() async {
        await #expect(processExitsWith: .success) {
            let workspace = try LoopWorkspace(config: "excluded:\n  - Build\n")
            defer { workspace.remove() }
            do {
                _ = try await SwiftLintInProcessActor()
                    .executeLintCommand(configPath: workspace.config, workspacePath: workspace.root)
                exit(2)
            } catch let error as SymlinkLoopError {
                guard error.link == "Sources/loop" else { exit(3) }
            }
        }
    }

    @Test("A looping link that `excluded` names lints like any workspace")
    func lintsExcludedLoop() async {
        await #expect(processExitsWith: .success) {
            let workspace = try LoopWorkspace(config: "excluded:\n  - Sources/loop\n")
            defer { workspace.remove() }
            let data = try await SwiftLintInProcessActor()
                .executeLintCommand(configPath: workspace.config, workspacePath: workspace.root)
            let violations = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            guard violations?.contains(where: { $0["rule_id"] as? String == "type_name" }) == true else { exit(3) }
        }
    }

    /// Under `/private`, SwiftLint spells `excluded` with that prefix and matches a link's path
    /// without it, so naming the link doesn't skip it: `swiftlint lint` crashes there too.
    @Test("Under /private, a looping link that `excluded` names still fails the lint, not the app")
    func lintRefusesExcludedLoopUnderPrivate() async {
        await #expect(processExitsWith: .success) {
            let workspace = try LoopWorkspace(config: "excluded:\n  - Sources/loop\n", underPrivate: true)
            defer { workspace.remove() }
            guard workspace.root.path.hasPrefix("/private/") else { exit(4) }
            do {
                _ = try await SwiftLintInProcessActor()
                    .executeLintCommand(configPath: workspace.config, workspacePath: workspace.root)
                exit(2)
            } catch let error as SymlinkLoopError {
                guard error == SymlinkLoopError(link: "Sources/loop", excludingSkipsLink: false) else { exit(3) }
            }
        }
    }

    /// Without `excluded`, SwiftLint lists files with `subpaths(atPath:)`, which doesn't follow
    /// links, so the check leaves that case alone.
    @Test("Without `excluded`, SwiftLint doesn't follow the loop, and the lint succeeds")
    func lintsLoopWithoutExclusions() async {
        await #expect(processExitsWith: .success) {
            let workspace = try LoopWorkspace(config: "disabled_rules:\n  - todo\n")
            defer { workspace.remove() }
            _ = try await SwiftLintInProcessActor()
                .executeLintCommand(configPath: workspace.config, workspacePath: workspace.root)
        }
    }

    // MARK: - The check alone

    // These never let SwiftLint walk the files, so they run in-process.

    @Test("A loop deeper down, through a link to a folder above, is refused at that link")
    func refusesDeepLoop() throws {
        let workspace = try LoopWorkspace(config: "excluded:\n  - Build\n", loop: nil)
        defer { workspace.remove() }
        try workspace.link("App/Feature/up", to: "../../App")

        #expect(throws: SymlinkLoopError(link: "App/Feature/up")) {
            try check(workspace)
        }
    }

    @Test("A loop inside an excluded folder isn't walked, so isn't refused")
    func allowsLoopInExcludedFolder() throws {
        let workspace = try LoopWorkspace(config: "excluded:\n  - Vendor\n", loop: nil)
        defer { workspace.remove() }
        try workspace.link("Vendor/Pod/loop", to: "..")

        try check(workspace)
    }

    @Test("Links that reach one folder two ways, or a folder beside, aren't loops")
    func allowsLinksWithoutLoops() throws {
        let workspace = try LoopWorkspace(config: "excluded:\n  - Build\n", loop: nil)
        defer { workspace.remove() }
        try workspace.folder("Shared/Models")
        try workspace.link("Sources/shared", to: "../Shared")
        try workspace.link("App/models", to: "../Shared/Models")

        try check(workspace)
    }

    @Test("With `included`, only the loops in what it names are walked")
    func checksOnlyIncludedFolders() throws {
        let outside = try LoopWorkspace(config: "included:\n  - App\nexcluded:\n  - Build\n")
        defer { outside.remove() }
        try check(outside)

        let inside = try LoopWorkspace(config: "included:\n  - Sources\nexcluded:\n  - Build\n")
        defer { inside.remove() }
        #expect(throws: SymlinkLoopError(link: "Sources/loop")) {
            try check(inside)
        }
    }

    @Test("A glob in `included` is checked from the folder above its first wildcard")
    func checksFromAboveGlob() throws {
        let workspace = try LoopWorkspace(config: "included:\n  - Sour*\nexcluded:\n  - Build\n")
        defer { workspace.remove() }

        #expect(throws: SymlinkLoopError(link: "Sources/loop")) {
            try check(workspace)
        }
    }

    @Test("Under /private, the refusal says to exclude the folder that holds the link, not the link")
    func advisesExcludingHolderUnderPrivate() throws {
        let workspace = try LoopWorkspace(config: "excluded:\n  - Sources/loop\n", underPrivate: true)
        defer { workspace.remove() }
        try #require(workspace.root.path.hasPrefix("/private/"), "the temporary directory isn't under /private")

        let error = #expect(throws: SymlinkLoopError.self) {
            try check(workspace)
        }
        #expect(error == SymlinkLoopError(link: "Sources/loop", excludingSkipsLink: false))
        let advice = try #require(error?.errorDescription)
        #expect(advice.contains("exclude Sources, the folder that holds it"))
        #expect(!advice.contains("Add it to `excluded`"))
    }

    @Test("Under /private, excluding the folder that holds a looping link keeps SwiftLint out of it")
    func allowsLoopInExcludedFolderUnderPrivate() throws {
        let workspace = try LoopWorkspace(config: "excluded:\n  - Sources\n", underPrivate: true)
        defer { workspace.remove() }
        try #require(workspace.root.path.hasPrefix("/private/"), "the temporary directory isn't under /private")

        try check(workspace)
    }

    @Test("A looping link at the workspace's top can only be removed or moved")
    func advisesRemovingTopLevelLink() {
        let advice = SymlinkLoopError(link: "loop", excludingSkipsLink: false).errorDescription ?? ""
        #expect(advice.contains("remove the link, or keep it in a folder `excluded` names"))
    }

    /// The check as a lint makes it: in the workspace, where SwiftLint spells `excluded` from.
    private func check(_ workspace: LoopWorkspace) throws {
        SwiftLintInProcessActor.prepare()
        try CurrentWorkingDirectory.$url.withValue(workspace.root) {
            let configuration = try InProcessConfiguration.root(
                configPath: workspace.config,
                workspacePath: workspace.root
            ).configuration
            try SymlinkLoopCheck.check(configuration, workspacePath: workspace.root)
        }
    }
}
