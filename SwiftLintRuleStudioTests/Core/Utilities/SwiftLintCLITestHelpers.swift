//
//  SwiftLintCLITestHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Helper utilities for SwiftLintCLIActor tests
//

import Foundation
@testable import SwiftLIntRuleStudio

actor CommandRecorderActor {
    private(set) var calls: [(String, [String])] = []

    func record(_ command: String, _ arguments: [String]) {
        calls.append((command, arguments))
    }
}

actor AsyncMapActor<Value> {
    private var values: [String: Value]

    init(values: [String: Value]) {
        self.values = values
    }

    func get(_ key: String) -> Value {
        guard let value = values[key] else {
            fatalError("Missing value for key: \(key)")
        }
        return value
    }

    func set(_ key: String, _ value: Value) {
        values[key] = value
    }
}
