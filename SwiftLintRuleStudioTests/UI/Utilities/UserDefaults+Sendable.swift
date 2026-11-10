//
//  UserDefaults+Sendable.swift
//  SwiftLintRuleStudioTests
//

import SwiftLintCLIBackend
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

// UserDefaults is passed across actor boundaries in tests; @retroactive silences the
// "retroactive conformance" warning while keeping the required Sendable conformance.
extension UserDefaults: @retroactive @unchecked Sendable {}
