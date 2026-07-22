//
//  ViolationStorageCollectRowsTests.swift
//  SwiftLintRuleStudioTests
//
//  Regression for P3: the fetch loop treated a SQLite `.error` step like `.done`,
//  returning a silently truncated result. `collectRows` now throws on `.error`;
//  these drive its control flow with a scripted step sequence (no live database).
//

@testable import SwiftLintRuleStudioCore
import Testing

struct ViolationStorageCollectRowsTests {
    private let noError: () -> String = { "" }

    private func makeViolation() -> Violation {
        Violation(ruleID: "rule", filePath: "File.swift", line: 1, severity: .warning, message: "m")
    }

    /// A `step` closure that replays `results` one call at a time.
    private func stepper(_ results: [SQLiteStepResult]) -> () -> SQLiteStepResult {
        var index = 0
        return {
            defer { index += 1 }
            return results[index]
        }
    }

    @Test("Collects one parsed value per row until done")
    func collectsRowsUntilDone() throws {
        let result = try ViolationStorageActor.collectRows(
            step: stepper([.row, .row, .done]),
            parse: makeViolation,
            lastError: noError
        )
        #expect(result.count == 2)
    }

    @Test("Done with no rows returns an empty result")
    func doneReturnsEmpty() throws {
        let result = try ViolationStorageActor.collectRows(
            step: stepper([.done]),
            parse: { nil },
            lastError: noError
        )
        #expect(result.isEmpty)
    }

    @Test("A step error throws instead of returning a truncated result")
    func stepErrorThrows() {
        #expect(throws: ViolationStorageError.self) {
            _ = try ViolationStorageActor.collectRows(
                step: stepper([.row, .error]),
                parse: makeViolation,
                lastError: noError
            )
        }
    }

    @Test("An immediate step error throws")
    func immediateErrorThrows() {
        #expect(throws: ViolationStorageError.self) {
            _ = try ViolationStorageActor.collectRows(
                step: stepper([.error]),
                parse: makeViolation,
                lastError: noError
            )
        }
    }

    @Test("A nil parse result is skipped, not appended")
    func nilParseIsSkipped() throws {
        var parseCall = 0
        let result = try ViolationStorageActor.collectRows(
            step: stepper([.row, .row, .done]),
            parse: {
                defer { parseCall += 1 }
                return parseCall == 0 ? nil : makeViolation()
            },
            lastError: noError
        )
        #expect(result.count == 1)
    }
}
