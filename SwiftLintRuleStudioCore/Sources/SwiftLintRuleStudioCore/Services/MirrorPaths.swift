//
//  MirrorPaths.swift
//  SwiftLintRuleStudio
//
//  Path arithmetic the simulation mirror shares: standardizing a path, placing one in the
//  container, and writing an `excluded` entry so it names in the mirror what it names in the
//  workspace.
//

import Foundation

nonisolated enum MirrorPaths {
    /// `components` with `.` dropped and each `..` taking the one before it, as SwiftLint
    /// standardizes a path.
    static func standardized(_ components: [String]) -> [String] {
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

    /// The `excluded` entry `entry`, from a config read relative to the folder `base`, as
    /// SwiftLint makes it absolute: `~/` expanded, and a relative one joined to `base`, then
    /// standardized. Nil for one starting with `${PWD}`, which names the folder SwiftLint runs in.
    static func absolute(_ entry: String, base: String) -> String? {
        guard !entry.hasPrefix("${PWD}") else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded = entry.hasPrefix("~/") ? home + entry.dropFirst() : entry
        let joined = expanded.hasPrefix("/") ? expanded : base + "/" + expanded
        let components = standardized(["/"] + joined.split(separator: "/").map(String.init))
        return "/" + components.dropFirst().joined(separator: "/")
    }

    /// The absolute `pattern` as SwiftLint matches it: under `/tmp`, `/var` or `/etc`, which are
    /// `/private`'s, it matches a path either way, so without that prefix, as the mirror spells
    /// paths; anywhere else as written.
    static func unprivate(_ pattern: String) -> String {
        let rest = pattern.dropFirst("/private".count)
        let isFirmlinked = ["/tmp", "/var", "/etc"].contains { rest == $0 || rest.hasPrefix($0 + "/") }
        return pattern.hasPrefix("/private/") && isFirmlinked ? String(rest) : pattern
    }

    /// The first symlink to a folder on the way down `components` from the folder `base` names,
    /// by absolute path; nil when there is none, or the first leads to a file.
    static func firstFolderLink(on components: [String], under base: [String]) -> String? {
        var folder = base
        for component in components {
            folder.append(component)
            let path = "/" + folder.dropFirst().joined(separator: "/")
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil else { continue }
            var isFolder: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
            return exists && isFolder.boolValue ? path : nil
        }
        return nil
    }

    /// The path of the absolute `pattern` below `folder`: "" for `folder` itself, nil when it
    /// doesn't lie there. Its folders up to the first glob decide.
    static func place(_ pattern: String, in folder: String) -> String? {
        let (literal, rest) = split(unprivate(pattern))
        guard MirrorRegions.isInside(literal, folder) else { return nil }
        let below = literal == folder ? "" : String(literal.dropFirst(folder == "/" ? 1 : folder.count + 1))
        return [below, rest].filter { !$0.isEmpty }.joined(separator: "/")
    }

    /// Whether the absolute `pattern` starts above `folder`: its folders up to the first glob
    /// hold `folder` and aren't it, so it may take everything there, or match part way down.
    static func startsAbove(_ pattern: String, _ folder: String) -> Bool {
        let literal = split(unprivate(pattern)).literal
        return literal != folder && MirrorRegions.isInside(folder, literal)
    }

    /// The `excluded` entry to write in the mirror for `entry`, from a config read relative to
    /// the folder `base` whose copy is at `mirrorBase` in the container. One written relative
    /// that stays below `anchor`, the folder the container stands for, names the same there as
    /// written; any other, absolute or climbing above it, is written relative too, to its place in
    /// the container — below the anchor or in an outside folder's copy. One naming nothing the
    /// mirror holds stays as it is: it names nothing SwiftLint lints there either. One starting
    /// above an outside folder the mirror copies has no place there, so the simulation stops.
    static func mirroredExclusion(
        _ entry: String,
        base: String,
        mirrorBase: String,
        anchor: String,
        outsideFolders: [WorkspaceMirrorPlan.ExternalFolder]
    ) throws -> String {
        guard let pattern = absolute(entry, base: base), needsRewriting(entry, base: base, anchor: anchor) else {
            return entry
        }
        if place(pattern, in: anchor) == nil,
           let folder = outsideFolders.first(where: { startsAbove(pattern, $0.original.path) }) {
            throw MirrorUnsupportedSetupError(
                reason: "The configuration's `excluded` has \(entry), which starts above \(folder.original.path), "
                    + "a folder the workspace's symlinks reach that a copy of the workspace holds elsewhere."
            )
        }
        let place = place(pattern, in: anchor) ?? outsideFolders.lazy.compactMap { folder in
            Self.place(pattern, in: folder.original.path).map { below in
                [folder.path, below].filter { !$0.isEmpty }.joined(separator: "/")
            }
        }.first
        guard let place else { return entry }
        let relative = WorkspaceMirrorPlan.relative(from: mirrorBase, to: place)
        return relative.isEmpty ? "." : relative
    }

    /// Whether `entry` names anything but where it is written relative to: absolute, from `~/`,
    /// or climbing above `anchor` on the way.
    private static func needsRewriting(_ entry: String, base: String, anchor: String) -> Bool {
        guard !entry.hasPrefix("/"), !entry.hasPrefix("~/") else { return true }
        let anchorDepth = anchor.split(separator: "/").count
        var depth = base.split(separator: "/").count
        for component in entry.split(separator: "/") where component != "." {
            depth += component == ".." ? -1 : 1
            if depth < anchorDepth { return true }
        }
        return false
    }

    /// `path` split before its first component holding a glob: the folder that part names, and
    /// the rest.
    private static func split(_ path: String) -> (literal: String, rest: String) {
        let components = path.split(separator: "/").map(String.init)
        let globAt = components.firstIndex(where: MirrorLinkReach.hasGlob) ?? components.count
        let literal = "/" + components[..<globAt].joined(separator: "/")
        return (literal, components[globAt...].joined(separator: "/"))
    }
}
