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
    /// See ``MirrorScope/isUnderPrivate``.
    let isUnderPrivate: Bool
    private let outsideEntryLimit: Int

    private(set) var linkedFolders: Set<String> = []
    /// Files outside the workspace that file links point at.
    private(set) var linkedFiles: Set<String> = []
    /// Links, by path, that point at a folder holding one being walked: following one leads
    /// back round for ever, and SwiftLint walking one with `excluded` set recurses until it
    /// crashes.
    private(set) var cyclicLinks: Set<String> = []
    private var visited: Set<String> = []
    private var walking: [String] = []
    private var outsideEntries = 0
    private var firstOutsideLink: (link: String, target: String)?

    init(
        fileManager: FileManager,
        reach: MirrorLinkReach,
        workspaceRoot: String,
        exclusions: MirrorExclusions = MirrorExclusions(patterns: []),
        walkRoots: [[String]]? = nil,
        isUnderPrivate: Bool = false,
        outsideEntryLimit: Int = Self.outsideEntryLimit
    ) {
        self.fileManager = fileManager
        self.reach = reach
        self.workspaceRoot = workspaceRoot
        self.exclusions = exclusions
        self.walkRoots = walkRoots
        self.isUnderPrivate = isUnderPrivate
        self.outsideEntryLimit = outsideEntryLimit
    }

    /// Walks `folder`, which SwiftLint sees at `path` relative to the workspace.
    mutating func explore(_ folder: URL, at path: String) throws {
        try Task.checkCancellation()
        // Following every link, a real folder is walked once — twice at most: once where
        // SwiftLint walks (see ``MirrorScope/walkRoots``) and once where it doesn't, as a loop
        // matters only in the first. Following only the way to the `included` entries, a folder
        // reached by two paths may lead toward an entry by only one of them, so it is walked
        // once per path; the reach keeps that narrow.
        let key = reach == .everyLink
            ? folder.path + (isWalked(path) ? "\u{0}walked" : "")
            : folder.path + "\u{0}" + path
        guard visited.insert(key).inserted else { return }
        walking.append(folder.path)
        defer { walking.removeLast() }

        let entries = MirrorDirectoryEntry.list(folder, fileManager: fileManager)
        if !MirrorRegions.isInside(folder.path, workspaceRoot) {
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
        if walking.contains(where: { MirrorRegions.isInside($0, target.path) }) {
            cyclicLinks.insert(link.url.path)
            // The mirror leaves the link out. Following every link, SwiftLint resolves it and
            // walks the folder again, and again, until it crashes — if it walks where the link
            // is and no exclusion keeps it out — so the mirror would measure a workspace
            // SwiftLint can't lint. Following only the way to an `included` entry, SwiftLint
            // goes through it once, and the mirror without it would lint less.
            switch reach {
            case .everyLink:
                guard isWalked(linkPath), !isExcluded(link.url.path, target: target.path) else { return }
                throw MirrorUnsupportedSetupError(
                    reason: "SwiftLint follows the symlink at \(linkPath) back into a folder that holds it, round "
                        + "and round until it crashes. Add it to `excluded` and SwiftLint skips it."
                )
            case .towardIncluded:
                throw MirrorUnsupportedSetupError(
                    reason: "An `included` entry runs through the symlink at \(linkPath), which points back into a "
                        + "folder that holds it."
                )
            }
        }
        linkedFolders.insert(target.path)
        if firstOutsideLink == nil, !MirrorRegions.isInside(target.path, workspaceRoot) {
            firstOutsideLink = (linkPath, target.path)
        }
        try explore(target, at: linkPath)
    }

    /// Whether SwiftLint skips the link at `path` to `target` for an exclusion. Under `/private`
    /// it never does: there it matches a link's path, and the folder behind it, with `/private`
    /// dropped against patterns that keep it.
    private func isExcluded(_ path: String, target: String) -> Bool {
        !isUnderPrivate && (exclusions.excludes(path) || exclusions.excludes(target))
    }

    /// Whether SwiftLint, following every link, walks where `path` (relative to the workspace) is.
    private func isWalked(_ path: String) -> Bool {
        walkRoots.map { MirrorLinkReach.isWithin(path, anyOf: $0) } ?? true
    }
}
