//
//  Violation+LintViolation.swift
//  SwiftLintRuleStudio
//

import LintStudioCore
import SwiftLintRuleStudioCore
import SwiftUI

extension Violation: @retroactive LintViolation {
    public var identifier: UUID { id }
    public var ruleIdentifier: String { ruleID }
}
