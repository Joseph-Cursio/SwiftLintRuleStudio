//
//  ResolvedConfigurationEngineTests+ReferencedConfigs.swift
//  SwiftLintRuleStudioCoreTests
//
//  The configs the root pulls in from outside the workspace's own `.swiftlint.yml` files — a
//  package's `parent_config: ../../.swiftlint.yml`, a remote config — are part of the root
//  configuration in every folder, as those it pulls in from the workspace are.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

extension ResolvedConfigurationEngineTests {
    /// A repository whose config opts in `empty_count` and disables `todo`, with a package
    /// opened on its own at `Packages/Foo` that inherits it.
    private func makePackageWorkspace() throws -> (repository: URL, workspace: URL) {
        let repository = try makeWorkspace()
        try writeConfig("opt_in_rules:\n  - empty_count\ndisabled_rules:\n  - todo\n", at: "", in: repository)
        try writeConfig(
            "parent_config: ../../.swiftlint.yml\ndisabled_rules:\n  - force_cast\n",
            at: "Packages/Foo",
            in: repository
        )
        try writeConfig("disabled_rules:\n  - empty_count\n", at: "Packages/Foo/Sub", in: repository)
        return (repository, repository.appendingPathComponent("Packages/Foo", isDirectory: true))
    }

    @Test("a package's parent_config outside the workspace applies in every folder, attributed to it")
    @MainActor
    func testParentConfigOutsideTheWorkspace() throws {
        let (repository, workspace) = try makePackageWorkspace()
        defer { cleanup(repository) }

        let atSources = resolve(at: "Sources", in: workspace)
        #expect(atSources.layerChain.map(\.displayName) == ["../../.swiftlint.yml", "root"])
        #expect(atSources.optInRules.map(\.identifier) == ["empty_count"])
        #expect(atSources.optInRules.first?.setBy.displayName == "../../.swiftlint.yml")
        #expect(atSources.disabledRules.map(\.identifier) == ["force_cast", "todo"])
        #expect(atSources.disablingLayer(for: "todo")?.relativePath == "../../.swiftlint.yml")
        #expect(atSources.disablingLayer(for: "force_cast")?.isRoot == true)

        // A nested config merges onto the whole root configuration, the repository's part
        // included, and is never passed over for it.
        let atSub = resolve(at: "Sub", in: workspace)
        #expect(atSub.layerChain.map(\.displayName) == ["../../.swiftlint.yml", "root", "Sub"])
        #expect(atSub.skippedLayers.isEmpty)
        #expect(atSub.optInRules.isEmpty)
        #expect(atSub.disabledRules.map(\.identifier) == ["empty_count", "force_cast", "todo"])
    }

    @Test("a remote config applies as SwiftLint last fetched it; one it hasn't fetched contributes nothing")
    @MainActor
    func testRemoteConfigs() throws {
        let workspace = try makeWorkspace()
        defer { cleanup(workspace) }
        try writeConfig(
            "parent_config: https://example.com/base.yml\nchild_config: https://example.com/strict.yml\n",
            at: "",
            in: workspace
        )
        let cached = ConfigTreeDiscovery.remoteConfigCacheURL(for: "https://example.com/base.yml", in: workspace)
        try FileManager.default.createDirectory(
            at: cached.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "disabled_rules:\n  - todo\n".write(to: cached, atomically: true, encoding: .utf8)

        let resolved = resolve(at: "", in: workspace)
        #expect(resolved.layerChain.map(\.displayName) == [
            "https://example.com/base.yml",
            "root",
            "https://example.com/strict.yml"
        ])
        #expect(resolved.disabledRules.map(\.identifier) == ["todo"])
        #expect(resolved.disablingLayer(for: "todo")?.displayName == "https://example.com/base.yml")
    }

    // MARK: - excluded, included and reporter

    @Test("excluded and included merge across the root configuration, each read from its own config's folder")
    @MainActor
    func testRootConfigurationPathsMerge() throws {
        let repository = try makeWorkspace()
        defer { cleanup(repository) }
        try writeConfig(
            "excluded:\n  - Pods\n  - Packages/Foo/Generated\nincluded:\n  - Packages\n",
            at: "",
            in: repository
        )
        try writeConfig(
            "parent_config: ../../.swiftlint.yml\n"
                + "included:\n  - Generated\n  - Sources\nexcluded:\n  - Sources/Legacy\n",
            at: "Packages/Foo",
            in: repository
        )
        try writeConfig("excluded:\n  - Ignored\n", at: "Packages/Foo/Sub", in: repository)
        let workspace = repository.appendingPathComponent("Packages/Foo", isDirectory: true)

        let resolved = resolve(at: "Sub", in: workspace)
        // The repository's `Packages/Foo/Generated` is the package's `Generated`, which the
        // package's config includes: it drops out. A nested config's `excluded` is ignored.
        #expect(resolved.excluded.map(\.value) == ["../../Pods", "Sources/Legacy"])
        #expect(resolved.excluded.map(\.setBy.displayName) == ["../../.swiftlint.yml", "root"])
        #expect(resolved.included.map(\.value) == ["..", "Generated", "Sources"])
        #expect(resolved.included.map(\.setBy.displayName) == ["../../.swiftlint.yml", "root", "root"])
    }

    @Test("a remote config's excluded is read from the folder of the config that pulled it in")
    @MainActor
    func testRemoteConfigPaths() throws {
        let repository = try makeWorkspace()
        defer { cleanup(repository) }
        try writeConfig("parent_config: https://example.com/base.yml\n", at: "Packages/Foo", in: repository)
        let workspace = repository.appendingPathComponent("Packages/Foo", isDirectory: true)
        let cached = ConfigTreeDiscovery.remoteConfigCacheURL(for: "https://example.com/base.yml", in: workspace)
        try FileManager.default.createDirectory(
            at: cached.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "excluded:\n  - Generated\n".write(to: cached, atomically: true, encoding: .utf8)

        let resolved = resolve(at: "", in: workspace)
        #expect(resolved.excluded.map(\.value) == ["Generated"])
        #expect(resolved.excluded.first?.setBy.displayName == "https://example.com/base.yml")
    }

    @Test("the reporter is the first config's of the root configuration, not the root config's")
    @MainActor
    func testReporterComesFromTheFurthestParent() throws {
        let (repository, workspace) = try makePackageWorkspace()
        defer { cleanup(repository) }
        try writeConfig(
            "parent_config: ../../.swiftlint.yml\nreporter: json\n",
            at: "Packages/Foo",
            in: repository
        )

        // The repository's config names no reporter: SwiftLint uses its default.
        #expect(resolve(at: "", in: workspace).reporter == nil)

        try writeConfig("reporter: emoji\n", at: "", in: repository)
        let reporter = try #require(resolve(at: "", in: workspace).reporter)
        #expect(reporter.value == "emoji")
        #expect(reporter.setBy.displayName == "../../.swiftlint.yml")
    }
}
