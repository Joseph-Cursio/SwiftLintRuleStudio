//
//  MirrorLinkReachTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Which links SwiftLint can reach on the way to an `included` entry, and where it walks.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct MirrorLinkReachTests {
    @Test("an entry spelled in another case reaches the folder, as on the volumes macOS defaults to")
    func caseVariant() {
        let reach = MirrorLinkReach.towardIncluded([["sources", "sub"]])

        #expect(reach.follows(linkAt: "Sources"))
        #expect(reach.follows(linkAt: "Sources/Sub"))
        #expect(!reach.follows(linkAt: "Tests"))
    }

    @Test("braces reach anything in an entry SwiftLint expands as a glob, and nothing in one it doesn't")
    func braces() {
        // SwiftLint globs an entry only when it holds `*`, `?` or `[`; otherwise `{A,B}` is a name.
        #expect(MirrorLinkReach.towardIncluded([["Modules", "{Core,UI}", "*"]]).follows(linkAt: "Modules/Core"))
        #expect(MirrorLinkReach.towardIncluded([["Modules", "{Core,UI}", "*"]]).follows(linkAt: "Modules/Other"))
        #expect(!MirrorLinkReach.towardIncluded([["{Sources,Lib}"]]).follows(linkAt: "Sources"))
    }

    @Test("** reaches anything below it")
    func globstar() {
        let reach = MirrorLinkReach.towardIncluded([["Sources", "**"]])

        #expect(reach.follows(linkAt: "Sources/a/b"))
        #expect(!reach.follows(linkAt: "Tests/a"))
    }

    @Test("SwiftLint walks an entry and what lies beneath it, not what lies on the way to it")
    func within() {
        #expect(MirrorLinkReach.isWithin("Sources/loop", anyOf: [["Sources"]]))
        #expect(!MirrorLinkReach.isWithin("Sources/loop", anyOf: [["Tests"]]))
        #expect(!MirrorLinkReach.isWithin("Sources", anyOf: [["Sources", "Sub"]]))
        #expect(MirrorLinkReach.isWithin("Anything", anyOf: [[]]))
        #expect(!MirrorLinkReach.isWithin("Anything", anyOf: []))
    }
}
