//
//  MirrorLinkDiscovery.swift
//  SwiftLintRuleStudio
//
//  Finds the folders and files a workspace's symlinks reach, for the simulation mirror.
//

import Foundation

/// The outside folders a workspace's links reach hold more files than the mirror will copy.
nonisolated struct MirrorTooLargeError: LocalizedError, Sendable {
    let limit: Int
    /// The first link that led outside the workspace, relative to it, when one did.
    let link: String?
    /// The folder outside the workspace where the count went past the limit.
    let target: String

    var errorDescription: String? {
        let start = link.map { "the first through \($0) → \(target)" } ?? "starting with \(target)"
        return "The workspace's symlinks and `included` entries reach more than \(limit.formatted()) files "
            + "outside it, \(start). Simulating a rule would copy them all, so the simulation stopped."
    }
}

/// Walks the workspace and every folder a link reaches, depth first, to find the folders and
/// files links point at and the links that close a cycle.
nonisolated struct MirrorLinkDiscovery {
    /// How many entries the folders outside the workspace may hold before the mirror refuses
    /// them. A link to a toolchain or a whole volume would otherwise be walked and copied for
    /// every simulation; SwiftLint would lint it too, but in minutes, for a result nobody can use.
    static let outsideEntryLimit = 20_000

    let fileManager: FileManager
    let reach: MirrorLinkReach
    let workspaceRoot: String
    let exclusions: MirrorExclusions
    /// See ``MirrorScope/walkRoots``.
    let walkRoots: [[String]]?
    /// See ``MirrorScope/includedFiles``.
    let includedFiles: [[String]]
    /// See ``MirrorScope/isUnderPrivate``.
    let isUnderPrivate: Bool
    private let outsideEntryLimit: Int

    private(set) var linkedFolders: Set<String> = []
    /// Files outside the workspace that file links point at.
    private(set) var linkedFiles: Set<String> = []
    /// Links, by path, that point at a folder holding one being walked: following one leads
    /// back round for ever, and SwiftLint walking one with `excluded` set recurses until it
    /// crashes. A link may do so only on a route SwiftLint never walks, or one an exclusion
    /// keeps it off, and lead somewhere new on one it walks; it isn't one then.
    private(set) var cyclicLinks: Set<String> = []
    /// Links SwiftLint goes through on the way to an `included` entry it lints without walking
    /// what lies behind the link (see ``isOnTheWayToUnwalkedEntry(_:)``): just once, so the
    /// mirror keeps them, though they lead back round where SwiftLint doesn't go.
    private(set) var linksOnTheWay: Set<String> = []
    /// Links SwiftLint follows without coming back round: on a route it walks, or on the way to
    /// a walk an `included` entry starts beyond the link.
    private var followedLinks: Set<String> = []
    private var visited: Set<String> = []
    /// Folders outside the workspace whose entries count toward ``outsideEntryLimit``: the
    /// mirror copies each once, however many routes lead there.
    private var countedOutside: Set<String> = []
    private var walking: [Folder] = []
    private var outsideEntries = 0
    private var firstOutsideLink: (link: String, target: String)?

    init(
        fileManager: FileManager,
        reach: MirrorLinkReach,
        workspaceRoot: String,
        exclusions: MirrorExclusions = MirrorExclusions(patterns: []),
        walkRoots: [[String]]? = nil,
        includedFiles: [[String]] = [],
        isUnderPrivate: Bool = false,
        outsideEntryLimit: Int = Self.outsideEntryLimit
    ) {
        self.fileManager = fileManager
        self.reach = reach
        self.workspaceRoot = workspaceRoot
        self.exclusions = exclusions
        self.walkRoots = walkRoots
        self.includedFiles = includedFiles
        self.isUnderPrivate = isUnderPrivate
        self.outsideEntryLimit = outsideEntryLimit
    }

    /// A folder being walked.
    private struct Folder {
        /// Its real path.
        let path: String
        /// Where SwiftLint sees it, relative to the workspace.
        let seenAt: String
        /// A link led into it.
        let isLinkTarget: Bool
        /// Under `/private`, SwiftLint listing the folder above skips this one for an exclusion;
        /// see ``isKeptOut(by:toward:)``.
        let isExcluded: Bool

        /// How many folders below the workspace SwiftLint sees it.
        var depth: Int { seenAt.split(separator: "/").count }
    }

    /// Walks `folder`, which SwiftLint sees at `path` relative to the workspace.
    mutating func explore(_ folder: URL, at path: String) throws {
        try explore(folder, at: path, isLinkTarget: false)
    }

    /// Follows the symlink to a folder at `link`, which SwiftLint sees at `path` relative to the
    /// workspace, and walks what it points at.
    mutating func follow(linkAt link: URL, seenAt path: String) throws {
        let target = link.resolvingSymlinksInPath()
        let entry = MirrorDirectoryEntry(url: link, name: link.lastPathComponent, kind: .folderLink(target))
        try follow(entry, to: target, at: path)
    }

    private mutating func explore(_ folder: URL, at path: String, isLinkTarget: Bool) throws {
        try Task.checkCancellation()
        let current = Folder(
            path: folder.path,
            seenAt: path,
            isLinkTarget: isLinkTarget,
            isExcluded: isUnderPrivate && !isLinkTarget && exclusions.excludes(folder.path)
                && Self.isMatchedAsSpelled(folder)
        )
        let route = walking + [current]
        // Following every link, a real folder is walked once — twice at most: once where
        // SwiftLint walks (see ``MirrorScope/walkRoots``), and an exclusion doesn't keep it out,
        // and once where it doesn't, as a loop matters only in the first. A walk starting below
        // decides for itself what lies there, and a `.swift` entry below needs every link on the
        // way, so a folder on the way to either is walked once per path. Following only the way
        // to the `included` entries, a folder reached by two paths may lead toward an entry by
        // only one of them, so it is walked once per path too; the reach keeps that narrow.
        let key = reach == .everyLink
            ? folder.path + (isWalked(path) && !isKeptOut(by: route, toward: path) ? "\u{0}walked" : "")
                + (hasWalkStart(below: path) || leadsToIncludedFile(path) ? "\u{0}" + path : "")
            : folder.path + "\u{0}" + path
        guard visited.insert(key).inserted else { return }
        walking = route
        defer { walking.removeLast() }

        let entries = MirrorDirectoryEntry.list(folder, fileManager: fileManager)
        if !MirrorRegions.isInside(folder.path, workspaceRoot), countedOutside.insert(folder.path).inserted {
            outsideEntries += entries.count
            if outsideEntries > outsideEntryLimit {
                throw MirrorTooLargeError(
                    limit: outsideEntryLimit,
                    link: firstOutsideLink?.link,
                    target: firstOutsideLink?.target ?? folder.path
                )
            }
        }

        for entry in entries {
            let entryPath = path.isEmpty ? entry.name : path + "/" + entry.name
            switch entry.kind {
            case .folder:
                if reach.mayHoldReachableLinks(entryPath) {
                    try explore(entry.url, at: entryPath)
                }
            case .folderLink(let target):
                try follow(entry, to: target, at: entryPath)
            case .fileLink(let target):
                if !MirrorRegions.isInside(target.path, workspaceRoot) {
                    linkedFiles.insert(target.path)
                }
            case .file:
                continue
            }
        }
    }

    private mutating func follow(_ link: MirrorDirectoryEntry, to target: URL, at linkPath: String) throws {
        guard reach.follows(linkAt: linkPath) else { return }
        if isOnTheWayToUnwalkedEntry(linkPath) {
            linksOnTheWay.insert(link.url.path)
        }
        if walking.contains(where: { MirrorRegions.isInside($0.path, target.path) }) {
            try closeLoop(link, to: target, at: linkPath)
            return
        }
        if reach == .everyLink, hasWalkStart(below: linkPath)
            || (isWalked(linkPath) && !isExcluded(link.url.path, target: target.path, at: linkPath)) {
            followedLinks.insert(link.url.path)
            cyclicLinks.remove(link.url.path)
        }
        linkedFolders.insert(target.path)
        if firstOutsideLink == nil, !MirrorRegions.isInside(target.path, workspaceRoot) {
            firstOutsideLink = (linkPath, target.path)
        }
        try explore(target, at: linkPath, isLinkTarget: true)
    }

    /// Records the link at `linkPath` to `target`, which points back into a folder being walked,
    /// or throws when the mirror can't reproduce what SwiftLint makes of it.
    private mutating func closeLoop(_ link: MirrorDirectoryEntry, to target: URL, at linkPath: String) throws {
        if !followedLinks.contains(link.url.path) {
            cyclicLinks.insert(link.url.path)
        }
        // The mirror leaves the link out. Following every link, SwiftLint resolves it and
        // walks the folder again, and again, until it crashes — if it walks where the link
        // is and no exclusion keeps it out — so the mirror would measure a workspace
        // SwiftLint can't lint. Following only the way to an `included` entry, SwiftLint
        // goes through it once, and the mirror keeps it (see ``linksOnTheWay``).
        guard reach == .everyLink else { return }
        // The mirror writes each `excluded` entry to name its place there, so an exclusion that
        // keeps SwiftLint off the link here keeps it off in the mirror too.
        if isWalked(linkPath), !isExcluded(link.url.path, target: target.path, at: linkPath) {
            throw MirrorUnsupportedSetupError(
                reason: "SwiftLint follows the symlink at \(linkPath) back into a folder that holds it, round "
                    + "and round until it crashes. " + loopAdvice(forLinkAt: linkPath)
            )
        }
        // A walk an `included` entry starts beyond the link begins in the folder it points
        // at, which holds the link: no exclusion above it keeps that walk out.
        guard hasWalkStart(below: linkPath) else { return }
        throw Self.includedThroughLoop(at: linkPath)
    }

    /// Whether SwiftLint goes through the link at `linkPath`, which it may follow, on the way to
    /// an `included` entry it lints without walking what lies behind the link. Following only
    /// the way to the entries, that is any: `subpaths` goes into no link inside one. Following
    /// every link, one naming `.swift` files, which it lints where they are; `**` goes into no
    /// link either.
    private func isOnTheWayToUnwalkedEntry(_ linkPath: String) -> Bool {
        reach == .everyLink ? leadsToIncludedFile(linkPath) : true
    }

    /// Whether an `included` entry naming `.swift` files lies past `path`.
    private func leadsToIncludedFile(_ path: String) -> Bool {
        let depth = path.split(separator: "/").count
        return includedFiles.contains { entry in
            entry.count > depth && MirrorLinkReach.towardIncluded([entry]).follows(linkAt: path)
        }
    }

    private static func includedThroughLoop(at linkPath: String) -> MirrorUnsupportedSetupError {
        MirrorUnsupportedSetupError(
            reason: "An `included` entry runs through the symlink at \(linkPath), which points back into a "
                + "folder that holds it."
        )
    }

    /// Whether an exclusion keeps SwiftLint from walking into the link at `path` to `target`,
    /// which it sees at `linkPath`. Under `/private` neither the link nor the folder behind it
    /// does: SwiftLint matches those with `/private` dropped against patterns that keep it. A
    /// folder on the way to the link may, though; see ``isKeptOut(by:toward:)``.
    private func isExcluded(_ path: String, target: String, at linkPath: String) -> Bool {
        guard isUnderPrivate else { return exclusions.excludes(path) || exclusions.excludes(target) }
        return isKeptOut(by: walking, toward: linkPath)
    }

    /// Under `/private`, whether an exclusion keeps SwiftLint off `route` before it gets to
    /// `path`, at the end of it. SwiftLint matches each entry of a folder it lists by the path
    /// the listing gives, the real one, which keeps `/private` as the patterns do. So it skips an
    /// excluded folder on the way, unless that folder is where its walk starts, which it never
    /// matches, or one a link led into, which it matches with `/private` dropped. Nor does it
    /// skip one it matches by any path but the one here (see ``isMatchedAsSpelled(_:)``).
    private func isKeptOut(by route: [Folder], toward path: String) -> Bool {
        guard isUnderPrivate, let start = walkStartDepth(of: path) else { return false }
        return route.contains { $0.isExcluded && $0.depth > start }
    }

    /// How deep below the workspace the walk that reaches `path` starts, or nil when that can't
    /// be told; see ``MirrorLinkReach/walkStartDepth(of:in:)``.
    private func walkStartDepth(of path: String) -> Int? {
        guard let walkRoots else { return 0 }
        return MirrorLinkReach.walkStartDepth(of: path, in: walkRoots)
    }

    /// Whether a walk SwiftLint makes starts below `path`: an `included` entry lies past it.
    private func hasWalkStart(below path: String) -> Bool {
        let depth = path.split(separator: "/").count
        return walkRoots?.contains { entry in
            entry.count > depth && MirrorLinkReach.towardIncluded([entry]).follows(linkAt: path)
        } ?? false
    }

    /// Under `/private`, whether SwiftLint matches `folder` against the patterns as `folder`'s
    /// path, `/private` in front: its real path must be that, with no link part way along it,
    /// and must hold no character SwiftLint's matcher miscounts. It measures the path in
    /// characters but matches it as UTF-16, so one that takes two units cuts the match short.
    private static func isMatchedAsSpelled(_ folder: URL) -> Bool {
        let path = folder.path
        guard path.count == path.utf16.count, let real = realpath(path, nil) else { return false }
        defer { free(real) }
        return String(cString: real) == "/private" + path
    }

    /// How to keep SwiftLint out of the looping link SwiftLint sees at `linkPath`. Under
    /// `/private` an exclusion naming the link doesn't (see ``isExcluded(_:target:at:)``): one
    /// naming a folder on the way to it, which SwiftLint lists from the workspace, does.
    private func loopAdvice(forLinkAt linkPath: String) -> String {
        guard isUnderPrivate else { return "Add it to `excluded` and SwiftLint skips it." }
        let skipsNoLink = "In a workspace under /tmp or /var, SwiftLint doesn't skip a symlink `excluded` names: "
        // Named as written in `excluded`, the folder must be matched by that path, not as a glob.
        let holder = walkStartDepth(of: linkPath).flatMap { start in
            walking.last { folder in
                !folder.isLinkTarget && folder.depth > start && folder.path == workspaceRoot + "/" + folder.seenAt
                    && folder.seenAt.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[")) == nil
                    && Self.isMatchedAsSpelled(URL(fileURLWithPath: folder.path))
            }
        }
        guard let holder else { return skipsNoLink + "remove the link." }
        let which = holder.path == walking.last?.path ? "the folder that holds it" : "a folder on the way to it"
        return skipsNoLink + "exclude \(holder.seenAt), \(which), or remove the link."
    }

    /// Whether SwiftLint, following every link, walks where `path` (relative to the workspace) is.
    private func isWalked(_ path: String) -> Bool {
        walkRoots.map { MirrorLinkReach.isWithin(path, anyOf: $0) } ?? true
    }
}
