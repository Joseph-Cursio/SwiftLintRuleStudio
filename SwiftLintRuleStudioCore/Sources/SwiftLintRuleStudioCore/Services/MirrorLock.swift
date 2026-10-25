//
//  MirrorLock.swift
//  SwiftLintRuleStudio
//
//  The advisory lock a live simulation mirror holds, so a sweep never removes it.
//

import Darwin
import Foundation

/// An advisory lock (`flock`) on a file inside a simulation mirror's container, held for the
/// mirror's whole life.
///
/// A mirror's age says nothing about whether it is in use: its creation and modification dates
/// never change while it is, and renaming it per rule moves only its ctime. A sweep that went by
/// age alone would remove the mirror of an audit left running across a night's sleep — and
/// SwiftLint reads a vanished file as empty, so the rules counted after that read short, or
/// in-process SwiftLint hits a fatal error on a vanished config. A sweep takes the lock first,
/// and leaves any mirror whose lock is held, by this app or another copy of it.
nonisolated final class MirrorLock: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }

    /// Creates the lock file in `container` and takes the lock.
    static func acquire(in container: URL) throws -> MirrorLock {
        let path = container.appendingPathComponent(MirrorScope.lockFileName).path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        return MirrorLock(descriptor: descriptor)
    }

    /// Whether a live mirror holds the lock in `container`. A container without a lock file
    /// predates the lock, or never got one; its age alone decides.
    static func isHeld(in container: URL) -> Bool {
        let path = container.appendingPathComponent(MirrorScope.lockFileName).path
        let descriptor = open(path, O_RDWR | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return true }
        flock(descriptor, LOCK_UN)
        return false
    }

    /// Lets go of the lock. Safe to call more than once.
    func release() {
        lock.withLock {
            guard descriptor >= 0 else { return }
            close(descriptor)
            descriptor = -1
        }
    }
}
