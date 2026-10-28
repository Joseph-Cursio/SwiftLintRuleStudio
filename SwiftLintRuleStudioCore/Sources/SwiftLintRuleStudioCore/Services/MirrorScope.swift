//
//  MirrorScope.swift
//  SwiftLintRuleStudio
//
//  What a simulation mirror must reach beyond the workspace, from the configs that decide it —
//  or why it can't.
//

import Darwin
import Foundation

/// Accumulates a ``MirrorScope`` while walking the root config and the configs it pulls in,
/// then places what they reach once it knows how far up they climb.
nonisolated private struct MirrorScopeBuilder {
    /// A path a config names, standardized and absolute, and how it was written.
    struct Target {
        let written: String
        let config: String
        let components: [String]

        var path: String { "/" + components.dropFirst().joined(separator: "/") }
    }

    /// One config's own `included` and `excluded`, and its place in the chain SwiftLint merges:
    /// below the configs it pulls in as `parent_config`, above one it pulls in as `child_config`.
    struct Layer {
        let order: Int
        var included: [Target] = []
        var excluded: [String] = []
    }

    struct Placed {
        let anchor: String
        let lintRoot: String
        let included: [[String]]
        let hostedFolders: [String]
        let hostedLinks: [String]
        let referencedConfigs: [WorkspaceMirrorPlan.File]
    }

    /// See ``MirrorScope/walkRoots``, ``MirrorScope/hostedFolders`` and ``MirrorScope/hostedLinks``.
    struct Included {
        var entries: [[String]] = []
        var hostedFolders: [String] = []
        var hostedLinks: [String] = []
    }

    let root: URL
    let rootComponents: [String]
    var configGraph: Set<String> = []
    /// Absolute, as SwiftLint makes them: each config's folder joined with the entry. Once
    /// ``merge()`` has run, what the merged configuration excludes.
    private(set) var excludedPatterns: [String] = []
    /// The merged configuration excludes something.
    var excludesAnything: Bool { !excludedPatterns.isEmpty }
    private var includedTargets: [Target] = []
    private var referencedTargets: [(target: Target, file: URL)] = []
    private var layers: [Layer] = []
    private var visited: Set<String> = []

    init(root: URL) {
        self.root = root
        rootComponents = root.pathComponents
    }

    /// The `excluded` entry `written` in a config read relative to `base`, absolute.
    private func exclusion(_ written: String, base: URL) -> String {
        let (entry, entryBase) = expandingPWD(written, base: base)
        return MirrorPaths.unprivate(MirrorPaths.absolute(entry, base: entryBase.path) ?? entry)
    }

    /// Merges the configs as SwiftLint does, from the furthest parent down to the last child:
    /// each one's `included` entries drop those its parents exclude by the same path, and its
    /// `excluded` entries those they include. So a parent's exclusion of a folder a child
    /// includes keeps nothing out.
    mutating func merge() {
        for layer in layers.sorted(by: { $0.order < $1.order }) {
            let childIncluded = Set(layer.included.map(\.path))
            let childExcluded = Set(layer.excluded)
            includedTargets = includedTargets.filter { !childExcluded.contains($0.path) } + layer.included
            excludedPatterns = excludedPatterns.filter { !childIncluded.contains($0) } + layer.excluded
        }
    }

    mutating func visit(_ config: URL, base: URL, order: Int = 0) throws {
        guard visited.insert(config.standardizedFileURL.path).inserted,
              let keys = RawConfigKeys.read(config) else { return }
        var layer = Layer(order: order, excluded: keys.excluded.map { exclusion($0, base: base) })
        for written in keys.included {
            let (entry, entryBase) = expandingPWD(written, base: base)
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else {
                throw MirrorUnsupportedSetupError(
                    reason: "The configuration's `included` names \(written), an absolute path, which in a copy of "
                        + "the workspace still names the original files. Make it relative to the workspace to simulate."
                )
            }
            let parts = trimmed.split(separator: "/").map(String.init)
            let components = MirrorPaths.standardized(entryBase.pathComponents + parts)
            layer.included.append(Target(written: written, config: config.lastPathComponent, components: components))
        }
        layers.append(layer)
        if let parent = keys.parentConfig {
            try follow(parent, from: config, order: order - 1)
        }
        if let child = keys.childConfig {
            try follow(child, from: config, order: order + 1)
        }
    }

    /// `${PWD}` names the folder SwiftLint runs in — the workspace, and in the mirror the lint
    /// root — whichever config writes it; so an entry starting with it is relative to the
    /// workspace.
    private func expandingPWD(_ entry: String, base: URL) -> (String, URL) {
        guard entry.hasPrefix("${PWD}") else { return (entry, base) }
        let rest = entry.dropFirst("${PWD}".count).drop { $0 == "/" }
        return (rest.isEmpty ? "." : String(rest), root)
    }

    /// Records a `parent_config`/`child_config` the mirror must hold, and walks it; `order` is its
    /// place in the chain SwiftLint merges (see ``Layer``).
    private mutating func follow(_ reference: String, from config: URL, order: Int) throws {
        if reference.hasPrefix("http://") || reference.hasPrefix("https://") {
            // SwiftLint fetches it in the mirror as it does in the workspace, but the mirror
            // can't rewrite it, and it can turn the rule off.
            throw MirrorUnsupportedSetupError(
                reason: "\(config.lastPathComponent) pulls in \(reference), a remote configuration, which can turn "
                    + "rules off where the copy of the workspace can't turn them back on."
            )
        }
        guard !reference.hasPrefix("/"), !reference.hasPrefix("~") else {
            throw MirrorUnsupportedSetupError(
                reason: "\(config.lastPathComponent) pulls in \(reference) by an absolute path, which in a copy of "
                    + "the workspace still names the original, unchanged."
            )
        }
        let file = config.deletingLastPathComponent().appendingPathComponent(reference).standardizedFileURL
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let target = Target(written: reference, config: config.lastPathComponent, components: file.pathComponents)
        referencedTargets.append((target, file))
        configGraph.insert(file.resolvingSymlinksInPath().path)
        try visit(file, base: file.deletingLastPathComponent(), order: order)
    }

    // MARK: - Placing

    /// Picks the anchor — as far up as the furthest path climbs — and places every path there.
    func place() throws -> Placed {
        var climb = 1
        for target in includedTargets + referencedTargets.map(\.target) {
            let levels = rootComponents.count - commonPrefixCount(target.components)
            guard levels <= MirrorScope.maximumClimb else {
                throw MirrorUnsupportedSetupError(
                    reason: "\(target.config) names \(target.written), more than \(MirrorScope.maximumClimb) "
                        + "folders above the workspace."
                )
            }
            climb = max(climb, levels)
        }
        climb = min(climb, rootComponents.count - 1)
        let anchorCount = rootComponents.count - climb
        let anchor = "/" + rootComponents.prefix(anchorCount).dropFirst().joined(separator: "/")
        let lintRoot = rootComponents.dropFirst(anchorCount).joined(separator: "/")
        try checkReserved(lintRoot, written: lintRoot, config: "the workspace")
        // SwiftLint makes each entry a pattern starting with its config's path, where `[` starts a
        // set of characters; the container, elsewhere, takes the anchor's path away.
        if anchor.contains("["), excludesAnything || !includedTargets.isEmpty {
            throw MirrorUnsupportedSetupError(
                reason: "The workspace is in \(anchor), whose path holds a `[`. SwiftLint reads the "
                    + "configuration's `included` and `excluded` entries as patterns starting with that path, where "
                    + "`[` starts a set of characters, so they don't name the folders they're written for."
            )
        }
        // The mirror writes each `excluded` entry to name its place in the container (see
        // ``MirrorPaths/mirroredExclusion(_:base:mirrorBase:anchor:outsideFolders:)``); one
        // starting above the folder the container stands for has none.
        if let above = excludedPatterns.first(where: { MirrorPaths.startsAbove($0, anchor) }) {
            throw MirrorUnsupportedSetupError(
                reason: "The configuration's `excluded` has \(above), which starts above \(anchor), the folder a copy "
                    + "of the workspace stands for."
            )
        }
        let included = try placeIncluded(anchorCount: anchorCount)

        let referenced = try referencedTargets.map { target, file in
            let common = commonPrefixCount(target.components)
            let path = (Array(rootComponents[anchorCount..<common]) + target.components.dropFirst(common))
                .joined(separator: "/")
            try checkReserved(path, written: target.written, config: target.config)
            return WorkspaceMirrorPlan.File(source: file, path: path)
        }
        return Placed(
            anchor: anchor,
            lintRoot: lintRoot,
            included: included.entries,
            hostedFolders: included.hostedFolders,
            hostedLinks: included.hostedLinks,
            referencedConfigs: referenced
        )
    }

    /// The `included` entries as ``MirrorLinkReach`` holds them, and what beside the workspace
    /// the mirror must hold for them.
    private func placeIncluded(anchorCount: Int) throws -> Included {
        var included = Included()
        for target in includedTargets {
            let common = commonPrefixCount(target.components)
            let below = Array(target.components.dropFirst(common))
            included.entries.append(Array(repeating: "..", count: rootComponents.count - common) + below)
            guard common < rootComponents.count else { continue }
            let literal = Array(below.prefix { !MirrorLinkReach.hasGlob($0) })
            guard !literal.isEmpty else {
                throw MirrorUnsupportedSetupError(
                    reason: "The configuration's `included` names \(target.written), a folder holding the workspace, "
                        + "or a pattern over one."
                )
            }
            let base = Array(rootComponents.prefix(common))
            try checkReserved(
                (base + literal).dropFirst(anchorCount).joined(separator: "/"),
                written: target.written,
                config: target.config
            )
            // With `excluded` set SwiftLint lists the folder by its real path, through any link
            // on the way, so the mirror recreates the first such link and holds what it points at
            // where that really is; without, it lists it as written.
            if excludesAnything, let link = MirrorPaths.firstFolderLink(on: literal, under: base) {
                let destination = URL(fileURLWithPath: link).resolvingSymlinksInPath().path
                guard destination == root.path || !MirrorRegions.isInside(root.path, destination) else {
                    throw MirrorUnsupportedSetupError(
                        reason: "\(target.config) names \(target.written) in `included`, through the symlink at "
                            + "\(link) to \(destination), which holds the workspace."
                    )
                }
                if !included.hostedLinks.contains(link) { included.hostedLinks.append(link) }
                continue
            }
            let path = "/" + (base + literal).dropFirst().joined(separator: "/")
            if !included.hostedFolders.contains(path) { included.hostedFolders.append(path) }
        }
        return included
    }

    /// Refuses a path whose first folder in the container is one the container keeps for itself.
    private func checkReserved(_ path: String, written: String, config: String) throws {
        let first = path.split(separator: "/").first.map(String.init) ?? ""
        guard ![MirrorScope.outsideFolderName, MirrorScope.lockFileName].contains(first) else {
            throw MirrorUnsupportedSetupError(
                reason: "\(config) names \(written), under a folder named \(first), which the simulation keeps "
                    + "for itself."
            )
        }
    }

    /// How many leading components `components` shares with the workspace's, ignoring case as
    /// the volumes macOS defaults to do.
    private func commonPrefixCount(_ components: [String]) -> Int {
        zip(components, rootComponents).prefix { $0.caseInsensitiveCompare($1) == .orderedSame }.count
    }

}

