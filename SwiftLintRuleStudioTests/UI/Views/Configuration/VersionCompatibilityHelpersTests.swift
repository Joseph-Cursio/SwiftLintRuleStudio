//
//  VersionCompatibilityHelpersTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the four issue sections of the version compatibility report —
//  removed, deprecated, renamed and newly available rules — plus the shared
//  section chrome they are built from.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

private struct HelpersStubChecker: VersionCompatibilityCheckerProtocol {
    func checkCompatibility(
        config _: YAMLConfigurationEngine.YAMLConfig,
        swiftLintVersion: String
    ) -> CompatibilityReport {
        CompatibilityReport(
            swiftLintVersion: swiftLintVersion,
            deprecatedRules: [],
            removedRules: [],
            renamedRules: [],
            availableNewRules: []
        )
    }
}

private struct HelpersStubCLI: SwiftLintCLIProtocol {
    func detectSwiftLintPath() throws -> URL { throw SwiftLintError.notFound }
    func executeRulesCommand() throws -> Data { Data() }
    func executeRuleDetailCommand(ruleId _: String) throws -> Data { Data() }
    func generateDocsForRule(ruleId _: String) throws -> String { "" }
    func executeLintCommand(configPath _: URL?, workspacePath _: URL) throws -> Data { Data() }
    func getVersion() throws -> String { "0.0.0" }
}

@MainActor
@Suite("Version compatibility sections")
struct VersionCompatibilityHelpersTests {

    // MARK: - Fixtures

    private static func makeView() -> VersionCompatibilityView {
        VersionCompatibilityView(
            checker: HelpersStubChecker(),
            swiftLintCLI: HelpersStubCLI(),
            configPath: nil
        )
    }

    private static func makeRemoved(
        _ ruleId: String,
        removedIn: String = "0.50.0",
        message: String = "This rule was removed"
    ) -> RemovedRuleInfo {
        RemovedRuleInfo(
            id: ruleId,
            ruleId: ruleId,
            removedInVersion: removedIn,
            replacement: nil,
            message: message
        )
    }

    private static func makeDeprecated(
        _ ruleId: String,
        replacement: String?,
        message: String = "This rule is deprecated"
    ) -> DeprecatedRuleInfo {
        DeprecatedRuleInfo(
            id: ruleId,
            ruleId: ruleId,
            deprecatedInVersion: "0.49.0",
            replacement: replacement,
            message: message
        )
    }

    private static func makeRenamed(_ oldId: String, _ newId: String) -> RenamedRuleInfo {
        RenamedRuleInfo(id: oldId, oldRuleId: oldId, newRuleId: newId)
    }

    private static func contains(_ view: some View, text: String) -> Bool {
        (try? view.inspect().find(text: text)) != nil
    }

    // MARK: - Removed rules

    @Test("The removed section explains what the user must do")
    func removedSectionHasHeading() {
        let section = Self.makeView().removedRulesSection([Self.makeRemoved("ignore_me")])

        #expect(Self.contains(section, text: "Removed Rules"))
        #expect(Self.contains(section, text: "These rules no longer exist and must be removed"))
    }

    @Test("Each removed rule shows its id, message and removal version")
    func removedSectionListsRules() {
        let section = Self.makeView().removedRulesSection([
            Self.makeRemoved("attributes", removedIn: "0.50.0", message: "Gone for good")
        ])

        #expect(Self.contains(section, text: "attributes"))
        #expect(Self.contains(section, text: "Gone for good"))
        #expect(Self.contains(section, text: "Removed in 0.50.0"))
    }

    @Test("Every removed rule is listed, not just the first")
    func removedSectionListsEveryRule() {
        let section = Self.makeView().removedRulesSection([
            Self.makeRemoved("first_rule"),
            Self.makeRemoved("second_rule"),
            Self.makeRemoved("third_rule")
        ])

        #expect(Self.contains(section, text: "first_rule"))
        #expect(Self.contains(section, text: "second_rule"))
        #expect(Self.contains(section, text: "third_rule"))
    }

    @Test("Rules removed in different versions each report their own")
    func removedSectionReportsPerRuleVersions() {
        let section = Self.makeView().removedRulesSection([
            Self.makeRemoved("early_rule", removedIn: "0.40.0"),
            Self.makeRemoved("late_rule", removedIn: "0.55.0")
        ])

        #expect(Self.contains(section, text: "Removed in 0.40.0"))
        #expect(Self.contains(section, text: "Removed in 0.55.0"))
    }

    // MARK: - Deprecated rules

    @Test("The deprecated section says the rules still work")
    func deprecatedSectionHasHeading() {
        let section = Self.makeView().deprecatedRulesSection([
            Self.makeDeprecated("old_rule", replacement: nil)
        ])

        #expect(Self.contains(section, text: "Deprecated Rules"))
        #expect(Self.contains(section, text: "These rules still work but should be migrated"))
    }

