import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// The analyzer reads the clock its sibling already took as a parameter.
///
/// `ImpactSimulator` has taken a `DateProvider` since it was written, and `DateProvider`'s own
/// documentation names `completedAt` and `detectedAt` as the fields it exists for.
/// `WorkspaceAnalyzer` — the primary path, running the same SwiftLint and parsing the same JSON —
/// read `Date.now` inline in four places. Two implementations of one job, one testable and one not.
///
/// Two things follow from injecting it, and only the first is about tests.
struct WorkspaceAnalyzerClockTests {

    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    /// Two violations, listed with `Zebra.swift` before `Apple.swift` on purpose.
    private static func lintJSON(root: String) -> Data {
        Data("""
        [
          {
            "file": "\(root)/Zebra.swift",
            "line": 1,
            "severity": "error",
            "type": "force_cast",
            "reason": "second alphabetically, first in the output"
          },
          {
            "file": "\(root)/Apple.swift",
            "line": 1,
            "severity": "warning",
            "type": "line_length",
            "reason": "first alphabetically, second in the output"
          }
        ]
        """.utf8)
    }

    @MainActor
    private func analyze(with clock: DateProvider) async throws -> AnalysisResult {
        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLIActor()
        await WorkspaceAnalyzerTestHelpers.setupMockCLI(
            mockCLI, output: Self.lintJSON(root: workspace.path.path)
        )
        let analyzer = WorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: WorkspaceAnalyzerTestHelpers.createMockViolationStorage(),
            fileTracker: nil,
            now: clock
        )
        return try await analyzer.analyze(workspace: workspace)
    }

    // MARK: - One run, one instant

    /// Every violation a pass finds was found by that pass. Stamping them one at a time made that
    /// untrue by microseconds, which is invisible until something compares them — and something
    /// does: `ViolationInspectorViewModel` sorts by `detectedAt` with a file/line tiebreak
    /// underneath, so while every violation carried its own microsecond that tiebreak could never
    /// be reached. A list the user asked to see newest-first came back in whatever order the JSON
    /// arrived.
    @Test("all violations from one run carry the same instant")
    @MainActor
    func oneRunStampsOneInstant() async throws {
        let result = try await analyze(with: .fixed(Self.epoch))

        #expect(result.violations.count == 2)
        #expect(Set(result.violations.map(\.detectedAt)).count == 1)
        #expect(result.violations.allSatisfy { $0.detectedAt == Self.epoch })
    }

    /// The consequence, without going through the view model: equal instants mean the date
    /// comparison is `.orderedSame`, which is the only way anything underneath it can decide.
    @Test("equal instants leave the date comparison undecided, so a tiebreak can run")
    @MainActor
    func equalInstantsLeaveTheComparisonUndecided() async throws {
        let result = try await analyze(with: .fixed(Self.epoch))
        let (first, second) = (result.violations[0], result.violations[1])

        #expect(first.filePath != second.filePath, "two distinct violations")
        #expect(first.detectedAt == second.detectedAt)
    }

    // MARK: - A duration the test chose

    /// A stopwatch is the one thing `fixed` cannot express, which is what `scripted` is for: the
    /// clock is read once before the work and once after, so a scripted pair makes the gap a value
    /// the test picked rather than one it has to tolerate.
    @Test("the duration is the gap between the scripted instants")
    @MainActor
    func durationIsTheScriptedGap() async throws {
        let finished = Self.epoch.addingTimeInterval(5)

        let result = try await analyze(with: .scripted([Self.epoch, finished]))

        #expect(result.duration == 5)
        #expect(result.startedAt == Self.epoch)
        #expect(result.completedAt == finished)
    }

    /// Non-vacuity for the two above: the analyzer really reads the provider it was handed, so a
    /// different script gives a different answer rather than a constant.
    @Test("a different script gives a different duration")
    @MainActor
    func aDifferentScriptGivesADifferentDuration() async throws {
        let result = try await analyze(
            with: .scripted([Self.epoch, Self.epoch.addingTimeInterval(90)])
        )

        #expect(result.duration == 90)
    }
}
