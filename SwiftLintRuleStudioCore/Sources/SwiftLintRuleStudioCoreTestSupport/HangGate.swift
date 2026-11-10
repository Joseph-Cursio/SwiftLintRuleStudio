//
//  HangGate.swift
//  SwiftLintRuleStudioTests
//

import Foundation
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore

public final class HangGate: @unchecked Sendable {
    nonisolated(unsafe) private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    nonisolated public func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    nonisolated public func open() {
        lock.lock()
        continuation?.resume()
        continuation = nil
        lock.unlock()
    }
}
