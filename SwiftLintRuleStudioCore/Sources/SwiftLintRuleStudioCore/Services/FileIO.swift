import Foundation

/// The file operations a service performs, injected so a test can choose what they do.
///
/// A struct of closures rather than a protocol, matching `DateProvider`: there are four
/// operations and nothing needs to conform to anything. `live` is the real file system, so a
/// caller that says nothing keeps the behaviour it had.
///
/// **What this is for, and what it is not.** The point is not that reading a file is untestable
/// — this package has forty test files that build real temp directories and they work. It is
/// that *failure* is untestable: a backup that cannot be read, a config that cannot be written,
/// a copy that fails halfway. Those paths decide whether a restore leaves the user's
/// configuration intact, and reaching them on a real file system means arranging a permission
/// error or a full disk.
/// `nonisolated` because the package defaults to `MainActor` isolation and this is a value
/// type made of `@Sendable` closures: binding it to an actor would stop a test from building
/// one outside the main actor, which is the only reason the seam exists.
nonisolated public struct FileIO: Sendable {

    public var read: @Sendable (URL) throws -> String
    public var write: @Sendable (String, URL) throws -> Void
    public var exists: @Sendable (URL) -> Bool
    public var copy: @Sendable (URL, URL) throws -> Void

    public init(
        read: @escaping @Sendable (URL) throws -> String,
        write: @escaping @Sendable (String, URL) throws -> Void,
        exists: @escaping @Sendable (URL) -> Bool,
        copy: @escaping @Sendable (URL, URL) throws -> Void
    ) {
        self.read = read
        self.write = write
        self.exists = exists
        self.copy = copy
    }

    /// The real file system. The production default.
    public static let live = Self(
        read: { try String(contentsOf: $0, encoding: .utf8) },
        write: { try $0.write(to: $1, atomically: true, encoding: .utf8) },
        exists: { FileManager.default.fileExists(atPath: $0.path) },
        copy: { try FileManager.default.copyItem(at: $0, to: $1) }
    )
}
