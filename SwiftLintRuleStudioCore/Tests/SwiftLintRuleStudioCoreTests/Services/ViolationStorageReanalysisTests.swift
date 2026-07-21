//
//  ViolationStorageReanalysisTests.swift
//  SwiftLintRuleStudioTests
//
//  Regression tests for P0.1: suppression/resolution must survive a re-analysis
//  that re-reports the same finding.
//
//  Background: each `storeViolations` call replaces the workspace's rows, and the
//  analyzer constructs a fresh `Violation` (new random `id`, `suppressed:false`,
//  `resolvedAt:nil`) for every finding on every run. If identity is not derived
//  from content, a re-analysis orphans the prior suppression/resolution — the
//  state is silently lost. These tests pin the *behavior* (state survives a
//  re-store of the same finding) rather than the identity mechanism, so they hold
//  regardless of how the fix implements stable identity.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ViolationStorageReanalysisTests {
    /// A finding as a fresh analysis would report it: same content, but a brand-new
    /// `id` and cleared suppression/resolution state — exactly what the analyzer emits.
    private static func reportedFinding(
        ruleID: String = "test_rule",
        filePath: String = "Test.swift",
        line: Int = 10,
        message: String = "Test violation"
    ) -> Violation {
        Violation(
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            severity: .error,
            message: message,
            column: 5,
            detectedAt: Date.now
        )
    }

    @Test("Suppression survives a re-analysis that re-reports the same finding")
    func suppressionSurvivesReanalysis() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        // Initial analysis reports one finding; the user suppresses it.
        let original = Self.reportedFinding()
        try await storage.storeViolations([original], for: workspaceId)
        try await storage.suppressViolations([original.id], reason: "Not applicable")

        // Re-analysis re-reports the *same finding* (new id, suppressed:false).
        try await storage.storeViolations([Self.reportedFinding()], for: workspaceId)

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1)
        let violation = try #require(fetched.first)
        #expect(violation.suppressed, "re-analysis must not clear an existing suppression")
        #expect(violation.suppressionReason == "Not applicable")
    }

    @Test("Resolution survives a re-analysis that re-reports the same finding")
    func resolutionSurvivesReanalysis() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let original = Self.reportedFinding()
        try await storage.storeViolations([original], for: workspaceId)
        try await storage.resolveViolations([original.id])

        try await storage.storeViolations([Self.reportedFinding()], for: workspaceId)

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1)
        let violation = try #require(fetched.first)
        #expect(violation.resolvedAt != nil, "re-analysis must not clear an existing resolution")
    }

    @Test("Plain re-analysis with no edits preserves suppression across every finding")
    func plainReanalysisPreservesState() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let alpha = Self.reportedFinding(ruleID: "rule_alpha", filePath: "Alpha.swift")
        let beta = Self.reportedFinding(ruleID: "rule_beta", filePath: "Beta.swift")
        try await storage.storeViolations([alpha, beta], for: workspaceId)
        try await storage.suppressViolations([alpha.id], reason: "false positive")
        try await storage.resolveViolations([beta.id])

        // The user clicks "Analyze" again; nothing in the code changed.
        try await storage.storeViolations(
            [
                Self.reportedFinding(ruleID: "rule_alpha", filePath: "Alpha.swift"),
                Self.reportedFinding(ruleID: "rule_beta", filePath: "Beta.swift")
            ],
            for: workspaceId
        )

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 2)
        let alphaAfter = try #require(fetched.first { $0.ruleID == "rule_alpha" })
        let betaAfter = try #require(fetched.first { $0.ruleID == "rule_beta" })
        #expect(alphaAfter.suppressed, "suppression must survive a no-op re-analysis")
        #expect(alphaAfter.suppressionReason == "false positive")
        #expect(betaAfter.resolvedAt != nil, "resolution must survive a no-op re-analysis")
    }

    @Test("A finding no longer reported by re-analysis is removed")
    func staleFindingIsRemovedAfterReanalysis() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let fixed = Self.reportedFinding(ruleID: "rule_fixed", filePath: "Fixed.swift")
        let remaining = Self.reportedFinding(ruleID: "rule_remaining", filePath: "Remaining.swift")
        try await storage.storeViolations([fixed, remaining], for: workspaceId)
        try await storage.suppressViolations([fixed.id], reason: "will be fixed")

        // The user fixes `Fixed.swift`; re-analysis reports only the remaining finding.
        try await storage.storeViolations(
            [Self.reportedFinding(ruleID: "rule_remaining", filePath: "Remaining.swift")],
            for: workspaceId
        )

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1, "a finding the analyzer no longer reports must not linger")
        #expect(fetched.first?.ruleID == "rule_remaining")
    }

    @Test("A newly-reported finding after re-analysis is not suppressed")
    func newFindingIsNotInadvertentlySuppressed() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let existing = Self.reportedFinding(ruleID: "rule_existing", filePath: "Existing.swift")
        try await storage.storeViolations([existing], for: workspaceId)
        try await storage.suppressViolations([existing.id], reason: "known")

        // Re-analysis re-reports the existing (suppressed) finding plus a brand-new one.
        try await storage.storeViolations(
            [
                Self.reportedFinding(ruleID: "rule_existing", filePath: "Existing.swift"),
                Self.reportedFinding(ruleID: "rule_new", filePath: "New.swift")
            ],
            for: workspaceId
        )

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 2)
        let existingAfter = try #require(fetched.first { $0.ruleID == "rule_existing" })
        let newAfter = try #require(fetched.first { $0.ruleID == "rule_new" })
        #expect(existingAfter.suppressed, "the previously-suppressed finding stays suppressed")
        #expect(!newAfter.suppressed, "a brand-new finding must not inherit suppression")
        #expect(newAfter.resolvedAt == nil, "a brand-new finding must not inherit resolution")
    }
}
