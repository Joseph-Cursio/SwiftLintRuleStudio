//
//  MirrorRegions.swift
//  SwiftLintRuleStudio
//
//  The real folders a simulation mirror reproduces, and where each goes in it.
//

import Foundation

/// The real folders the mirror reproduces, and where each goes in the mirror's container, which
/// stands for a folder holding the workspace (``MirrorScope/anchor``):
/// - the workspace, at the lint root;
/// - the outermost of the other folders in it that `included` entries name or links point into,
///   at their own places, so a path climbing out of the workspace (`../Shared`) means the same
///   in the mirror, and so do the configs between them and the container;
/// - the outermost of the folders further out that links point into, in the container's
///   outside folder;
/// - the folders of outside files that file links point at, holding just those files, placed
///   the same way.
nonisolated struct MirrorRegions {
    struct Region {
        let real: String
        let mirror: String
    }

    /// A folder outside the workspace holding files that file links point at — only those.
    struct FileRegion {
        let region: Region
        let files: [String]
        /// Whether it is in the folder holding the workspace, at its own place in the container.
        let isBeside: Bool
    }

    let workspace: Region
    /// Folders in the folder holding the workspace, at their own places in the container.
    let beside: [Region]
    /// Folders further out, in the container's outside folder.
    let externals: [Region]
    let fileRegions: [FileRegion]

    init(scope: MirrorScope, linkedFolders: Set<String>, linkedFiles: Set<String>) {
        workspace = Region(real: scope.workspaceRoot, mirror: scope.lintRoot)

        // Outermost only: two links into one folder then reach one copy of it, as SwiftLint
        // reaches one real folder and counts its files once.
        let outside = linkedFolders.filter { !Self.isInside($0, scope.workspaceRoot) }
        let folders = Self.outermost(scope.hostedFolders + outside)
        beside = folders.compactMap { folder in
            Self.besidePath(of: folder, in: scope).map { Region(real: folder, mirror: $0) }
        }
        let further = folders.filter { Self.besidePath(of: $0, in: scope) == nil }
        externals = further.enumerated().map { index, folder in
            Region(real: folder, mirror: "\(MirrorScope.outsideFolderName)/\(index)/tree")
        }

        let inPlace = [workspace.real] + folders
        let looseFiles = linkedFiles.filter { file in !inPlace.contains { Self.isInside(file, $0) } }
        let byFolder = Dictionary(grouping: looseFiles) { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        var nextOutside = further.count
        fileRegions = byFolder.keys.sorted().map { folder in
            let files = (byFolder[folder] ?? []).sorted()
            if let path = Self.besidePath(of: folder, in: scope) {
                return FileRegion(region: Region(real: folder, mirror: path), files: files, isBeside: true)
            }
            defer { nextOutside += 1 }
            let mirror = "\(MirrorScope.outsideFolderName)/\(nextOutside)/tree"
            return FileRegion(region: Region(real: folder, mirror: mirror), files: files, isBeside: false)
        }
    }

    /// Where the real path `path` is in the mirror, or nil when no mirrored folder holds it.
    func mirrorPath(of path: String) -> String? {
        if let fileRegion = fileRegions.first(where: { $0.files.contains(path) }) {
            return fileRegion.region.mirror + "/" + URL(fileURLWithPath: path).lastPathComponent
        }
        for region in [workspace] + beside + externals where Self.isInside(path, region.real) {
            return path == region.real ? region.mirror : region.mirror + path.dropFirst(region.real.count)
        }
        return nil
    }

    /// Whether the mirror holds the real file at `path` where it is: a file a file region
    /// holds, or a `.swift` file in a mirrored folder.
    func isMirrored(file path: String) -> Bool {
        if fileRegions.contains(where: { $0.files.contains(path) }) { return true }
        return path.hasSuffix(".swift") && ([workspace] + beside + externals).contains { Self.isInside(path, $0.real) }
    }

    /// Whether `path` is `folder` or lies inside it. Every path lies inside `/`.
    static func isInside(_ path: String, _ folder: String) -> Bool {
        folder == "/" || path == folder || path.hasPrefix(folder + "/")
    }

    /// `folder`'s place in the container for a region of its own: in the folder the container
    /// stands for, not holding the workspace — or nil.
    static func besidePath(of folder: String, in scope: MirrorScope) -> String? {
        guard !isInside(scope.workspaceRoot, folder) else { return nil }
        return placeInContainer(of: folder, in: scope)
    }

    /// `folder`'s place in the container: beneath the folder the container stands for, and not
    /// under a name the container keeps for itself — or nil.
    static func placeInContainer(of folder: String, in scope: MirrorScope) -> String? {
        let anchor = scope.anchor == "/" ? "" : scope.anchor
        guard folder.hasPrefix(anchor + "/") else { return nil }
        let path = String(folder.dropFirst(anchor.count + 1))
        let first = path.split(separator: "/").first.map(String.init) ?? ""
        guard ![MirrorScope.outsideFolderName, MirrorScope.lockFileName].contains(first) else { return nil }
        return path
    }

    /// The folders not inside another of them, sorted.
    private static func outermost(_ folders: some Collection<String>) -> [String] {
        var kept: [String] = []
        for folder in folders.sorted(by: { $0.count < $1.count })
        where !kept.contains(where: { isInside(folder, $0) }) {
            kept.append(folder)
        }
        return kept.sorted()
    }
}
