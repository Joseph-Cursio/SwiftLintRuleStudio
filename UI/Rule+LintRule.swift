//
//  Rule+LintRule.swift
//  SwiftLintRuleStudio
//

import LintStudioCore
import SwiftLintRuleStudioCore

extension Rule: @retroactive LintRule {
    public typealias CategoryType = RuleCategory

    public var identifier: String { id }
    public var ruleDescription: String { description }
}
