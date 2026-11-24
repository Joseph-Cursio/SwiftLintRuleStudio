//
//  SwiftLintVersionOrderTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  How SwiftLint versions compare, on examples. The property laws check that the order is an
//  order; these check it is the right one.
//

@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct SwiftLintVersionOrderTests {
    @Test("versions compare by every number from the first, with or without a leading v")
    func comparesFromTheFirstNumber() {
        #expect(SwiftLintDeprecations.isVersion("0.65.0", lessThan: "1.0.0"))
        #expect(!SwiftLintDeprecations.isVersion("1.0.0", lessThan: "0.65.0"))
        #expect(SwiftLintDeprecations.isVersion("0.65.0", lessThan: "v1.0.0"))
        #expect(!SwiftLintDeprecations.isVersion("V1.0.0", lessThan: "1.0.0"))
    }
}
