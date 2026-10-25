import Foundation
@testable import SwiftLintInProcessBackend
import SwiftLintRuleStudioCore
import Testing

// Core's `RulePresets` is hand-written and can't see SwiftLint; this package links the
// real thing. A preset filters the Rule Browser by identifier and its card counts its
// identifiers, so one SwiftLint doesn't have matches nothing and inflates the count.
// Core is built with `.defaultIsolation(MainActor.self)`, so the suite opts in.
@Suite("Rule presets against the linked SwiftLint")
@MainActor
struct RulePresetDataTests {

    @Test
    func presetsNameOnlyCurrentRules() {
        let liveRules = Set(
            // A key path to a static member through `any Rule.Type` crashes the Swift 6.4 compiler.
            // swiftlint:disable:next prefer_key_path
            SwiftLintInProcessActor.sortedBuiltInRules().map { $0.description.identifier }
        )
        for preset in RulePresets.allPresets {
            let unknown = preset.ruleIds.filter { !liveRules.contains($0) }
            #expect(unknown.isEmpty, "Preset '\(preset.id)' names rules SwiftLint doesn't have: \(unknown)")
        }
    }
}