    @Test("A deprecated rule with a replacement points at it")
    func deprecatedSectionShowsReplacement() {
        let section = Self.makeView().deprecatedRulesSection([
            Self.makeDeprecated("old_rule", replacement: "new_rule")
        ])

        #expect(Self.contains(section, text: "old_rule"))
        #expect(Self.contains(section, text: "Use: new_rule"))
    }

    @Test("A deprecated rule with no replacement suggests nothing")
    func deprecatedSectionOmitsMissingReplacement() {
        // The rule is deprecated with nothing to migrate to, so the row must
        // not render a dangling "Use:" label.
        let section = Self.makeView().deprecatedRulesSection([
            Self.makeDeprecated("orphan_rule", replacement: nil)
        ])

        #expect(Self.contains(section, text: "orphan_rule"))
        #expect(!Self.contains(section, text: "Use: "))
    }

    @Test("Replacements are shown per rule, not shared")
    func deprecatedSectionShowsPerRuleReplacements() {
        let section = Self.makeView().deprecatedRulesSection([
            Self.makeDeprecated("has_replacement", replacement: "the_new_one"),
            Self.makeDeprecated("no_replacement", replacement: nil)
        ])

        #expect(Self.contains(section, text: "Use: the_new_one"))
        #expect(Self.contains(section, text: "no_replacement"))
    }

    // MARK: - Renamed rules

    @Test("The renamed section shows both the old and new names")
    func renamedSectionShowsBothNames() {
        let section = Self.makeView().renamedRulesSection([
            Self.makeRenamed("old_name", "new_name")
        ])

        #expect(Self.contains(section, text: "Renamed Rules"))
        #expect(Self.contains(section, text: "old_name"))
        #expect(Self.contains(section, text: "new_name"))
    }

    @Test("Each renamed rule offers its own Fix, plus one Fix All")
    func renamedSectionOffersFixes() throws {
        let renames = [
            Self.makeRenamed("one_old", "one_new"),
            Self.makeRenamed("two_old", "two_new")
        ]
        let section = Self.makeView().renamedRulesSection(renames)

        let buttons = try section.inspect().findAll(ViewType.Button.self)

        #expect(buttons.count == renames.count + 1, "one Fix per rule, plus Fix All Renames")
        #expect(Self.contains(section, text: "Fix All Renames"))
    }

    @Test("Fix All is offered even for a single rename")
    func renamedSectionOffersFixAllForOneRule() {
        let section = Self.makeView().renamedRulesSection([Self.makeRenamed("solo_old", "solo_new")])

        #expect(Self.contains(section, text: "Fix All Renames"))
    }

    // MARK: - Newly available rules

    @Test("The new rules section invites the user to enable them")
    func newRulesSectionHasHeading() {
        let section = Self.makeView().newRulesAvailableSection(["some_rule"])

        #expect(Self.contains(section, text: "New Rules Available"))
        #expect(
            Self.contains(
                section,
                text: "Rules added in recent SwiftLint versions that you could enable"
            )
        )
    }

    @Test("Every newly available rule is listed")
    func newRulesSectionListsEveryRule() {
        let ruleIds = ["alpha_rule", "beta_rule", "gamma_rule", "delta_rule"]
        let section = Self.makeView().newRulesAvailableSection(ruleIds)

        for ruleId in ruleIds {
            #expect(Self.contains(section, text: ruleId), "\(ruleId) is missing")
        }
    }

    // MARK: - Shared section chrome

    @Test("A section renders its title, subtitle and content")
    func issueSectionRendersChromeAndContent() {
        let section = Self.makeView().issueSection(
            title: "A Title",
            subtitle: "A subtitle",
            color: .red,
            icon: "xmark.circle.fill"
        ) {
            Text("The content")
        }

        #expect(Self.contains(section, text: "A Title"))
        #expect(Self.contains(section, text: "A subtitle"))
        #expect(Self.contains(section, text: "The content"))
    }

    @Test("The section icon is hidden from assistive technologies")
    func issueSectionHidesItsIcon() throws {
        // The title already names the section, so the icon would be a second,
        // redundant VoiceOver stop.
        let section = Self.makeView().issueSection(
            title: "A Title",
            subtitle: "A subtitle",
            color: .orange,
            icon: "exclamationmark.triangle.fill"
        ) {
            EmptyView()
        }

        let images = try section.inspect().findAll(ViewType.Image.self)

        #expect(!images.isEmpty)
        for image in images {
            #expect(try image.accessibilityHidden())
        }
    }

    @Test("A section with no content still renders its heading")
    func issueSectionRendersWithEmptyContent() {
        let section = Self.makeView().removedRulesSection([])

        #expect(Self.contains(section, text: "Removed Rules"))
    }
}
