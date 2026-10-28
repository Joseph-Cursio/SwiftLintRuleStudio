//
//  MirrorExclusionsTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  `excluded` patterns match as SwiftLint's filename matchers match them.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct MirrorExclusionsTests {
    @Test("a literal pattern excludes that path and everything in it, case-sensitively")
    func literalPattern() {
        let exclusions = MirrorExclusions(patterns: ["/ws/Sources/loop"])

        #expect(exclusions.excludes("/ws/Sources/loop"))
        #expect(exclusions.excludes("/ws/Sources/loop/A.swift"))
        #expect(!exclusions.excludes("/ws/Sources/loopy"))
        #expect(!exclusions.excludes("/ws/sources/loop"))
    }

    @Test("* matches across folders, as in Python's fnmatch, and **/ matches no folder or any number")
    func wildcards() {
        let exclusions = MirrorExclusions(patterns: ["/ws/Sour*/l?op", "/ws/**/gen"])

        #expect(exclusions.excludes("/ws/Sources/loop"))
        #expect(exclusions.excludes("/ws/Sour/ces/loop"))
        #expect(exclusions.excludes("/ws/gen"))
        #expect(exclusions.excludes("/ws/a/b/gen/X.swift"))
        #expect(!exclusions.excludes("/ws/a/generated"))
    }

    @Test("a bracket expression matches one character, and a [ that never closes is literal")
    func brackets() {
        let exclusions = MirrorExclusions(patterns: ["/ws/[!A]ib", "/ws/x[y"])

        #expect(exclusions.excludes("/ws/Lib"))
        #expect(!exclusions.excludes("/ws/Aib"))
        #expect(exclusions.excludes("/ws/x[y"))
    }

    @Test("a * before more of the pattern matches as little as it can and never gives it back, as in fnmatch")
    func atomicStars() {
        let exclusions = MirrorExclusions(patterns: ["/ws/*/**/Gen/*/Mocks"])

        #expect(exclusions.excludes("/ws/A/Gen/B/Mocks"))
        // The first star stops at the first `/`, then **/ takes all it can, up to the second Gen:
        // `/Mocks` can't follow.
        #expect(!exclusions.excludes("/ws/A/Gen/B/Gen/Mocks"))
        #expect(MirrorExclusions(patterns: ["/ws/*/Gen/*/Mocks"]).excludes("/ws/A/Gen/B/Gen/Mocks"))
    }

    @Test("a [ in brackets stands for itself, a range runs forwards only, and & ~ | in brackets match nothing")
    func bracketSets() {
        #expect(MirrorExclusions(patterns: ["/ws/Vendor [[]old]"]).excludes("/ws/Vendor [old]"))
        #expect(MirrorExclusions(patterns: ["/ws/[a-c]x"]).excludes("/ws/bx"))
        #expect(!MirrorExclusions(patterns: ["/ws/[c-a]x"]).excludes("/ws/bx"))
        #expect(!MirrorExclusions(patterns: ["/ws/[|]x"]).excludes("/ws/|x"))
    }

    @Test("a path counts as excluded only when it matches both minding and ignoring case, as SwiftLint ignores it")
    func bothCases() {
        // SwiftLint's [^a], ignoring case, doesn't take A.
        #expect(!MirrorExclusions(patterns: ["/ws/[!a]"]).excludes("/ws/A"))
        #expect(MirrorExclusions(patterns: ["/ws/[!a]"]).excludes("/ws/B"))
        // Ignoring case, the **/ settles on the later gen/, and /Mocks can't follow.
        #expect(!MirrorExclusions(patterns: ["/ws/*/**/Gen/*/Mocks"]).excludes("/ws/A/Gen/B/gen/Mocks"))
        #expect(MirrorExclusions(patterns: ["/ws/*/**/Gen/*/Mocks"]).excludes("/ws/A/Gen/B/xyz/Mocks"))
    }

    @Test("a .swift pattern names files only, and no patterns exclude nothing")
    func swiftPatternAndNone() {
        let exclusions = MirrorExclusions(patterns: ["/ws/A.swift"])

        #expect(exclusions.excludes("/ws/A.swift"))
        #expect(!exclusions.excludes("/ws/A.swift/B.swift"))
        #expect(!MirrorExclusions(patterns: []).excludes("/ws/A.swift"))
    }
}
