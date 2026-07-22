//
//  FilterViolationsPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `WorkspaceAnalyzer.filterViolations` — the filter the
//  `swift-infer` toolchain now proposes a `filter-subset` law for. A filter
//  returns only what it was given (subset), keeps exactly the elements whose
//  path is in the batch (membership), and settles after one pass (idempotence).
//  Generators use a small, overlapping filename alphabet so "in the batch" and
//  "not in the batch" nearly coincide — the counterexamples live in the collisions.
//

import Foundation
import LintStudioCore
import PropertyBased
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
@Suite("filterViolations property laws")
struct FilterViolationsPropertyLawTests {

    nonisolated static let workspace = URL(fileURLWithPath: "/ws")

    /// Violations over a four-name alphabet. `d.swift` is never in the batch, so
    /// every trial has misses as well as matches.
    private static func violationsGenerator() -> Generator<[Violation], some SendableSequenceType> {
        let names = ["a.swift", "b.swift", "c.swift", "d.swift"]
        let violation = Gen<Int>.int(in: 0 ... (names.count - 1)).map { index in
            Violation(ruleID: "rule", filePath: names[index], line: 1, severity: .warning, message: "m")
        }
        return violation.array(of: 0...6)
    }

    /// Batch paths over an overlapping-but-distinct alphabet: `other.swift` is
    /// never a violation path, `d.swift` is never batched — both matches and
    /// misses on every trial.
    private static func batchGenerator() -> Generator<[URL], some SendableSequenceType> {
        let names = ["a.swift", "b.swift", "c.swift", "other.swift"]
        return Gen<Int>.int(in: 0 ... (names.count - 1))
            .map { workspace.appendingPathComponent(names[$0]) }
            .array(of: 0...5)
    }

    private func makeAnalyzer() -> WorkspaceAnalyzer {
        WorkspaceAnalyzer(
            swiftLintCLI: MockSwiftLintCLIActor(),
            violationStorage: WorkspaceAnalyzerTestHelpers.createMockViolationStorage(),
            fileTracker: FileTracker.createForTesting()
        )
    }

    @Test("filterViolations is a subset, membership-exact, and idempotent")
    func filterLaws() async {
        let analyzer = makeAnalyzer()
        await propertyCheck(input: Self.violationsGenerator(), Self.batchGenerator()) { violations, batch in
            let result = analyzer.filterViolations(violations, batch: batch, workspacePath: Self.workspace)

            // Subset — a filter invents nothing.
            #expect(Set(result).isSubset(of: Set(violations)))

            // Membership — a violation is kept iff its full path is in the batch.
            let batchPaths = Set(batch.map(\.path))
            for violation in violations {
                let fullPath = Self.workspace.appendingPathComponent(violation.filePath).path
                #expect(result.contains(violation) == batchPaths.contains(fullPath))
            }

            // Idempotence under the same batch — a second pass changes nothing.
            #expect(
                analyzer.filterViolations(result, batch: batch, workspacePath: Self.workspace) == result
            )
        }
    }
}
