import Foundation

/// A source of identifiers, injected for the same reason as ``DateProvider``.
///
/// Only worth injecting where the identifier is *observable* — where a test compares two
/// values that carry one, so a fresh `UUID()` on each run would make equal records unequal.
/// A `UUID()` used to name a scratch directory is not that: nothing asserts on the name, and
/// injecting one there buys indirection and no testability.
public struct IDProvider: Sendable {

    private let make: @Sendable () -> UUID

    public init(_ make: @escaping @Sendable () -> UUID) {
        self.make = make
    }

    // swiftprojectlint:disable:next non-injected-nondeterminism
    /// Fresh random identifiers. The production default.
    ///
    /// As with `DateProvider.system`, the nondeterminism is deliberate and confined here.
    public static let random = Self { UUID() }

    /// Counts up from zero, so the nth identifier is the same on every run.
    public static func sequential() -> Self {
        let counter = Counter()
        return Self { counter.next() }
    }

    public func callAsFunction() -> UUID { make() }

    nonisolated private final class Counter: @unchecked Sendable {
        private var value: UInt32 = 0
        private let lock = NSLock()

        func next() -> UUID {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            let hex = String(format: "%08x", value)
            // The fallback is unreachable — the string above is always a valid UUID — and
            // exists only so this stays total rather than force-unwrapping.
            // swiftprojectlint:disable:next non-injected-nondeterminism
            return UUID(uuidString: "\(hex)-0000-0000-0000-000000000000") ?? UUID()
        }
    }
}
