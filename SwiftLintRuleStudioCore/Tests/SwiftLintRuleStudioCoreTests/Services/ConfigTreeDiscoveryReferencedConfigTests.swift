//
//  ConfigTreeDiscoveryReferencedConfigTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The configs the root config pulls in that aren't among the workspace's own
//  `.swiftlint.yml` files: files outside the workspace or under another name, and
//  remote configs, read from the copy SwiftLint keeps in the workspace.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct ConfigTreeDiscoveryReferencedConfigTests {
    /// A repository holding `files`, keyed by their path in it, with the workspace
    /// opened at `Packages/Foo` — a package opened on its own.
    private static func repository(_ files: [String: String]) throws -> (repository: URL, workspace: URL) {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigTreeDiscoveryReferencedConfigTests-\(UUID().uuidString)", isDirectory: true)
        let workspace = repository.appendingPathComponent("Packages/Foo", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        for (relative, content) in files {
            let file = repository.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        return (repository, workspace)
    }

    /// Writes `content` where SwiftLint keeps its copy of the remote config at `reference`.
    private static func cacheRemoteConfig(_ content: String, for reference: String, in workspace: URL) throws {
        let cached = ConfigTreeDiscovery.remoteConfigCacheURL(for: reference, in: workspace)
        try FileManager.default.createDirectory(
            at: cached.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: cached, atomically: true, encoding: .utf8)
    }

    @Test("a package's parent_config outside the workspace is read, and its own parent_config after it")
    func readsConfigsOutsideTheWorkspace() throws {
        let (repository, workspace) = try Self.repository([
            "Packages/Foo/.swiftlint.yml": "parent_config: ../../.swiftlint.yml\n",
            ".swiftlint.yml": "parent_config: Shared/base.yml\ndisabled_rules: [todo]\n",
            "Shared/base.yml": "opt_in_rules: [empty_count]\n"
        ])
        defer { try? FileManager.default.removeItem(at: repository) }
        let tree = ConfigTreeDiscovery().discover(in: workspace)

        // The walk of the workspace finds its own config alone.
        #expect(tree.configs.map(\.relativePath) == [".swiftlint.yml"])
        #expect(tree.referencedConfigs.map(\.relativePath) == ["../../Shared/base.yml", "../../.swiftlint.yml"])
        #expect(tree.referencedConfigs.map(\.rootGraphPosition) == [-2, -1])
        #expect(tree.referencedConfigs.allSatisfy { $0.origin == .referencedFile && !$0.isRoot })
        #expect(tree.referencedConfigs.map(\.displayName) == ["../../Shared/base.yml", "../../.swiftlint.yml"])
        #expect(tree.referencedConfigs.last?.summary.disabledRuleCount == 1)
        #expect(tree.rootGraph.map(\.relativePath) == [
            "../../Shared/base.yml",
            "../../.swiftlint.yml",
            ".swiftlint.yml"
        ])
    }

    @Test("a file under another name in the workspace is read as a referenced config, and the chain goes on from it")
    func readsConfigsUnderAnotherName() throws {
        let (repository, workspace) = try Self.repository([
            "Packages/Foo/.swiftlint.yml": "child_config: Config/strict.yml\n",
            "Packages/Foo/Config/strict.yml": "child_config: ../Sub/.swiftlint.yml\nopt_in_rules: [empty_count]\n",
            "Packages/Foo/Sub/.swiftlint.yml": "disabled_rules: [todo]\n"
        ])
        defer { try? FileManager.default.removeItem(at: repository) }
        let tree = ConfigTreeDiscovery().discover(in: workspace)

        #expect(tree.referencedConfigs.map(\.relativePath) == ["Config/strict.yml"])
        #expect(tree.referencedConfigs.map(\.rootGraphPosition) == [1])
        let sub = try #require(tree.configs.first { $0.relativePath == "Sub/.swiftlint.yml" })
        #expect(sub.rootGraphPosition == 2)
        #expect(tree.rootGraph.map(\.relativePath) == [".swiftlint.yml", "Config/strict.yml", "Sub/.swiftlint.yml"])
    }

    @Test("a referenced file that doesn't exist ends the chain, as SwiftLint ignores it")
    func missingFileEndsTheChain() throws {
        let (repository, workspace) = try Self.repository([
            "Packages/Foo/.swiftlint.yml": "parent_config: ../../missing.yml\n"
        ])
        defer { try? FileManager.default.removeItem(at: repository) }
        let tree = ConfigTreeDiscovery().discover(in: workspace)

        #expect(tree.referencedConfigs.isEmpty)
        #expect(tree.rootGraph.map(\.relativePath) == [".swiftlint.yml"])
    }

    @Test("a remote config is read from SwiftLint's copy in the workspace, and the remote parent it names after it")
    func readsRemoteConfigsFromSwiftLintsCache() throws {
        let (repository, workspace) = try Self.repository([
            "Packages/Foo/.swiftlint.yml": "parent_config: https://example.com/base.yml\n"
        ])
        defer { try? FileManager.default.removeItem(at: repository) }
        try Self.cacheRemoteConfig(
            "disabled_rules: [todo]\nparent_config: https://example.com/org.yml\n",
            for: "https://example.com/base.yml",
            in: workspace
        )
        let tree = ConfigTreeDiscovery().discover(in: workspace)

        try #require(tree.referencedConfigs.count == 2)
        let org = tree.referencedConfigs[0]
        let base = tree.referencedConfigs[1]
        #expect(base.origin == .remote)
        #expect(base.configPath == URL(string: "https://example.com/base.yml"))
        #expect(base.displayName == "https://example.com/base.yml")
        #expect(base.rootGraphPosition == -1)
        #expect(base.summary.disabledRuleCount == 1)
        #expect(base.isAwaitingFetch == false)
        // SwiftLint reads a remote config's paths relative to the folder of the config
        // that pulled it in.
        #expect(base.directoryPath.standardizedFileURL == workspace.standardizedFileURL)
        // SwiftLint hasn't fetched the org config: there's nothing to read, and nothing
        // beyond it.
        #expect(org.rootGraphPosition == -2)
        #expect(org.isAwaitingFetch)
    }

    @Test("SwiftLint's copy of a remote config is named for its URL")
    func remoteConfigCacheName() {
        let workspace = URL(fileURLWithPath: "/Work/App", isDirectory: true)
        let cached = ConfigTreeDiscovery.remoteConfigCacheURL(for: "https://example.com/org/base.yml", in: workspace)
        #expect(cached.path == "/Work/App/.swiftlint/RemoteConfigCache/v1/https___example.com_org_base.yml.yml")
    }

    @Test("a local reference in a remote config is not followed: SwiftLint refuses it")
    func remoteConfigsLocalReferenceIsNotFollowed() throws {
        let (repository, workspace) = try Self.repository([
            "Packages/Foo/.swiftlint.yml": "parent_config: https://example.com/base.yml\n",
            ".swiftlint.yml": "disabled_rules: [todo]\n"
        ])
        defer { try? FileManager.default.removeItem(at: repository) }
        try Self.cacheRemoteConfig(
            "parent_config: ../../.swiftlint.yml\n",
            for: "https://example.com/base.yml",
            in: workspace
        )
        let tree = ConfigTreeDiscovery().discover(in: workspace)

        #expect(tree.referencedConfigs.map(\.relativePath) == ["https://example.com/base.yml"])
    }
}
