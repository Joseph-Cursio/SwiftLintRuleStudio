import FilenameMatcher
import Foundation
import SwiftLintFramework

/// The workspace has a folder symlink SwiftLint would follow round for ever.
struct SymlinkLoopError: LocalizedError, Equatable {
    /// The link, relative to the workspace when it's inside it.
    let link: String
    /// Whether naming the link in `excluded` makes SwiftLint skip it. In a workspace spelled
    /// under `/private`, as an open panel gives one in `/tmp` or `/var`, it doesn't: SwiftLint
    /// spells the patterns with that prefix and matches the link's path without it.
    var excludingSkipsLink = true

    var errorDescription: String? {
        "SwiftLint follows the symlink at \(link) back into a folder that holds it, round and round until it "
            + "crashes, so the lint stopped before it started. " + advice
    }

    private var advice: String {
        guard !excludingSkipsLink else { return "Add it to `excluded` and SwiftLint skips it." }
        let skipsNoLink = "In a workspace under /tmp or /var, SwiftLint doesn't skip a symlink `excluded` names: "
        guard let slash = link.lastIndex(where: { $0 == "/" }), slash != link.startIndex else {
            return skipsNoLink + "remove the link, or keep it in a folder `excluded` names."
        }
        return skipsNoLink + "exclude \(link[..<slash]), the folder that holds it, or remove the link."
    }
}

/// Retraces the walk SwiftLint makes to find the files to lint, and refuses one that never ends.
///
/// With `excluded` set, SwiftLint collects files folder by folder (`FileManager.collectFiles`):
/// it resolves each link it meets and walks the folder behind it, keeping no record of where it
/// has been. A link back into a folder holding it is walked again and again, until the stack
/// overflows — which, in-process, is the app. Without `excluded` it lists files with
/// `subpaths(atPath:)`, which doesn't follow links, so there is nothing to check.
///
/// What SwiftLint walks next depends only on the path of the folder it is walking, so the check
/// walks the same paths the same way — the same directory listing, the same link resolution,
/// SwiftLint's own exclusion matching — and stops at the first that leads back to one it is
/// still walking. The Rule Audit's mirror refuses the same loops (`MirrorLinkDiscovery`).
enum SymlinkLoopCheck {
    /// Throws ``SymlinkLoopError`` when linting `workspacePath` with `configuration` would walk
    /// a folder link round for ever.
    static func check(_ configuration: Configuration, workspacePath: URL) throws {
        guard !configuration.excludedPaths.isEmpty else { return }
        var walk = Walk(
            matchers: configuration.excludedPaths.flatMap { filenameMatchers(pattern: $0.path) },
            workspacePath: workspacePath
        )
        let included = configuration.includedPaths
        if included.isEmpty {
            try walk.walk(workspacePath)
            return
        }
        for path in included {
            if let prefix = globPrefix(of: path) {
                // SwiftLint expands the glob and walks each match. Walking from the folder above
                // the first wildcard, ignoring exclusions, walks every folder those walks do and
                // more, so it may refuse a loop SwiftLint never reaches but misses none.
                var unexcluded = Walk(matchers: [], workspacePath: workspacePath)
                try unexcluded.walk(prefix)
            } else {
                // A file, or nothing, lists no entries: SwiftLint walks it to no effect.
                try walk.walk(path)
            }
        }
    }

    /// SwiftLint's `Glob.createFilenameMatchers(pattern:)`.
    private static func filenameMatchers(pattern: String) -> [FilenameMatcher] {
        if pattern.hasSuffix(".swift") || pattern.hasSuffix("/**") {
            return [FilenameMatcher(pattern: pattern)]
        }
        if pattern.hasSuffix("/") {
            return [FilenameMatcher(pattern: pattern + "**")]
        }
        return [FilenameMatcher(pattern: pattern), FilenameMatcher(pattern: pattern + "/**")]
    }

    /// The folder above the first wildcard in `path`, when it has one.
    private static func globPrefix(of path: URL) -> URL? {
        let wildcards = CharacterSet(charactersIn: "*?[]")
        let components = path.pathComponents
        guard let first = components.firstIndex(where: { $0.rangeOfCharacter(from: wildcards) != nil }) else {
            return nil
        }
        // The first component is `/`, which holds no wildcard.
        return URL(fileURLWithPath: "/" + components[1..<first].joined(separator: "/"), isDirectory: true)
    }

    /// The folders being walked, each with the link that led into it, if one did.
    private struct Walk {
        private static let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        private static let options: FileManager.DirectoryEnumerationOptions = [
            .skipsPackageDescendants,
            .skipsSubdirectoryDescendants
        ]

        let matchers: [FilenameMatcher]
        let workspacePath: URL
        private var walking: [(path: String, link: URL?)] = []
        private var walked: Set<String> = []

        init(matchers: [FilenameMatcher], workspacePath: URL) {
            self.matchers = matchers
            self.workspacePath = workspacePath
        }

        /// Walks `folder` as SwiftLint's `collectFiles(atPath:excluder:)` does, entered through
        /// `link` when one led here.
        mutating func walk(_ folder: URL, through link: URL? = nil) throws {
            let path = folder.path
            if let start = walking.firstIndex(where: { $0.path == path }) {
                // The way round runs through at least one link: plain subfolders only go down.
                let culprit = walking[(start + 1)...].lazy.compactMap(\.link).first ?? link
                throw SymlinkLoopError(
                    link: culprit.map { relativePath(of: $0) } ?? path,
                    excludingSkipsLink: !workspacePath.path.hasPrefix("/private/")
                )
            }
            guard walked.insert(path).inserted else { return }
            walking.append((path, link))
            defer { walking.removeLast() }

            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: Array(Self.keys),
                options: Self.options
            ) else { return }
            var subfolders: [(url: URL, link: URL?)] = []
            for case var element as URL in enumerator {
                var values = try? element.resourceValues(forKeys: Self.keys)
                var entryLink: URL?
                if values?.isSymbolicLink == true {
                    element = element.standardizedFileURL
                    if excludes(element) { continue }
                    entryLink = element
                    element.resolveSymlinksInPath()
                    values = try? element.resourceValues(forKeys: Self.keys)
                }
                if values?.isRegularFile != true, values != nil, !excludes(element) {
                    subfolders.append((element, entryLink))
                }
            }
            for subfolder in subfolders {
                try walk(subfolder.url, through: subfolder.link)
            }
        }

        /// SwiftLint's `Excluder.excludes(path:)` for `.matching`: a path under `/private` also
        /// matches with that prefix dropped.
        private func excludes(_ url: URL) -> Bool {
            let path = url.path
            let stripped = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : nil
            return matchers.contains { matcher in
                matcher.match(filename: path) || stripped.map { matcher.match(filename: $0) } == true
            }
        }

        private func relativePath(of link: URL) -> String {
            let path = link.path
            for root in [workspacePath.standardizedFileURL.path, workspacePath.resolvingSymlinksInPath().path]
            where path.hasPrefix(root + "/") {
                return String(path.dropFirst(root.count + 1))
            }
            return path
        }
    }
}
