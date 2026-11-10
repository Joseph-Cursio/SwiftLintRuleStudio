//
//  Severity+LintSeverity.swift
//  SwiftLintRuleStudio
//

import LintStudioCore
import SwiftLintRuleStudioCore

extension Severity: @retroactive LintSeverity {
    public var isError: Bool { self == .error }
}
