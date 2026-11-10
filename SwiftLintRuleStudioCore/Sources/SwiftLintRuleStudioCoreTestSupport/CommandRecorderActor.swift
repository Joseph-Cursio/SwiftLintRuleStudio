//
//  CommandRecorderActor.swift
//  SwiftLintRuleStudioTests
//

import Foundation
@testable import SwiftLintRuleStudioCore

/// Actor that records CLI command invocations for test assertions
public actor CommandRecorderActor {
    /// List of recorded command and argument pairs
    public private(set) var calls: [(String, [String])] = []

    /// Initialize an empty command recorder
    public init() {
        // Declared only to make the initializer public.
    }

    /// Record a command invocation with its arguments
    public func record(_ command: String, _ arguments: [String]) {
        calls.append((command, arguments))
    }
}
