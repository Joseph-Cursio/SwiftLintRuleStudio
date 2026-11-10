//
//  Rule+LintRule.swift
//  SwiftLintRuleStudio
//

import LintStudioCore
import SwiftLintRuleStudioCore
import SwiftUI

extension Rule: @retroactive LintRule {
    public typealias CategoryType = RuleCategory

    public var identifier: String { id }
    public var ruleDescription: String { description }
}
