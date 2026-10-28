//
//  WorkspaceMirrorPlan.swift
//  SwiftLintRuleStudio
//
//  What a rule simulation's mirror of a workspace holds, symlinks included.
//

import Foundation

/// What a simulation mirror holds: the `.swift` files to hardlink, the `.swiftlint.yml` files
/// to rewrite, and the symlinks to recreate.
///
/// The mirror must make SwiftLint lint exactly the files it lints in the real workspace, and
/// how SwiftLint treats a symlink depends on the configuration in ways no short rule captures.
/// With no `excluded`, it lists files with `subpaths(atPath:)`, which follows an `included`
/// entry that is a link but no link inside one. With `excluded`, it resolves every link it
/// meets, reports the files behind it at their real paths (so an exclusion written under the
/// link's path never reaches them), and drops a file it reaches twice; yet an `included` entry
/// that is itself a link yields nothing. Globs, `**` above all, expand differently again. The
/// mirror once turned followed links into real folders, and each of those broke in turn.
///
/// So the mirror keeps links as links, and lets SwiftLint decide. A link to a folder in the
/// workspace points at that folder's mirror. A link to a folder outside the workspace points at
/// a mirror of that folder outside the lint root, as the real one is outside the workspace, so
/// SwiftLint reaches it only through the link; the configs in it are rewritten like any other.
/// One in the folder holding the workspace keeps its own place beside the lint root — the
/// container stands for that folder — with the configs between it and the container, so `../`
/// paths and config lookups mean the same in the mirror; one further out goes in the
/// container's outside folder, beside the nearest config above it. A link to a file outside the
/// workspace points at a copy of just that file, placed the same way. ``MirrorLinkReach`` keeps
/// the walk to the links SwiftLint can follow; ``MirrorRegions`` decides the places.
///
/// Where it can't be exact the plan leans toward including: a file missing from the mirror
/// measures 0, which reads as "safe to enable", while an extra one only over-counts. Where it
/// can't reproduce a setup at all it refuses (``MirrorUnsupportedSetupError``), so the
/// simulation fails rather than guess. Left out on purpose: links that close a cycle. SwiftLint
/// walking one with `excluded` set follows it until it crashes — in-process, the app — so where
/// it would, and nothing excludes it, the plan refuses the workspace instead.
nonisolated struct WorkspaceMirrorPlan: Sendable {
    /// A real file and its place in the mirror.
    struct File: Equatable, Sendable {
        let source: URL
        /// Relative to the mirror's container, which holds the lint root at ``lintRoot``.
        let path: String
    }

    /// A symlink to recreate.
    struct Link: Equatable, Sendable {
        /// Relative to the mirror's container.
        let path: String
        /// Relative to the link's folder, so it survives the container being moved.
        let destination: String
    }

    /// A folder outside the workspace that links point into, and where its mirror is.
    struct ExternalFolder: Equatable, Sendable {
        let original: URL
        /// Relative to the mirror's container.
        let path: String
    }

    /// The folder the mirror's container stands for; see ``MirrorScope/anchor``.
    private(set) var anchor = ""
    /// The lint root's path in the mirror's container: the workspace folder's own name.
    private(set) var lintRoot = ""
    private(set) var sources: [File] = []
    private(set) var configs: [File] = []
    private(set) var links: [Link] = []
    /// Folders outside the workspace mirrored in the container — beside the lint root or in its
    /// outside folder — so a path SwiftLint reports in one can be put back at the real one.
    private(set) var externalFolders: [ExternalFolder] = []
    /// Every folder a link points at, so a link to a folder with nothing to mirror still resolves.
    private(set) var linkedFolderPaths: [String] = []
    /// Where the configs the root config pulls in are, relative to the container.
    private(set) var referencedConfigPaths: Set<String> = []
    /// Whether SwiftLint, looking for some file's nested config, may climb out of the mirror's
    /// container — and so find a config above it that nothing in the workspace sees.
    private(set) var climbsPastContainer = false

    private var placedSourcePaths: Set<String> = []
    private var outsideEntries = 0
    private var outsideEntryLimit = MirrorLinkDiscovery.outsideEntryLimit

    /// The plan for mirroring the workspace `scope` describes.
    ///
    /// Synchronous and slow on a large tree, so call it off the main actor. It stops with
    /// `CancellationError` when the task running it is cancelled, with ``MirrorTooLargeError``
    /// when it would copy more from outside the workspace than the limit, and with
    /// ``MirrorUnsupportedSetupError`` when it can't reproduce the workspace's configs.
    static func make(
        for scope: MirrorScope,
        outsideEntryLimit: Int = MirrorLinkDiscovery.outsideEntryLimit,
        fileManager: FileManager = .default
    ) throws -> Self {
        let discovery = try discover(scope, outsideEntryLimit: outsideEntryLimit, fileManager: fileManager)
        let regions = MirrorRegions(
            scope: scope,
            linkedFolders: discovery.linkedFolders,
            linkedFiles: discovery.linkedFiles
        )
        var plan = Self()
        plan.anchor = scope.anchor
        plan.lintRoot = scope.lintRoot
        plan.outsideEntryLimit = outsideEntryLimit
        plan.configs = scope.referencedConfigs
        plan.referencedConfigPaths = Set(scope.referencedConfigs.map(\.path))
        try plan.placeConfigsAbove(regions, scope: scope, fileManager: fileManager)
        for fileRegion in regions.fileRegions {
            let original = URL(fileURLWithPath: fileRegion.region.real)
            plan.externalFolders.append(ExternalFolder(original: original, path: fileRegion.region.mirror))
            plan.placeFiles(of: fileRegion, skipping: scope.configGraph, fileManager: fileManager)
        }
        try plan.place(
            URL(fileURLWithPath: regions.workspace.real),
            at: regions.workspace.mirror,
            regions: regions,
            discovery: discovery,
            counted: false
        )
        for region in regions.beside + regions.externals {
            try plan.place(URL(fileURLWithPath: region.real), at: region.mirror, regions: regions, discovery: discovery)
        }
        try plan.placeHostedLinks(scope, regions: regions)
        try plan.checkConfigsAboveDontLeak(regions, scope: scope)
        var seen: Set<String> = []
        plan.configs = plan.configs.filter { seen.insert($0.path).inserted }.sorted { $0.path < $1.path }
        return plan
    }

    /// Mirrors the configs SwiftLint finds above the folders the mirror copies from outside the
    /// workspace. It looks for a file's nested config from its real folder up to `/`, passing over
    /// the configs that make up the configuration, so:
    /// - beside each folder in the outside folder, the nearest config above it;
    /// - for folders at their own places beside the lint root, the configs between them and the
    ///   workspace's folder, at their own places too, and at the container — which stands for
    ///   that folder — the nearest config at or above it.
    ///
    /// A workspace under `/private` gets that last one too: there SwiftLint climbs out of the
    /// workspace for the files in it as well (see ``SimulationWorkspaceBuilder``), as it climbs
    /// out of the mirror's lint root, under `/private` with it.
    private mutating func placeConfigsAbove(
        _ regions: MirrorRegions,
        scope: MirrorScope,
        fileManager: FileManager
    ) throws {
        let graph = scope.configGraph
        for external in regions.externals {
            let original = URL(fileURLWithPath: external.real)
            externalFolders.append(ExternalFolder(original: original, path: external.mirror))
            let folder = original.deletingLastPathComponent()
            if let above = Self.nearestConfig(from: folder, fileManager: fileManager, skipping: graph) {
                let path = Self.outsideFolder(of: external.mirror) + "/" + ConfigTreeDiscovery.configFileName
                configs.append(File(source: above, path: path))
            }
        }
        for beside in regions.beside {
            let original = URL(fileURLWithPath: beside.real)
            externalFolders.append(ExternalFolder(original: original, path: beside.mirror))
            placeConfigsBetween(original.deletingLastPathComponent(), scope: scope, fileManager: fileManager)
        }
        let besideFiles = regions.fileRegions.filter(\.isBeside)
        for fileRegion in besideFiles {
            placeConfigsBetween(URL(fileURLWithPath: fileRegion.region.real), scope: scope, fileManager: fileManager)
        }
        if scope.isUnderPrivate {
            // The files in the workspace climb out of it too, through the folders up to the anchor.
            let workspaceParent = URL(fileURLWithPath: scope.workspaceRoot).deletingLastPathComponent()
            placeConfigsBetween(workspaceParent, scope: scope, fileManager: fileManager)
        }
        let anchor = URL(fileURLWithPath: scope.anchor)
        guard !regions.beside.isEmpty || !besideFiles.isEmpty || scope.isUnderPrivate,
              let above = Self.nearestConfig(from: anchor, fileManager: fileManager, skipping: graph)
        else { return }
        if let referenced = configs.first(where: { $0.path == ConfigTreeDiscovery.configFileName }) {
            throw MirrorUnsupportedSetupError(
                reason: "The configuration pulls in \(referenced.source.path), and SwiftLint also applies "
                    + "\(above.path) to the files beside the workspace; one copy can't hold both."
            )
        }
        configs.append(File(source: above, path: ConfigTreeDiscovery.configFileName))
    }

    /// Mirrors, at their own places, the configs from `folder` up to the anchor, exclusive —
    /// those SwiftLint may find above a folder beside the workspace.
    private mutating func placeConfigsBetween(_ folder: URL, scope: MirrorScope, fileManager: FileManager) {
        var current = folder
        while let mirror = MirrorRegions.placeInContainer(of: current.path, in: scope) {
            let config = current.appendingPathComponent(ConfigTreeDiscovery.configFileName)
            if fileManager.fileExists(atPath: config.path),
               !scope.configGraph.contains(config.resolvingSymlinksInPath().path) {
                configs.append(File(source: config, path: mirror + "/" + ConfigTreeDiscovery.configFileName))
            }
            current = current.deletingLastPathComponent()
        }
    }

    /// The folder in the outside folder holding the copy at `mirror` (`…/<n>/tree`).
    private static func outsideFolder(of mirror: String) -> String {
        mirror.hasSuffix("/tree") ? String(mirror.dropLast("/tree".count)) : mirror
    }

    /// A config at the container stands for the one at or above the workspace's folder, but
    /// the outside copies sit inside the container too, so SwiftLint looking up from one with
    /// no config above it of its own would find that one — which the real folder never sees.
    ///
    /// It also works out ``climbsPastContainer``: whether a lookup can get out of the container
    /// without meeting a config that stops it — one the configuration doesn't already include.
    private mutating func checkConfigsAboveDontLeak(_ regions: MirrorRegions, scope: MirrorScope) throws {
        let containerConfig = configs.first { $0.path == ConfigTreeDiscovery.configFileName }
        let stopsLookups = containerConfig.map { !scope.referencedConfigs.contains($0) } ?? false
        let outsideRoots = regions.externals.map(\.mirror)
            + regions.fileRegions.filter { !$0.isBeside }.map(\.region.mirror)
        let unguarded = outsideRoots.filter { root in
            !configs.contains { $0.path == Self.outsideFolder(of: root) + "/" + ConfigTreeDiscovery.configFileName }
                && !configs.contains { $0.path == root + "/" + ConfigTreeDiscovery.configFileName }
        }
        let reachesContainer = !regions.beside.isEmpty || regions.fileRegions.contains(where: \.isBeside)
        if stopsLookups, !unguarded.isEmpty {
            throw MirrorUnsupportedSetupError(
                reason: "The workspace's configuration reaches beside the workspace, and its links lead to "
                    + "folders with no configuration above them; both can't be reproduced in one copy."
            )
        }
        climbsPastContainer = !stopsLookups && (scope.isUnderPrivate || !unguarded.isEmpty || reachesContainer)
    }

    // MARK: - Placing

    /// Places `folder`'s entries at `mirrorPath`. Entries of a folder outside the workspace
    /// are `counted` against the limit: they are what the mirror copies on the workspace's
    /// behalf.
    private mutating func place(
        _ folder: URL,
        at mirrorPath: String,
        regions: MirrorRegions,
        discovery: MirrorLinkDiscovery,
        counted: Bool = true
    ) throws {
        try Task.checkCancellation()
        let entries = MirrorDirectoryEntry.list(folder, fileManager: discovery.fileManager)
        if counted {
            outsideEntries += entries.count
            if outsideEntries > outsideEntryLimit {
                throw MirrorTooLargeError(limit: outsideEntryLimit, link: nil, target: folder.path)
            }
        }
        for entry in entries {
            let entryMirrorPath = mirrorPath + "/" + entry.name
            switch entry.kind {
            case .folder:
                try place(entry.url, at: entryMirrorPath, regions: regions, discovery: discovery, counted: counted)
            case .file:
                record(entry.url, at: entryMirrorPath)
            case .folderLink(let target):
                // A link SwiftLint can't follow, into a folder outside every mirrored one, has
                // nowhere to point; it isn't linted in the workspace either. A link back into a
                // folder holding it is a cycle, whether or not the walk got that far — unless
                // SwiftLint only goes through it on the way to an `included` entry.
                guard discovery.linksOnTheWay.contains(entry.url.path)
                        || (!discovery.cyclicLinks.contains(entry.url.path)
                            && !MirrorRegions.isInside(folder.path, target.path)),
                      let targetMirrorPath = regions.mirrorPath(of: target.path) else { continue }
                let destination = Self.linkDestination(from: mirrorPath, to: targetMirrorPath)
                links.append(Link(path: entryMirrorPath, destination: destination))
                linkedFolderPaths.append(targetMirrorPath)
            case .fileLink(let target):
                placeFileLink(entry, target: target, at: entryMirrorPath, in: mirrorPath, regions: regions)
            }
        }
    }

    /// Recreates the links on the way to the folders `included` entries name beside the
    /// workspace (see ``MirrorScope/hostedLinks``), each pointing at the mirror of its target.
    private mutating func placeHostedLinks(_ scope: MirrorScope, regions: MirrorRegions) throws {
        for link in scope.hostedLinks {
            let target = URL(fileURLWithPath: link).resolvingSymlinksInPath().path
            guard let place = MirrorRegions.besidePath(of: link, in: scope),
                  let targetMirrorPath = regions.mirrorPath(of: target) else {
                throw MirrorUnsupportedSetupError(
                    reason: "The configuration's `included` runs through the symlink at \(link) to \(target), "
                        + "which a copy of the workspace can't hold where SwiftLint finds it."
                )
            }
            // A link in a folder the mirror holds anyway is there already.
            guard !links.contains(where: { $0.path == place }) else { continue }
            let folder = place.split(separator: "/").dropLast().joined(separator: "/")
            links.append(Link(path: place, destination: Self.linkDestination(from: folder, to: targetMirrorPath)))
            linkedFolderPaths.append(targetMirrorPath)
        }
    }

    private mutating func placeFileLink(
        _ entry: MirrorDirectoryEntry,
        target: URL,
        at entryMirrorPath: String,
        in folderMirrorPath: String,
        regions: MirrorRegions
    ) {
        // SwiftLint reads a nested config through a link, whatever it excludes.
        if entry.name == ConfigTreeDiscovery.configFileName {
            configs.append(File(source: target, path: entryMirrorPath))
            return
        }
        guard entry.name.hasSuffix(".swift") || target.pathExtension == "swift" else { return }
        if let targetMirrorPath = regions.mirrorPath(of: target.path), regions.isMirrored(file: target.path) {
            let destination = Self.linkDestination(from: folderMirrorPath, to: targetMirrorPath)
            links.append(Link(path: entryMirrorPath, destination: destination))
        } else {
            // The target won't be in the mirror — it isn't a `.swift` file — so mirror a copy
            // where the link is, which is where SwiftLint lints it without `excluded`. With
            // `excluded`, only the nested config it gets could differ.
            sources.append(File(source: target, path: entryMirrorPath))
        }
    }

    /// Copies the outside files that file links point at into their folder's mirror. One in the
    /// outside folder gets the nearest config at or above that folder — the one SwiftLint gives
    /// them when it lints them at their real path; one beside the lint root has the configs
    /// between it and the container placed already.
    private mutating func placeFiles(
        of fileRegion: MirrorRegions.FileRegion,
        skipping graph: Set<String>,
        fileManager: FileManager
    ) {
        let folder = URL(fileURLWithPath: fileRegion.region.real)
        for file in fileRegion.files {
            let name = URL(fileURLWithPath: file).lastPathComponent
            sources.append(File(source: URL(fileURLWithPath: file), path: fileRegion.region.mirror + "/" + name))
        }
        guard !fileRegion.isBeside else { return }
        if let config = Self.nearestConfig(from: folder, fileManager: fileManager, skipping: graph) {
            let path = fileRegion.region.mirror + "/" + ConfigTreeDiscovery.configFileName
            configs.append(File(source: config, path: path))
        }
    }

    private mutating func record(_ file: URL, at mirrorPath: String) {
        if file.pathExtension == "swift" {
            guard placedSourcePaths.insert(mirrorPath).inserted else { return }
            sources.append(File(source: file, path: mirrorPath))
        } else if file.lastPathComponent == ConfigTreeDiscovery.configFileName {
            configs.append(File(source: file, path: mirrorPath))
        }
    }
}
