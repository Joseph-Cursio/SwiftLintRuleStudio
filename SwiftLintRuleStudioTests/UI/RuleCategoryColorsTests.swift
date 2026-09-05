@testable import SwiftLintRuleStudio
import SwiftLintRuleStudioCore
import SwiftUI
import Testing

/// One colour per rule category, and one mapping that decides it.
///
/// There were two. `RuleCategoryColors` — used by the rule list and the rule detail header — gives
/// `style` blue, `lint` red, `metrics` purple, `performance` orange, `idiomatic` green.
/// `RuleAuditRow` carried a private switch giving purple, blue, green, orange, teal. **Four of the
/// five disagreed**, so the same rule wore a different badge colour depending on which screen you
/// were on. Neither mapping had a test.
///
/// The row now asks the shared mapping. These laws are about the mapping itself, because a second
/// opinion is only findable if there is a first one worth stating.
@Suite("Rule category colours") @MainActor
struct RuleCategoryColorsTests {
    @Test("every category has a colour")
    func everyCategoryHasAColour() {
        // Vacuous while the switch is exhaustive, and here for the case that is not today's: a
        // sixth category added with a `default:` arm. `RuleCategory` is already `CaseIterable`, so
        // iterating it costs nothing.
        for category in RuleCategory.allCases {
            _ = RuleCategoryColors.color(for: category)
        }
        #expect(RuleCategory.allCases.count == 5)
    }

    @Test("no two categories share a colour")
    func coloursAreDistinct() {
        // The badge is read at a glance and its only signal is hue. Two categories drawn alike are
        // indistinguishable, and with five arms a copy-paste is easy — this is the law that was
        // missing when a second mapping drifted from the first.
        let colours = RuleCategory.allCases.map { RuleCategoryColors.color(for: $0) }
        #expect(Set(colours).count == colours.count, "duplicate colour among \(colours)")
    }

    @Test("an audit entry reports the same category as its rule")
    func entryForwardsItsRulesCategory() {
        // `RuleAuditRow` now asks the entry rather than reaching `entry.rule.category`. The
        // forwarding has to be exactly that and nothing else.
        for category in RuleCategory.allCases {
            let rule = Rule(
                id: "test_rule", name: "Test", description: "d",
                category: category, isOptIn: false, isEnabled: false
            )
            let entry = RuleAuditEntry(rule: rule, impactResult: nil, isCurrentlyEnabled: false)
            #expect(entry.category == category)
        }
    }
}
