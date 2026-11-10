//
//  Severity+LintSeverity.swift
//  SwiftLintRuleStudio
//

import LintStudioCore
import SwiftLintRuleStudioCore
import SwiftUI

extension Severity: @retroactive LintSeverity {
    public var isError: Bool { self == .error }
}
