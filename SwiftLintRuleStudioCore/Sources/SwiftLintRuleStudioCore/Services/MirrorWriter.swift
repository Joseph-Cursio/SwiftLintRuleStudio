//
//  MirrorWriter.swift
//  SwiftLintRuleStudio
//
//  Writes a simulation mirror's plan to disk, and clears away mirrors left behind.
//

import Foundation

/// Writes a ``WorkspaceMirrorPlan`` into a mirror's container, and removes containers an app
/// that quit mid-simulation left behind. File-system work, so call it off the main actor.
nonisolated enum MirrorWriter {
    /// How old a container must be before a new simulation takes it for abandoned. A
    /// simulation lasts minutes; another copy of the app may be running one right now.
    static let abandonedContainerAge: TimeInterval = 24 * 60 * 60

    /// Hardlinks each source into `container` at its mirror path and recreates the links.
    /// Sources are read-only during a lint, so sharing inodes is safe; a link failure (e.g.
    /// `EXDEV` across volumes) falls back to a copy. A file nobody can read is left out, as
    /// SwiftLint leaves it out; any other failure to copy one — a full disk, an I/O error —
    /// is thrown, since a mirror missing a file SwiftLint lints would count short.
    static func write(_ plan: WorkspaceMirrorPlan, into container: URL, fileManager: FileManager) throws {
        for folder in plan.externalFolders.map(\.path) + plan.linkedFolderPaths {
            try fileManager.createDirectory(
                at: container.appendingPathComponent(folder),
                withIntermediateDirectories: true
            )
        }
        for (index, file) in plan.sources.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let destination = container.appendingPathComponent(file.path)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try linkOrCopy(file.source, to: destination, fileManager: fileManager)
        }
        for link in plan.links {
            let location = container.appendingPathComponent(link.path)
            try fileManager.createDirectory(
                at: location.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createSymbolicLink(atPath: location.path, withDestinationPath: link.destination)
        }
    }

    private static func linkOrCopy(_ source: URL, to destination: URL, fileManager: FileManager) throws {
        if (try? fileManager.linkItem(at: source, to: destination)) != nil { return }
        try? fileManager.removeItem(at: destination)
        guard fileManager.isReadableFile(atPath: source.path) else { return }
        try fileManager.copyItem(at: source, to: destination)
        // A copy keeps a Finder lock (`uchg`), and a locked file can't be removed, so the whole
        // mirror would be left behind. Only copies can carry one: a locked file can't be
        // hardlinked, and clearing the flag on a hardlink would unlock the user's file.
        try? fileManager.setAttributes([.immutable: false], ofItemAtPath: destination.path)
    }

    /// Removes the containers in `parent` older than ``abandonedContainerAge`` whose lock no
    /// live mirror holds (see ``MirrorLock``).
    static func sweepAbandonedContainers(in parent: URL, fileManager: FileManager, now: Date = Date()) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        guard let containers = try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return }
        for container in containers {
            let values = try? container.resourceValues(forKeys: keys)
            guard let newest = [values?.contentModificationDate, values?.creationDate].compactMap(\.self).max(),
                  now.timeIntervalSince(newest) > abandonedContainerAge,
                  !MirrorLock.isHeld(in: container) else { continue }
            try? fileManager.removeItem(at: container)
        }
    }
}
