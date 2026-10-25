//
//  SwiftLintDeprecationsTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  How the deprecation tables relate to one another. The compatibility checker
//  reads renames from `renamedRules` alone; the migration assistant falls back to
//  a deprecation's replacement. If the two tables disagree, the report and the
//  migration offer different renames. Whether each row is true of SwiftLint is
//  checked against the linked SwiftLint in SwiftLintInProcessBackendTests.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct SwiftLintDeprecationsTests {

    @Test("every rename is dated by a deprecation that names the same replacement")
    func renamesAreDated() {
        for (oldId, newId) in SwiftLintDeprecations.renamedRules {
            let deprecation = SwiftLintDeprecations.deprecatedRules[oldId]
            #expect(deprecation?.replacement == newId, "\(oldId) is renamed to \(newId) but not deprecated for it")
        }
    }

    @Test("every deprecation with a replacement is a rename to it")
    func replacementsAreRenames() {
        for (ruleId, entry) in SwiftLintDeprecations.deprecatedRules {
            guard let replacement = entry.replacement else { continue }
            #expect(SwiftLintDeprecations.renamedRules[ruleId] == replacement)
        }
    }

    @Test("no rule is renamed to itself or to another renamed rule")
    func renamesAreDirect() {
        for (oldId, newId) in SwiftLintDeprecations.renamedRules {
            #expect(oldId != newId)
            #expect(SwiftLintDeprecations.renamedRules[newId] == nil, "\(oldId) → \(newId) needs a second rename")
        }
    }
}
