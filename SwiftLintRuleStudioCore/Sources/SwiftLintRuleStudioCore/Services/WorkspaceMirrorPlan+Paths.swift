//
//  WorkspaceMirrorPlan+Paths.swift
//  SwiftLintRuleStudio
//
//  Walking a workspace for what its mirror holds, paths in the mirror's container, and the
//  configs SwiftLint finds above a folder.
//

import Foundation

nonisolated extension WorkspaceMirrorPlan {
    /// The workspace's real path: the lint root's, below the folder the container stands for.
    var workspaceRoot: String {
        anchor == "/" ? "/" + lintRoot : anchor + "/" + lintRoot
    }

    /// Walks the workspace, and the folders beside it `included` entries reach, for the links
    /// that decide what the mirror holds.
    static func discover(
        _ scope: MirrorScope,
        outsideEntryLimit: Int,
        fileManager: FileManager
    ) throws -> MirrorLinkDiscovery {
        var discovery = MirrorLinkDiscovery(
            fileManager: fileManager,
            reach: scope.reach,
            workspaceRoot: scope.workspaceRoot,
            exclusions: scope.exclusions,
            walkRoots: scope.walkRoots,
            includedFiles: scope.includedFiles,
            isUnderPrivate: scope.isUnderPrivate,
            outsideEntryLimit: outsideEntryLimit
        )
        try discovery.explore(URL(fileURLWithPath: scope.workspaceRoot), at: "")
        // Each where SwiftLint sees it, relative to the workspace: `../Shared`, `../../Shared`.
        for folder in scope.hostedFolders {
            let url = URL(fileURLWithPath: folder)
            let place = MirrorRegions.besidePath(of: folder, in: scope) ?? url.lastPathComponent
            try discovery.explore(url, at: relative(from: scope.lintRoot, to: place))
        }
        for link in scope.hostedLinks {
            let url = URL(fileURLWithPath: link)
            let place = MirrorRegions.besidePath(of: link, in: scope) ?? url.lastPathComponent
            try discovery.follow(linkAt: url, seenAt: relative(from: scope.lintRoot, to: place))
        }
        return discovery
    }

    /// `target` relative to the folder `from`, both relative to the mirror's container.
    static func relative(from folder: String, to target: String) -> String {
        let folderComponents = folder.split(separator: "/")
        let targetComponents = target.split(separator: "/")
        let shared = zip(folderComponents, targetComponents).prefix { $0 == $1 }.count
        let ups = Array(repeating: "..", count: folderComponents.count - shared)
        return (ups + targetComponents.dropFirst(shared).map(String.init)).joined(separator: "/")
    }

    /// The `.swiftlint.yml` in `folder` or the nearest folder above it, up to `/`, passing over
    /// those in `skipping` (by resolved path), as SwiftLint passes over the configs that make up
    /// the configuration.
    static func nearestConfig(from folder: URL, fileManager: FileManager, skipping: Set<String> = []) -> URL? {
        var current = folder
        while true {
            let candidate = current.appendingPathComponent(ConfigTreeDiscovery.configFileName)
            if fileManager.fileExists(atPath: candidate.path),
               !skipping.contains(candidate.resolvingSymlinksInPath().path) {
                return candidate
            }
            guard current.path != "/" else { return nil }
            current = current.deletingLastPathComponent()
        }
    }
}
