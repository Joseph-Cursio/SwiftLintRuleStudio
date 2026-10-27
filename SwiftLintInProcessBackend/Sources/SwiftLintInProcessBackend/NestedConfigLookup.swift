import Foundation
import SwiftLintFramework

/// The configuration a file is linted with when nested configs apply, without asking SwiftLint's
/// `Configuration.configuration(for:)` about a file the disk alone settles.
///
/// SwiftLint remembers each answer in a process-wide dictionary it never empties, under a key
/// holding the folder and the lint's root folder: for a folder with no nested config above it,
/// that the root configuration applies there. `swiftlint` exits after one lint. In the app, a
/// rule simulation lints a mirror that moves to a new folder for every rule, so every simulated
/// rule left one entry behind for every folder the walk passed, kept until the app quits.
///
/// So this retraces SwiftLint's search, with SwiftLint's own steps: from the file's folder up,
/// stopping at the root's folder, or at `/`. A file whose search meets no `.swiftlint.yml` gets
/// `root`, as it would from SwiftLint in a fresh process. A file whose search meets one goes to
/// SwiftLint, which merges and caches as before. In a workspace with its own `.swiftlint.yml`,
/// so does every file whose path SwiftLint spells differently from the root's folder —
/// `/private/var/…` against `/var/…` — since both searches then pass the root's folder and meet
/// that `.swiftlint.yml`.
///
/// SwiftLint reads its dictionary before the disk, so at a root folder it has linted before, it
/// can answer from an entry the disk no longer matches. Only a lint of a workspace's own folder
/// does that: the analysis of a workspace with no `.swiftlint.yml`. A file this answers itself
/// is answered from the disk. A file it hands to SwiftLint still gets SwiftLint's remembered
/// answer, so there an edit to a nested config, or the removal of one beneath another, goes
/// unseen until the app quits.
struct NestedConfigLookup {
    let root: Configuration
    /// Whether the search from a folder meets a `.swiftlint.yml`, for each folder seen.
    private var findsConfig: [URL: Bool] = [:]

    init(root: Configuration) {
        self.root = root
    }

    mutating func configuration(for file: SwiftLintFile) -> Configuration {
        asksSwiftLint(about: file) ? root.configuration(for: file) : root
    }

    /// Whether `file`'s configuration comes from SwiftLint rather than from here.
    mutating func asksSwiftLint(about file: SwiftLintFile) -> Bool {
        guard let folder = file.path?.deletingLastPathComponent() else {
            return false
        }
        return searchFindsConfig(from: folder)
    }

    /// Whether SwiftLint's search from `folder` meets a `.swiftlint.yml` before it stops. Each step
    /// is SwiftLint's (`Configuration.configuration(forDirectory:)`), so both take the same path.
    private mutating func searchFindsConfig(from folder: URL) -> Bool {
        if let known = findsConfig[folder] {
            return known
        }
        let finds: Bool
        if folder == root.rootDirectory {
            finds = false
        } else if folder.appending(path: Configuration.defaultFileName, directoryHint: .notDirectory).exists {
            // SwiftLint passes over one that already went into the root configuration, as a
            // `parent_config` or `child_config` can; it decides that for itself.
            finds = true
        } else if folder.path != "/" {
            finds = searchFindsConfig(from: folder.deletingLastPathComponent())
        } else {
            finds = false
        }
        findsConfig[folder] = finds
        return finds
    }
}
