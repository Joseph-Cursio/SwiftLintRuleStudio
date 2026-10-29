//
//  ResolvedConfigurationEngineTests+NearestConfig.swift
//  SwiftLintRuleStudioCoreTests
//
//  Which configs apply to a folder. SwiftLint walks up from a file's folder and merges the root
//  config with the first nested `.swiftlint.yml` it meets, and with no other: a config in a
//  folder between them is passed over.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

extension ResolvedConfigurationEngineTests {
    /// SwiftLint merges the root config with the nearest nested config, and passes over the
    /// configs in the folders between: `Sub`'s `disabled_rules` doesn't reach `Sub/Deeper`.
    private func makeThreeLevelWorkspace() throws -> URL {
        let root = try makeWorkspace()
        try writeConfig("opt_in_rules:\n  - empty_count\n", at: "", in: root)
        try writeConfig("disabled_rules:\n  - empty_count\n", at: "Sub", in: root)
        try writeConfig("disabled_rules:\n  - force_cast\n", at: "Sub/Deeper", in: root)
        return root
    }

    @Test("a folder takes the root and its nearest nested config, not the configs between")
    @MainActor
    func testNearestNestedConfigAlone() throws {
        let root = try makeThreeLevelWorkspace()
        defer { cleanup(root) }

        let atDeeper = resolve(at: "Sub/Deeper", in: root)
        #expect(atDeeper.layerChain.map(\.displayName) == ["root", "Deeper"])
        #expect(atDeeper.skippedLayers.map(\.displayName) == ["Sub"])
        #expect(atDeeper.optInRules.map(\.identifier) == ["empty_count"])
        #expect(atDeeper.optInRules.first?.setBy.isRoot == true)
        #expect(atDeeper.disabledRules.map(\.identifier) == ["force_cast"])

        let atSub = resolve(at: "Sub", in: root)
        #expect(atSub.layerChain.map(\.displayName) == ["root", "Sub"])
        #expect(atSub.skippedLayers.isEmpty)
        #expect(atSub.disabledRules.map(\.identifier) == ["empty_count"])
        #expect(atSub.optInRules.isEmpty)
    }

    @Test("a folder with no config takes the nearest nested config above it")
    @MainActor
    func testConfiglessFolderTakesNearestNestedConfig() throws {
        let root = try makeThreeLevelWorkspace()
        defer { cleanup(root) }

        let resolved = resolve(at: "Sub/Deeper/Plain", in: root)
        #expect(resolved.layerChain.map(\.displayName) == ["root", "Deeper"])
        #expect(resolved.skippedLayers.map(\.displayName) == ["Sub"])
        #expect(resolved.optInRules.map(\.identifier) == ["empty_count"])
    }

    @Test("with no root config the nearest nested config applies alone")
    @MainActor
    func testNearestNestedConfigWithoutRoot() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("opt_in_rules:\n  - empty_count\n", at: "Sub", in: root)
        try writeConfig("disabled_rules:\n  - force_cast\n", at: "Sub/Deeper", in: root)

        let resolved = resolve(at: "Sub/Deeper", in: root)
        #expect(resolved.layerChain.map(\.displayName) == ["Deeper"])
        #expect(resolved.skippedLayers.map(\.displayName) == ["Sub"])
        #expect(resolved.optInRules.isEmpty)
        #expect(resolved.disabledRules.map(\.identifier) == ["force_cast"])
    }

    @Test("a nearest config that fails to parse still passes over the configs above it")
    @MainActor
    func testUnparseableNearestConfigStillStandsIn() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("opt_in_rules:\n  - empty_count\n", at: "", in: root)
        try writeConfig("disabled_rules:\n  - empty_count\n", at: "Sub", in: root)
        try writeConfig("key: [unterminated\n  another: ]\n", at: "Sub/Deeper", in: root)
        let tree = ConfigTreeDiscovery().discover(in: root)
        let deeper = try #require(tree.configs.first { $0.relativePath == "Sub/Deeper/.swiftlint.yml" })
        #expect(deeper.parseError != nil)

        let resolved = ResolvedConfigurationEngine().resolve(
            at: root.appendingPathComponent("Sub/Deeper", isDirectory: true),
            in: tree
        )
        #expect(resolved.layerChain.map(\.displayName) == ["root", "Deeper"])
        #expect(resolved.skippedLayers.map(\.displayName) == ["Sub"])
        #expect(resolved.optInRules.map(\.identifier) == ["empty_count"])
        #expect(resolved.disabledRules.isEmpty)
    }

    // MARK: - The configs the root pulls in

    @Test("a config the root pulls in with child_config stays part of the root's settings")
    @MainActor
    func testRootChildConfigIsPartOfTheRoot() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("opt_in_rules:\n  - empty_count\nchild_config: Sub/.swiftlint.yml\n", at: "", in: root)
        try writeConfig("disabled_rules:\n  - force_cast\n", at: "Sub", in: root)
        try writeConfig("disabled_rules:\n  - todo\n", at: "Sub/Deeper", in: root)

        // SwiftLint passes over Sub's config as a nested one, but has merged it
        // into the root: beneath Sub/Deeper's own config it still applies…
        let atDeeper = resolve(at: "Sub/Deeper", in: root)
        #expect(atDeeper.layerChain.map(\.displayName) == ["root", "Sub", "Deeper"])
        #expect(atDeeper.skippedLayers.isEmpty)
        #expect(atDeeper.disabledRules.map(\.identifier) == ["force_cast", "todo"])

        // …and in a folder nowhere near Sub.
        let atOther = resolve(at: "Other", in: root)
        #expect(atOther.layerChain.map(\.displayName) == ["root", "Sub"])
        #expect(atOther.disabledRules.map(\.identifier) == ["force_cast"])
        #expect(atOther.optInRules.map(\.identifier) == ["empty_count"])
    }

    @Test("a config the root pulls in with parent_config merges beneath the root's own settings")
    @MainActor
    func testRootParentConfigMergesFirst() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("parent_config: Shared/.swiftlint.yml\nopt_in_rules:\n  - empty_count\n", at: "", in: root)
        try writeConfig("disabled_rules:\n  - empty_count\n  - todo\n", at: "Shared", in: root)

        let resolved = resolve(at: "Sources", in: root)
        #expect(resolved.layerChain.map(\.displayName) == ["Shared", "root"])
        // The root is the child here: its opt-in overrides the parent's disable.
        #expect(resolved.optInRules.map(\.identifier) == ["empty_count"])
        #expect(resolved.optInRules.first?.setBy.isRoot == true)
        #expect(resolved.disabledRules.map(\.identifier) == ["todo"])
    }
}
