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

    @Test("a .swift pattern names files only, and no patterns exclude nothing")
    func swiftPatternAndNone() {
        let exclusions = MirrorExclusions(patterns: ["/ws/A.swift"])

        #expect(exclusions.excludes("/ws/A.swift"))
        #expect(!exclusions.excludes("/ws/A.swift/B.swift"))
        #expect(!MirrorExclusions(patterns: []).excludes("/ws/A.swift"))
    }
}
