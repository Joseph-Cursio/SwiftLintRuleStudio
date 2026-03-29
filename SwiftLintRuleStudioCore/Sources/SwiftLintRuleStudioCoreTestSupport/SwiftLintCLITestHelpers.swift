//
//  SwiftLintCLITestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for SwiftLintCLIActor tests
//

import Foundation
@testable import SwiftLintRuleStudioCore

public actor CommandRecorderActor {
    public private(set) var calls: [(String, [String])] = []

    public init() {}

    public func record(_ command: String, _ arguments: [String]) {
        calls.append((command, arguments))
    }
}

public actor AsyncMapActor<Value> {
    private var values: [String: Value]

    public init(values: [String: Value]) {
        self.values = values
    }

    public func get(_ key: String) -> Value {
        guard let value = values[key] else {
            fatalError("Missing value for key: \(key)")
        }
        return value
    }

    public func set(_ key: String, _ value: Value) {
        values[key] = value
    }
}
