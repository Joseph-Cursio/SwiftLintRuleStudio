//
//  LintReportDecoderTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Reading SwiftLint's JSON report: paths made relative to the workspace, however SwiftLint
//  spells them.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct LintReportDecoderTests {
    private func report(file: String) throws -> Data {
        let violation: [String: Any] = [
            "rule_id": "force_cast",
            "reason": "Force casts should be avoided",
            "severity": "Error",
            "file": file,
            "line": 3,
            "character": 7
        ]
        return try JSONSerialization.data(withJSONObject: [violation])
    }

    @Test("a path under /var is made relative to the workspace when SwiftLint spells it under /private")
    func privateSpelling() throws {
        // The temporary directory is under /var, which resolves to itself: only the /private
        // spelling made from the prefix matches what SwiftLint reports.
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("LintReportDecoderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try #require(workspace.path.hasPrefix("/var/"), "the temporary directory isn't under /var")

        let violations = try LintReportDecoder.decode(
            report(file: "/private" + workspace.path + "/Sources/A.swift"),
            workspacePath: workspace,
            mapping: nil,
            ruleIds: nil
        )

        #expect(violations.map(\.filePath) == ["Sources/A.swift"])
        #expect(violations.map(\.severity) == ["error"])
    }
}
