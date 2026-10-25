//
//  MirrorPathMapping.swift
//  SwiftLintRuleStudio
//
//  Puts a path SwiftLint reports in a mirrored outside folder back at the real one.
//

import Foundation

/// Where the mirror's copies of folders outside the workspace really are, so a path SwiftLint
/// reports in one can be put back at the real one. A value, so it can travel off the main actor
/// with the lint output it maps.
nonisolated struct MirrorPathMapping: Sendable {
    private let folders: [(spellings: [String], original: String)]

    /// `folders`' mirrors, inside the container at `container` as it is now.
    init(container: URL, folders: [WorkspaceMirrorPlan.ExternalFolder]) {
        self.folders = folders.map { folder in
            let mirror = container.appendingPathComponent(folder.path)
            // SwiftLint reports a path under a firmlink such as `/var` either way.
            let spellings = [mirror.path, mirror.resolvingSymlinksInPath().path, "/private" + mirror.path]
            return (spellings, folder.original.path)
        }
    }

    /// The real path of a file reported at `path`, or nil when `path` isn't in a mirrored
    /// outside folder.
    func originalPath(of path: String) -> String? {
        for folder in folders {
            if let base = folder.spellings.first(where: { path.hasPrefix($0 + "/") }) {
                return folder.original + path.dropFirst(base.count)
            }
        }
        return nil
    }
}
