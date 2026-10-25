//
//  ConfigDiffSummaryViewTests.swift
//  SwiftLintRuleStudioTests
//
//  The Summary tab for a diff that carries a ConfigChangeSummary, and the preview's
//  configurable buttons.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct ConfigDiffSummaryViewTests {
    private func diff(
        _ changes: ConfigChangeSummary,
        before: String = "before",
        after: String = "after"
    ) -> YAMLConfigurationEngine.ConfigDiff {
        YAMLConfigurationEngine.ConfigDiff(
            addedRules: [],
            removedRules: [],
            modifiedRules: [],
            before: before,
            after: after,
            changes: changes
        )
    }

    private func texts(_ view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    private func summary(_ diff: YAMLConfigurationEngine.ConfigDiff) -> ConfigDiffSummaryView {
        ConfigDiffSummaryView(diff: diff, addedLabel: "Added", removedLabel: "Removed", modifiedLabel: "Modified")
    }

    @Test("Shows rules turned on and off, changed settings, paths and other changes")
    func showsEachKindOfChange() throws {
        let rendered = try texts(summary(diff(ConfigChangeSummary(
            turnedOn: ["empty_count"],
            turnedOff: ["todo"],
            settingsChanged: [.init(ruleId: "line_length", details: ["warning: 160 → 120"])],
            pathChanges: ["Now excluded: Pods"],
            otherChanges: ["reporter: xcode → json"]
        ))))

        for expected in [
            "Rules turned on", "empty_count",
            "Rules turned off", "todo",
            "Settings changed", "line_length", "warning: 160 → 120",
            "Paths", "Now excluded: Pods",
            "Other changes", "reporter: xcode → json"
        ] {
            #expect(rendered.contains(expected), "missing \(expected)")
        }
        #expect(!rendered.contains("No changes detected"))
    }

    @Test("Says SwiftLint checks the same things when only the text differs")
    func textDiffersOnly() throws {
        let rendered = try texts(summary(diff(ConfigChangeSummary(), before: "a:\n- b\n", after: "a:\n  - b\n")))

        #expect(rendered.contains("The text differs, but SwiftLint checks the same things."))
    }

    @Test("Says when two versions are identical")
    func identical() throws {
        let rendered = try texts(summary(diff(ConfigChangeSummary(), before: "same", after: "same")))

        #expect(rendered.contains("The two versions are identical."))
    }

    @Test("The inline preview's buttons take the labels it's given")
    func customButtonLabels() throws {
        let view = ConfigDiffPreviewView(
            diff: diff(ConfigChangeSummary(turnedOn: ["empty_count"])),
            ruleName: "Version Comparison",
            onSave: {},
            onCancel: {},
            isInline: true,
            saveLabel: "Restore Newer Version",
            cancelLabel: "Clear Comparison"
        )

        let rendered = try texts(view)
        #expect(rendered.contains("Restore Newer Version"))
        #expect(rendered.contains("Clear Comparison"))
        #expect(!rendered.contains("Save Changes"))
    }

    @Test("The import and migration previews count the change summary's changes")
    func ruleChangeSummaryCountsChanges() throws {
        let rendered = try texts(RuleChangeSummary(diff: diff(ConfigChangeSummary(
            turnedOn: ["empty_count", "array_init"],
            pathChanges: ["Now excluded: Pods"]
        ))))

        #expect(rendered.contains("2 rule(s) turned on"))
        #expect(rendered.contains("Paths changed"))
    }
}
