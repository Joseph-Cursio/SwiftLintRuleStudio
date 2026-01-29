//
//  CodeBlockTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for CodeBlock view
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

@Suite(.serialized)
struct CodeBlockTests {
    @Test("CodeBlock renders code text")
    func testCodeBlockText() async throws {
        let view = CodeBlock(code: "let value = 1", isError: false)
        let text = try await MainActor.run {
            try view.inspect().find(ViewType.Text.self).string()
        }
        #expect(text == "let value = 1")
    }

    @Test("CodeBlock renders error and non-error styles")
    func testCodeBlockStyles() async throws {
        let errorView = CodeBlock(code: "bad()", isError: true)
        let okView = CodeBlock(code: "ok()", isError: false)

        let (errorHasHStack, okHasHStack) = await MainActor.run {
            let errorStack = (try? errorView.inspect().find(ViewType.HStack.self)) != nil
            let okStack = (try? okView.inspect().find(ViewType.HStack.self)) != nil
            return (errorStack, okStack)
        }

        #expect(errorHasHStack == true)
        #expect(okHasHStack == true)
    }
}
