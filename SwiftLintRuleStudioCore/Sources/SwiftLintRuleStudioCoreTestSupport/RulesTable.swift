//
//  RulesTable.swift
//  SwiftLintRuleStudioTests
//

import Foundation
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore

public enum RulesTable: Sendable {
    nonisolated public static let border =
        "+------------------------------------------+--------+-------------+" +
        "------------------------+-------------+----------+" +
        "----------------+---------------+"
    nonisolated public static let header =
        "| identifier | opt-in | correctable " +
        "| enabled in your config | kind | analyzer | " +
        "uses sourcekit | configuration |"
}

/// Build a mock rules table data blob from the given rows
nonisolated public func makeRulesTableData(rows: [String]) -> Data {
    let lines = [RulesTable.border, RulesTable.header, RulesTable.border] + rows + [RulesTable.border]
    return Data(lines.joined(separator: "\n").utf8)
}
