//
//  HeldSecurityScopes.swift
//  SwiftLintRuleStudio
//
//  The security scopes the sandboxed app holds open, shared by the code that opens them
//  (`WorkspaceManager`) and the code that reads through them (the in-process lint).
//

import Foundation

/// The security scopes the app holds open, each kept open until its holder releases it and
/// every lint that started while it was open is done.
///
/// An in-process lint can't be interrupted, and once its workspace's scope ends, the
/// workspace's files can still be found but not read. SwiftLint loads a nested config it has
/// found in a way that ends the process when the read fails, and in-process that's the app.
/// So a lint keeps every scope open from its start to its end, and a workspace closed or
/// replaced meanwhile keeps its scope until then.
///
/// A lint that starts once a scope has ended can't read through it at all, so it fails on the
/// checks it makes before SwiftLint loads anything, with an error rather than the app.
public final class HeldSecurityScopes: @unchecked Sendable {
    /// Shared by the whole app: a lint outlives the workspace, and the backend, that started it.
    public static let shared = HeldSecurityScopes()

    /// A scope this registry holds, to release with ``release(_:)``.
    public struct Hold: Hashable, Sendable {
        private let id = UUID()
    }

    private struct Scope {
        let stop: @Sendable () -> Void
        var lints = 0
        var isReleased = false
    }

    private let lock = NSLock()
    private var scopes: [Hold: Scope] = [:]

    public init() {}

    /// Holds a scope the caller has started, which `stop` ends.
    public func hold(stoppingWith stop: @escaping @Sendable () -> Void) -> Hold {
        let hold = Hold()
        lock.withLock { scopes[hold] = Scope(stop: stop) }
        return hold
    }

    /// Ends `hold`'s scope now, or when the last lint keeping it open is done.
    public func release(_ hold: Hold) {
        lock.withLock {
            scopes[hold]?.isReleased = true
            endIfUnused(hold)
        }
    }

    /// Runs `body` with every scope held now kept open until it returns.
    public func keepingOpen<T>(_ body: () throws -> T) rethrows -> T {
        let kept = lock.withLock {
            for hold in scopes.keys { scopes[hold]?.lints += 1 }
            return Array(scopes.keys)
        }
        defer {
            lock.withLock {
                for hold in kept {
                    scopes[hold]?.lints -= 1
                    endIfUnused(hold)
                }
            }
        }
        return try body()
    }

    /// How many scopes are open, released or not.
    var openCount: Int {
        lock.withLock { scopes.count }
    }

    /// Whether `hold`'s scope is still open, released or not.
    func isOpen(_ hold: Hold) -> Bool {
        lock.withLock { scopes[hold] != nil }
    }

    /// Ends the scope under the lock, so that a lint starting meanwhile either keeps it open
    /// or finds it already closed — never reads through it as it ends.
    private func endIfUnused(_ hold: Hold) {
        guard let scope = scopes[hold], scope.isReleased, scope.lints == 0 else { return }
        scopes[hold] = nil
        scope.stop()
    }
}
