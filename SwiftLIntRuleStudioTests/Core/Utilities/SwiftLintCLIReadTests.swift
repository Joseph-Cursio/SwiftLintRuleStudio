//
//  SwiftLintCLIReadTests.swift
//  SwiftLIntRuleStudioTests
//
//  ReadWithTimeout and readChunks tests for SwiftLintCLI
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct SwiftLintCLIReadTests {
    @Test("SwiftLintCLI readWithTimeout returns data on time")
    func testReadWithTimeoutSuccess() async throws {
        let read: @Sendable () async -> (Data, Data) = {
            (Data("ok".utf8), Data("warn".utf8))
        }
        let onTimeout: @Sendable () async -> Void = { }
        let timeoutResult = try await SwiftLintCLI.readWithTimeout(
            timeoutSeconds: 1,
            read: read,
            onTimeout: onTimeout
        )
        #expect(String(data: timeoutResult.stdout, encoding: .utf8) == "ok")
        #expect(String(data: timeoutResult.stderr, encoding: .utf8) == "warn")
        #expect(timeoutResult.didTimeout == false)
    }

    @Test("SwiftLintCLI readWithTimeout handles timeout")
    func testReadWithTimeoutTimeout() async throws {
        final class HangGate: @unchecked Sendable {
            private var continuation: CheckedContinuation<Void, Never>?
            private let lock = NSLock()

            func wait() async {
                await withCheckedContinuation { continuation in
                    lock.lock()
                    self.continuation = continuation
                    lock.unlock()
                }
            }

            func open() {
                lock.lock()
                continuation?.resume()
                continuation = nil
                lock.unlock()
            }
        }

        let gate = HangGate()
        let read: @Sendable () async -> (Data, Data) = {
            return await withTaskCancellationHandler {
                await gate.wait()
                return (Data(), Data())
            } onCancel: {
                gate.open()
            }
        }
        actor TimeoutTracker {
            var didTimeout = false
            func mark() { didTimeout = true }
        }
        let tracker = TimeoutTracker()
        let onTimeout: @Sendable () async -> Void = {
            await tracker.mark()
        }

        let timeoutResult = try await SwiftLintCLI.readWithTimeout(
            timeoutSeconds: 1,
            read: read,
            onTimeout: onTimeout
        )
        #expect(timeoutResult.stdout.isEmpty == true)
        #expect(timeoutResult.stderr.isEmpty == true)
        #expect(timeoutResult.didTimeout == true)
        let didTimeout = await tracker.didTimeout
        #expect(didTimeout == true)
    }

    @Test("SwiftLintCLI readChunks accumulates data")
    func testReadChunksAccumulation() async {
        final class ChunkSource: @unchecked Sendable {
            private var chunks: [Data]
            private let lock = NSLock()

            init(chunks: [Data]) {
                self.chunks = chunks
            }

            func next() -> Data {
                lock.lock()
                defer { lock.unlock() }
                if chunks.isEmpty { return Data() }
                return chunks.removeFirst()
            }
        }
        let source = ChunkSource(chunks: [
            Data("one".utf8),
            Data("two".utf8),
            Data()
        ])
        let read: @Sendable () -> Data = {
            source.next()
        }
        let sleep: @Sendable (UInt64) async -> Void = { _ in }
        let data = await SwiftLintCLI.readChunks(read: read, sleep: sleep, intervalNs: 1)
        #expect(String(data: data, encoding: .utf8) == "onetwo")
    }
}
