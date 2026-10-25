//
//  DeterminismProvidersTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The clock and the identifier source were read inline — `Date.now` and `UUID()` at the
//  point of use — which made the services that read them functions of the wall clock as
//  well as their arguments. Two runs disagreed, so nothing could be asserted about a
//  duration or a stamp, and a failing run could not be replayed.
//
//  These cover the providers themselves and an elapsed time, which was unassertable before
//  them. ConfigVersionHistoryClockTests covers the other: a timestamp that round-trips
//  through a filename.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("Determinism providers")
struct DeterminismProvidersTests {

    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - DateProvider

    @Test("a fixed provider returns the same instant every time")
    func fixedIsConstant() {
        let now = DateProvider.fixed(Self.epoch)
        #expect(now() == Self.epoch)
        #expect(now() == Self.epoch)
    }

    @Test("a scripted provider hands out its instants in order")
    func scriptedIsOrdered() {
        let now = DateProvider.scripted([Self.epoch, Self.epoch + 5, Self.epoch + 11])
        #expect(now() == Self.epoch)
        #expect(now() == Self.epoch + 5)
        #expect(now() == Self.epoch + 11)
    }

    @Test("a scripted provider repeats its last instant rather than trapping")
    func scriptedRepeatsTheLast() {
        // Deliberate: a caller that reads the clock one more time than the test predicted
        // gets a defensible answer instead of killing the test process. An assertion that
        // depended on the count still fails.
        let now = DateProvider.scripted([Self.epoch])
        #expect(now() == Self.epoch)
        #expect(now() == Self.epoch)
    }

    @Test("a scripted pair makes an elapsed time exactly what the test chose")
    func scriptedMakesDurationsAssertable() {
        // This is the shape every stopwatch in the codebase has: read the clock, do the
        // work, read it again, subtract. With the wall clock the difference is whatever the
        // machine was doing; scripted, it is a number the test picked.
        let now = DateProvider.scripted([Self.epoch, Self.epoch + 5])
        let startTime = now()
        let duration = now().timeIntervalSince(startTime)
        #expect(duration == 5)
    }

    @Test("the system provider actually reads the clock")
    func systemAdvances() {
        // Guards against a default that quietly froze — the failure mode that would make
        // every timestamp in production identical.
        let now = DateProvider.system
        let before = Date()
        let sampled = now()
        #expect(sampled.timeIntervalSince(before) >= 0)
        #expect(sampled.timeIntervalSince(before) < 60)
    }

    // MARK: - IDProvider

    @Test("sequential identifiers are the same on every run")
    func sequentialIsReproducible() {
        let first = IDProvider.sequential()
        let second = IDProvider.sequential()
        #expect(first() == second())
        #expect(first() == second())
    }

    @Test("sequential identifiers are distinct from each other")
    func sequentialIsUnique() {
        let makeID = IDProvider.sequential()
        let ids = (0..<50).map { _ in makeID() }
        #expect(Set(ids).count == 50)
    }

    @Test("random identifiers are the default and are not reproducible")
    func randomIsRandom() {
        let makeID = IDProvider.random
        let first = makeID()
        let second = makeID()
        #expect(first != second)
    }
}
