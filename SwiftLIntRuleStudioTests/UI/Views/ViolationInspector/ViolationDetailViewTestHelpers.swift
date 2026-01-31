//
//  ViolationDetailViewTestHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Helper utilities for ViolationDetailView tests
//

import SwiftUI
@testable import SwiftLIntRuleStudio

enum ViolationDetailViewTestHelpers {
    static func makeTestViolation(
        id: UUID = UUID(),
        ruleID: String = "test_rule",
        filePath: String = "Test.swift",
        line: Int = 10,
        column: Int? = 5,
        severity: Severity = .error,
        message: String = "Test violation message",
        suppressed: Bool = false,
        resolvedAt: Date? = nil
    ) async -> Violation {
        await MainActor.run {
            Violation(
                id: id,
                ruleID: ruleID,
                filePath: filePath,
                line: line,
                column: column,
                severity: severity,
                message: message,
                detectedAt: Date(),
                resolvedAt: resolvedAt,
                suppressed: suppressed
            )
        }
    }

    struct ViewResult: @unchecked Sendable {
        let view: AnyView

        init(view: some View) {
            self.view = AnyView(view)
        }
    }

    @MainActor
    static func createViolationDetailView(violation: Violation) -> ViewResult {
        let container = DependencyContainer.createForTesting()
        let view = ViolationDetailView(
            violation: violation,
            onSuppress: { _ in },
            onResolve: {}
        )
        .environmentObject(container)

        return ViewResult(view: view)
    }
}
