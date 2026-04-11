//
//  SwiftLintCLITestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for SwiftLintCLIActor tests
//

import Foundation
@testable import SwiftLintRuleStudioCore

/// Actor that records CLI command invocations for test assertions
public actor CommandRecorderActor {
    /// List of recorded command and argument pairs
    public private(set) var calls: [(String, [String])] = []

    /// Initialize an empty command recorder
    public init() {}

    /// Record a command invocation with its arguments
    public func record(_ command: String, _ arguments: [String]) {
        calls.append((command, arguments))
    }
}

/// Thread-safe key-value store for test data
public actor AsyncMapActor<Value> {
    private var values: [String: Value]

    /// Initialize with a dictionary of values
    public init(values: [String: Value]) {
        self.values = values
    }

    /// Retrieve a value by key, fatal error if missing
    public func get(_ key: String) -> Value {
        guard let value = values[key] else {
            fatalError("Missing value for key: \(key)")
        }
        return value
    }

    /// Store a value by key
    public func set(_ key: String, _ value: Value) {
        values[key] = value
    }
}
