//
//  AnalysisProgressPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  What `AnalysisProgress.progress` is, beyond the range its doc comment
//  states. That range is swift-infer's `documented-range` law, generated
//  beside this file. It found the fraction unclamped, but it cannot see a guard
//  that returns 0.0 for every positive total, because 0.0 is in range. These
//  laws state the value: the fraction of files processed when the count is
//  within its total, and 0.0 when the total is unknown or zero.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("Analysis progress property laws")
struct AnalysisProgressPropertyLawTests {

    private static func snapshot(processed: Int, total: Int?) -> AnalysisProgress {
        AnalysisProgress(
            currentFile: nil, filesProcessed: processed, totalFiles: total, violationsFound: 0, isComplete: false
        )
    }

    @Test("within its total, progress is the fraction of files processed")
    func fractionWithinTotal() async {
        let counts = zip(Gen<Int>.int(in: 1...10_000), Gen<Int>.int(in: 0...10_000))
            .map { total, draw in (total: total, processed: draw % (total + 1)) }
        await propertyCheck(input: counts) { count in
            let progress = Self.snapshot(processed: count.processed, total: count.total).progress
            #expect(progress == Double(count.processed) / Double(count.total))
        }
    }

    @Test("an unknown or empty total is no progress, whatever was counted", arguments: [
        (0, nil), (5, nil), (0, 0), (7, 0), (3, -2)
    ] as [(Int, Int?)])
    func noTotal(processed: Int, total: Int?) {
        #expect(Self.snapshot(processed: processed, total: total).progress == 0.0)
    }

    @Test("a count past its total, or below zero, is clamped to the documented range")
    func clamped() {
        #expect(Self.snapshot(processed: 12, total: 10).progress == 1.0)
        #expect(Self.snapshot(processed: -3, total: 10).progress == 0.0)
    }
}
