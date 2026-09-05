import Foundation

/// A source of "now", injected so that a caller can decide what time it is.
///
/// Reading `Date.now` inline makes a function a function of the wall clock as well as its
/// arguments. Two runs disagree, so no law can be stated about the result and a failing run
/// cannot be replayed. Passing the clock in makes the same code a function of its inputs
/// again, and the effect moves to the one call site that actually has a clock.
///
/// The default is the system clock, so no existing call site changes.
public struct DateProvider: Sendable {

    private let make: @Sendable () -> Date

    public init(_ make: @escaping @Sendable () -> Date) {
        self.make = make
    }

    /// Reads the wall clock. The production default.
    ///
    /// This is the one place in the package that is allowed to read it. Every other clock
    /// read was a hidden input; this one is the seam they were moved to.
    // swiftprojectlint:disable:next non-injected-nondeterminism
    public static let system = DateProvider { Date() }

    /// Always the same instant.
    ///
    /// Right for a *stamp* — `completedAt`, `detectedAt` — where the test asserts the record
    /// carries the time it was told. Wrong for a duration, which this makes always zero;
    /// use ``scripted(_:)`` there.
    public static func fixed(_ date: Date) -> DateProvider {
        DateProvider { date }
    }

    /// Returns each instant in turn, then repeats the last one forever.
    ///
    /// This is the one that makes a stopwatch testable. Code that reads the clock once before
    /// the work and once after computes a duration from the gap, so a scripted pair turns an
    /// unassertable elapsed time into a value the test chose: script `[t, t + 5]` and the
    /// duration is exactly 5.
    ///
    /// Repeating the last instant rather than trapping is deliberate — a caller that reads the
    /// clock one more time than the test predicted gets a defensible answer instead of a dead
    /// process, and the assertion still fails if the count mattered.
    public static func scripted(_ dates: [Date]) -> DateProvider {
        precondition(!dates.isEmpty, "a scripted DateProvider needs at least one instant")
        let cursor = Cursor(dates)
        return DateProvider { cursor.next() }
    }

    public func callAsFunction() -> Date { make() }

    /// Hands out the scripted instants in order under a lock, since a provider is `Sendable`
    /// and the code under test may read the clock from more than one task.
    private nonisolated final class Cursor: @unchecked Sendable {
        private let dates: [Date]
        private var index = 0
        private let lock = NSLock()

        init(_ dates: [Date]) { self.dates = dates }

        func next() -> Date {
            lock.lock()
            defer { lock.unlock() }
            let date = dates[min(index, dates.count - 1)]
            index += 1
            return date
        }
    }
}

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

    /// Fresh random identifiers. The production default.
    ///
    /// As with `DateProvider.system`, the nondeterminism is deliberate and confined here.
    // swiftprojectlint:disable:next non-injected-nondeterminism
    public static let random = IDProvider { UUID() }

    /// Counts up from zero, so the nth identifier is the same on every run.
    public static func sequential() -> IDProvider {
        let counter = Counter()
        return IDProvider { counter.next() }
    }

    public func callAsFunction() -> UUID { make() }

    private nonisolated final class Counter: @unchecked Sendable {
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