/// What the mirror must hold beyond the workspace, worked out from the root config and the
/// configs it pulls in.
///
/// The mirror's container stands for a folder holding the workspace — its anchor: the
/// workspace's parent, or the ancestor as far up as a config climbs, up to
/// ``maximumClimb`` levels. The lint root is the path from the anchor down to the workspace,
/// by the folders' own names, so a path climbing out of the workspace — `included:
/// [../Shared]`, `parent_config: ../../.swiftlint.yml` — lands in the container just as it lands
/// beside the real workspace. Anything it can't place that way (an absolute path, one climbing
/// further, a remote config) is refused with ``MirrorUnsupportedSetupError``.
nonisolated struct MirrorScope: Sendable {
    /// Where the mirrors of folders outside the workspace that links point into are kept, in
    /// the container. Not a name a workspace's neighbour is likely to have.
    static let outsideFolderName = ".swiftlint-rule-studio-outside"
    /// The lock a live mirror holds; see ``MirrorLock``.
    static let lockFileName = ".swiftlint-rule-studio.lock"
    /// How many folders above the workspace a config may reach — a monorepo package opened
    /// alone, pulling in the repository's config, climbs two or three.
    static let maximumClimb = 8

    /// The workspace's real path, resolved.
    let workspaceRoot: String
    /// The folder the container stands for: the workspace's parent, or further up.
    let anchor: String
    /// The lint root's path in the container: the folders from the anchor down to the
    /// workspace, by their own names, so an entry that climbs out and back in by name
    /// (`../App/Sources`) still resolves.
    let lintRoot: String
    let reach: MirrorLinkReach
    /// Where SwiftLint starts its walks when it follows every link: each `included` entry, as
    /// ``MirrorLinkReach/towardIncluded(_:)`` holds them, that names folders and isn't itself a
    /// link — a `.swift` pattern it lints without walking, and from a link it walks nothing — or,
    /// with no `included`, the whole workspace (nil).
    let walkRoots: [[String]]?
    /// The `included` entries naming `.swift` files, as ``walkRoots`` holds the rest: SwiftLint
    /// lints them without walking, so it goes through a link on the way to one just once.
    let includedFiles: [[String]]
    /// Folders outside the workspace that `included` entries name, by real path.
    let hostedFolders: [String]
    /// The first symlink to a folder on the way to each folder outside the workspace an
    /// `included` entry names, when a config excludes something. SwiftLint then lists that folder
    /// by its real path, matching exclusions there and reaching it once however many routes lead
    /// there; so the mirror recreates the link and holds what it points at, where that really
    /// is, rather than the folder where the entry spells it.
    let hostedLinks: [String]
    /// The configs the root config pulls in through `parent_config` or `child_config`, where
    /// SwiftLint will look for them; paths relative to the container.
    let referencedConfigs: [WorkspaceMirrorPlan.File]
    /// The root config and the configs it pulls in, by resolved path. SwiftLint looking for a
    /// file's nested config passes over these, as they already make up the configuration.
    let configGraph: Set<String>
    /// What the root config and the configs it pulls in exclude. SwiftLint applies it in the
    /// mirror too: the mirror writes each entry to name its place there (see
    /// ``MirrorPaths/mirroredExclusion(_:base:mirrorBase:anchor:outsideFolders:)``), and one that
    /// can have none stops the simulation.
    let exclusions: MirrorExclusions
    /// Whether the workspace lies under `/private`, as `/tmp` and `/var` do. SwiftLint reads a
    /// path there under two spellings, which changes what it does; see
    /// ``SimulationWorkspaceBuilder``.
    let isUnderPrivate: Bool

    /// The scope for mirroring the workspace at `workspaceRoot`, whose root config is
    /// `rootConfig` — the workspace's own, or the seed the mirror's root will get; either is
    /// read relative to the workspace, as it will be in the mirror.
    static func make(workspaceRoot: URL, rootConfig: URL?) throws -> Self {
        if isSymlink(workspaceRoot) {
            throw MirrorUnsupportedSetupError(
                reason: "The workspace is open at \(workspaceRoot.path), a symlink. SwiftLint linting a symlink "
                    + "finds files and configurations differently — with `excluded` set, none at all. Open "
                    + "\(workspaceRoot.resolvingSymlinksInPath().path) instead to simulate."
            )
        }
        let root = workspaceRoot.resolvingSymlinksInPath().standardizedFileURL
        let isUnderPrivate = isUnderPrivate(workspaceRoot)
        if isUnderPrivate, workspaceRoot.standardizedFileURL.path != root.path {
            throw MirrorUnsupportedSetupError(
                reason: "The workspace is open at \(workspaceRoot.path), through a symlink, under /private as /tmp "
                    + "and /var are. SwiftLint reads paths there two ways, and through the link which configurations "
                    + "it uses changes again. Open \(root.path) instead to simulate."
            )
        }
        var builder = MirrorScopeBuilder(root: root)
        // Its folder resolved like the root's, so what it pulls in compares with the root; the
        // file itself not, as a config that is a link still reads paths from where it is.
        if let rootConfig = rootConfig.map({
            $0.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent($0.lastPathComponent)
        }) {
            builder.configGraph.insert(rootConfig.resolvingSymlinksInPath().path)
            try builder.visit(rootConfig, base: root)
        }
        builder.merge()
        let placed = try builder.place()
        return Self(
            workspaceRoot: root.path,
            anchor: placed.anchor,
            lintRoot: placed.lintRoot,
            reach: builder.excludesAnything ? .everyLink : .towardIncluded(placed.included),
            walkRoots: placed.included.isEmpty ? nil : placed.included.filter { entry in
                !(entry.last ?? "").hasSuffix(".swift") && !isLink(entry, root: root)
            },
            includedFiles: placed.included.filter { ($0.last ?? "").hasSuffix(".swift") },
            hostedFolders: placed.hostedFolders,
            hostedLinks: placed.hostedLinks,
            referencedConfigs: placed.referencedConfigs,
            configGraph: builder.configGraph,
            exclusions: MirrorExclusions(patterns: builder.excludedPatterns),
            isUnderPrivate: isUnderPrivate
        )
    }

    /// Whether the workspace folder itself is a symlink. (A link further up its path SwiftLint
    /// reads through as if it weren't there.)
    private static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.standardizedFileURL.path)) != nil
    }

    /// Whether the `included` entry `components` names a symlink, read literally.
    private static func isLink(_ components: [String], root: URL) -> Bool {
        guard !components.contains(where: MirrorLinkReach.hasGlob) else { return false }
        let path = components.reduce(root) { $0.appendingPathComponent($1) }.path
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    /// Whether `url`'s real path starts with `/private/`. `resolvingSymlinksInPath()` drops
    /// that prefix, so this asks `realpath`.
    static func isUnderPrivate(_ url: URL) -> Bool {
        guard let resolved = realpath(url.path, nil) else { return url.path.hasPrefix("/private/") }
        defer { free(resolved) }
        return String(cString: resolved).hasPrefix("/private/")
    }
}
