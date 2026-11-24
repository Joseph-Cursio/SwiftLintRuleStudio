//
//  Violation+LintViolation.swift
//  SwiftLintRuleStudio
//

import Foundation
import LintStudioCore
import SwiftLintRuleStudioCore

extension Violation: @retroactive LintViolation {
    public var identifier: UUID { id }
    public var ruleIdentifier: String { ruleID }
}
