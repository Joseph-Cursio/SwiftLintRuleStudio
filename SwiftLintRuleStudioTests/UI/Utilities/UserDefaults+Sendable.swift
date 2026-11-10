//
//  UserDefaults+Sendable.swift
//  SwiftLintRuleStudioTests
//

import Foundation

// UserDefaults is passed across actor boundaries in tests; @retroactive silences the
// "retroactive conformance" warning while keeping the required Sendable conformance.
extension UserDefaults: @retroactive @unchecked Sendable {}
