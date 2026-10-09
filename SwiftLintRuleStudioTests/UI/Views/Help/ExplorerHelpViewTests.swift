//
//  ExplorerHelpViewTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the sandboxed edition's in-app help window
//

import Foundation
@testable import SwiftLintRuleStudio
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct ExplorerHelpViewTests {

    private func hasText(_ text: String) -> Bool {
        (try? ExplorerHelpView().inspect().find(text: text)) != nil
    }

    @Test("Help covers the built-in SwiftLint, SourceKit rules, and the other edition")
    func testShowsSections() {
        #expect(hasText("Getting Started"))
        #expect(hasText("Built-In SwiftLint"))
        #expect(hasText("SourceKit Rules"))
        #expect(hasText("Using Your Own SwiftLint"))
        #expect(hasText("More Help"))
    }

    @Test("Help names the non-sandboxed edition and says it's free")
    func testMentionsStudioEdition() {
        let note = """
        SwiftLint Rule Studio, the free non-sandboxed edition, uses the SwiftLint installed \
        on your Mac, including SourceKit rules.
        """
        #expect(hasText(note))
    }

    @Test("Help explains that the sandbox is why SwiftLint is bundled")
    func testExplainsSandbox() {
        let note = """
        For your security, apps from the Mac App Store run in a sandbox, which limits them to \
        their own built-in tools instead of programs installed elsewhere on your Mac. That's why \
        this app uses its bundled SwiftLint rather than one you've installed, and why its \
        SwiftLint version updates along with the app.
        """
        #expect(hasText(note))
    }

    @Test("Help links to the rule reference and issue tracker")
    func testShowsLinks() {
        let view = ExplorerHelpView()
        let linkCount = (try? view.inspect().findAll(ViewType.Link.self).count) ?? 0
        #expect(linkCount == 2)
    }
}
