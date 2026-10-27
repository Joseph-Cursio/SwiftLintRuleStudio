import Foundation
@testable import SwiftLintFramework
@testable import SwiftLintInProcessBackend
import Testing

/// The configuration each file gets when nested configs apply, and what finding it leaves in
/// SwiftLint's process-wide caches.
///
/// The tests work in `/tmp`, which is `/private/tmp`, and SwiftLint reads such a path two ways. Its
/// file walk spells files `/tmp/…` when the config's `excluded` list is empty, and
/// `/private/tmp/…` when it lists anything, even a path that matches nothing. Its search for a
/// file's nested config stops at the root's folder only when the file's path and the root's folder
/// are spelled alike; otherwise it passes the root's folder and meets the workspace's own
/// `.swiftlint.yml`. So the tests spell the root both ways.
@Suite("Nested config lookup")
struct NestedConfigLookupTests {
    private static let source = "let values: [Int] = []\nlet isEmpty = values.count == 0\n"

    /// A fresh folder in `/tmp`, spelled `/private/tmp/…` when `privateRoot`, `/tmp/…` otherwise.
    private func makeFolder(privateRoot: Bool) throws -> URL {
        let folder = URL(fileURLWithPath: privateRoot ? "/private/tmp" : "/tmp", isDirectory: true)
            .appendingPathComponent("NestedConfigLookupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Both searches climb out of the folder; a config above it would change every answer.
        var above = folder.deletingLastPathComponent()
        while true {
            let stray = above.appendingPathComponent(".swiftlint.yml")
            try #require(!FileManager.default.fileExists(atPath: stray.path), "\(stray.path) is in the way")
            guard above.path != "/" else { break }
            above = above.deletingLastPathComponent()
        }
        return folder
    }

    private func write(_ text: String, to path: String, in folder: URL) throws {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func rootConfig(excludes: Bool) -> String {
        "opt_in_rules:\n  - empty_count\n" + (excludes ? "excluded:\n  - Nope\n" : "")
    }

    @Test(
        "Every file gets the configuration SwiftLint's own lookup gives it",
        arguments: [false, true], [false, true]
    )
    func agreesWithSwiftLint(privateRoot: Bool, excludes: Bool) throws {
        SwiftLintInProcessActor.prepare()
        let container = try makeFolder(privateRoot: privateRoot)
        defer { try? FileManager.default.removeItem(at: container) }
        let workspace = container.appendingPathComponent("Workspace", isDirectory: true)
        try write(rootConfig(excludes: excludes), to: ".swiftlint.yml", in: workspace)
        try write(Self.source, to: "Root.swift", in: workspace)
        try write(Self.source, to: "Plain/Deep/Plain.swift", in: workspace)
        try write("disabled_rules:\n  - empty_count\n", to: "Nested/.swiftlint.yml", in: workspace)
        try write(Self.source, to: "Nested/Nested.swift", in: workspace)
        try write(Self.source, to: "Nested/Beneath/Beneath.swift", in: workspace)
        try write("opt_in_rules:\n  - force_unwrapping\n", to: "Nested/Inner/.swiftlint.yml", in: workspace)
        try write(Self.source, to: "Nested/Inner/Inner.swift", in: workspace)
        try write("", to: "Blank/.swiftlint.yml", in: workspace)
        try write(Self.source, to: "Blank/Blank.swift", in: workspace)
        // Folders outside the workspace that links in it point to, one with a config of its own.
        // SwiftLint's file walk follows the links only when the config excludes something.
        try write(Self.source, to: "Outside/Outside.swift", in: container)
        try write("disabled_rules:\n  - empty_count\n", to: "OutsideConfigured/.swiftlint.yml", in: container)
        try write(Self.source, to: "OutsideConfigured/Configured.swift", in: container)
        for folder in ["Outside", "OutsideConfigured"] {
            try FileManager.default.createSymbolicLink(
                atPath: workspace.appendingPathComponent(folder).path,
                withDestinationPath: container.appendingPathComponent(folder).path
            )
        }

        try CurrentWorkingDirectory.$url.withValue(workspace) {
            let root = try InProcessConfiguration.root(configPath: nil, workspacePath: workspace)
            let files = root.lintableFiles(inPath: workspace, forceExclude: false, excludeByPrefix: false)
            #expect(files.count == (excludes ? 8 : 6))
            var lookup = NestedConfigLookup(root: root)
            var answeredHere: [String] = []
            for file in files {
                let path = try #require(file.path)
                #expect(lookup.configuration(for: file) == root.configuration(for: file), "\(path.path)")
                if !lookup.asksSwiftLint(about: file) {
                    answeredHere.append(path.lastPathComponent)
                }
            }
            // Files beneath no nested config are answered here where the spellings agree; the
            // file outside, whose search runs to `/`, wherever the walk reaches it.
            let expected: [String] = switch (privateRoot, excludes) {
            case (false, false): ["Plain.swift", "Root.swift"]
            case (false, true): ["Outside.swift"]
            case (true, false): []
            case (true, true): ["Outside.swift", "Plain.swift", "Root.swift"]
            }
            #expect(answeredHere.sorted() == expected)
        }
    }

    /// Only where the root is spelled as SwiftLint's walk spells the files: `/tmp/…` with an empty
    /// `excluded` list, `/private/tmp/…` with a listed one. Otherwise every file's search passes
    /// the root's folder and meets the workspace's `.swiftlint.yml`, so SwiftLint is asked and
    /// caches as before; `agreesWithSwiftLint` pins that. The app never audits there: the
    /// sandboxed edition refuses to mirror a workspace under `/private`.
    @Test(
        "A lint of a workspace without nested configs leaves nothing in SwiftLint's cache",
        arguments: zip([false, true], [false, true])
    )
    func leavesNothingCached(privateRoot: Bool, excludes: Bool) throws {
        let workspace = try makeFolder(privateRoot: privateRoot)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try write(rootConfig(excludes: excludes), to: ".swiftlint.yml", in: workspace)
        try write(Self.source, to: "Root.swift", in: workspace)
        try write(Self.source, to: "Sources/Module/Deep/File.swift", in: workspace)

        let data = try SwiftLintInProcessActor.lint(configPath: nil, workspacePath: workspace)
        let violations = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(violations.count { $0["rule_id"] as? String == "empty_count" } == 2)

        try CurrentWorkingDirectory.$url.withValue(workspace) {
            let root = try InProcessConfiguration.root(configPath: nil, workspacePath: workspace)
            let files = root.lintableFiles(inPath: workspace, forceExclude: false, excludeByPrefix: false)
            // SwiftLint's keys: the root's folder, then each folder its search would pass, as the
            // file's path spells it.
            func key(_ folder: URL) -> String {
                "nestedPath" + root.rootDirectory.path
                    + folder.appending(path: Configuration.defaultFileName, directoryHint: .notDirectory).path
            }
            var folders: Set<URL> = []
            for file in files {
                var folder = try #require(file.path).deletingLastPathComponent()
                while folders.insert(folder).inserted, folder.path != "/" {
                    folder = folder.deletingLastPathComponent()
                }
            }
            #expect(folders.count > 3)
            for folder in folders {
                #expect(!Configuration.getIsNestedConfigurationSelf(forIdentifier: key(folder)), "\(folder.path)")
                #expect(Configuration.getCached(forIdentifier: key(folder)) == nil, "\(folder.path)")
            }
            // The keys are SwiftLint's: asking it about a file caches its answer under one.
            let file = try #require(files.first { $0.path?.lastPathComponent == "File.swift" })
            _ = root.configuration(for: file)
            let folder = try #require(file.path).deletingLastPathComponent()
            #expect(Configuration.getIsNestedConfigurationSelf(forIdentifier: key(folder)))
        }
    }
}
