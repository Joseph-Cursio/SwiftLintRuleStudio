//
//  MirrorScope.swift
//  SwiftLintRuleStudio
//
//  What a simulation mirror must reach beyond the workspace, from the configs that decide it —
//  or why it can't.
//

import Darwin
import Foundation

/// A setup the mirror can't reproduce faithfully. Rather than measure a count that might be
/// short — and a short count reads as "safe to enable" — the simulation fails with this.
nonisolated struct MirrorUnsupportedSetupError: LocalizedError, Sendable {
    let reason: String

    var errorDescription: String? {
        reason + " The simulation can't reproduce that, so it stopped rather than report a count that might be short."
    }
}

/// Accumulates a ``MirrorScope`` while walking the root config and the configs it pulls in,
/// then places what they reach once it knows how far up they climb.
nonisolated private struct MirrorScopeBuilder {
    /// A path a config names, standardized and absolute, and how it was written.
    struct Target {
        let written: String
        let config: String
        let components: [String]
    }

    struct Placed {
        let anchor: String
        let lintRoot: String
        let included: [[String]]
        let hostedFolders: [String]
        let referencedConfigs: [WorkspaceMirrorPlan.File]
    }

    let root: URL
    let rootComponents: [String]
    var configGraph: Set<String> = []
    /// Absolute, as SwiftLint makes them: each config's folder joined with the entry.
    var excludedPatterns: [String] = []
    /// A config excludes something.
    var excludesAnything = false
    private var includedTargets: [Target] = []
    private var referencedTargets: [(target: Target, file: URL)] = []
    private var visited: Set<String> = []

    init(root: URL) {
        self.root = root
        rootComponents = root.pathComponents
    }

    mutating func visit(_ config: URL, base: URL) throws {
        guard visited.insert(config.standardizedFileURL.path).inserted,
              let keys = RawConfigKeys.read(config) else { return }
        if !keys.excluded.isEmpty { excludesAnything = true }
        for written in keys.excluded {
            let (entry, entryBase) = expandingPWD(written, base: base)
            excludedPatterns.append(entry.hasPrefix("/") ? entry : Self.absolute(entry, base: entryBase))
        }
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
            let components = Self.standardized(entryBase.pathComponents + parts)
            includedTargets.append(Target(written: written, config: config.lastPathComponent, components: components))
        }
        for reference in keys.referencedConfigs {
            try follow(reference, from: config)
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

    /// Records a `parent_config`/`child_config` the mirror must hold, and walks it.
    private mutating func follow(_ reference: String, from config: URL) throws {
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
        try visit(file, base: file.deletingLastPathComponent())
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
        let lintRoot = rootComponents.dropFirst(anchorCount).joined(separator: "/")
        try checkReserved(lintRoot, written: lintRoot, config: "the workspace")

        var included: [[String]] = []
        var hosted: [String] = []
        for target in includedTargets {
            let common = commonPrefixCount(target.components)
            let below = Array(target.components.dropFirst(common))
            included.append(Array(repeating: "..", count: rootComponents.count - common) + below)
            guard common < rootComponents.count else { continue }
            let literal = below.prefix { !MirrorLinkReach.hasGlob($0) }
            guard !literal.isEmpty else {
                throw MirrorUnsupportedSetupError(
                    reason: "The configuration's `included` names \(target.written), a folder holding the workspace, "
                        + "or a pattern over one."
                )
            }
            let folder = Array(rootComponents.prefix(common)) + literal
            let place = folder.dropFirst(anchorCount).joined(separator: "/")
            try checkReserved(place, written: target.written, config: target.config)
            let path = "/" + folder.dropFirst().joined(separator: "/")
            if !hosted.contains(path) { hosted.append(path) }
        }

        let referenced = try referencedTargets.map { target, file in
            let common = commonPrefixCount(target.components)
            let path = (Array(rootComponents[anchorCount..<common]) + target.components.dropFirst(common))
                .joined(separator: "/")
            try checkReserved(path, written: target.written, config: target.config)
            return WorkspaceMirrorPlan.File(source: file, path: path)
        }
        let anchor = "/" + rootComponents.prefix(anchorCount).dropFirst().joined(separator: "/")
        return Placed(
            anchor: anchor,
            lintRoot: lintRoot,
            included: included,
            hostedFolders: hosted,
            referencedConfigs: referenced
        )
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

    /// `entry` joined to `base` and standardized.
    private static func absolute(_ entry: String, base: URL) -> String {
        let components = standardized(base.pathComponents + entry.split(separator: "/").map(String.init))
        return "/" + components.dropFirst().joined(separator: "/")
    }

    /// `components` with `.` dropped and each `..` taking the one before it, as SwiftLint
    /// standardizes a path.
    private static func standardized(_ components: [String]) -> [String] {
        var result: [String] = []
        for component in components where component != "." && !component.isEmpty {
            if component == "..", result.count > 1 {
                result.removeLast()
            } else if component != ".." {
                result.append(component)
            }
        }
        return result
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
    /// Folders outside the workspace that `included` entries name, by real path.
    let hostedFolders: [String]
    /// The configs the root config pulls in through `parent_config` or `child_config`, where
    /// SwiftLint will look for them; paths relative to the container.
    let referencedConfigs: [WorkspaceMirrorPlan.File]
    /// The root config and the configs it pulls in, by resolved path. SwiftLint looking for a
    /// file's nested config passes over these, as they already make up the configuration.
    let configGraph: Set<String>
    /// What the root config and the configs it pulls in exclude.
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
        let placed = try builder.place()
        return Self(
            workspaceRoot: root.path,
            anchor: placed.anchor,
            lintRoot: placed.lintRoot,
            reach: builder.excludesAnything ? .everyLink : .towardIncluded(placed.included),
            walkRoots: placed.included.isEmpty ? nil : placed.included.filter { entry in
                !(entry.last ?? "").hasSuffix(".swift") && !isLink(entry, root: root)
            },
            hostedFolders: placed.hostedFolders,
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
