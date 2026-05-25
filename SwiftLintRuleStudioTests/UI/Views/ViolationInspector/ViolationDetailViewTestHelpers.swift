//
//  ViolationDetailViewTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for ViolationDetailView tests
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI

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
                ruleID: ruleID,
                filePath: filePath,
                line: line,
                severity: severity,
                message: message,
                id: id,
                column: column,
                detectedAt: Date.now,
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
        .environment(\.dependencies, container)

        return ViewResult(view: view)
    }
}
