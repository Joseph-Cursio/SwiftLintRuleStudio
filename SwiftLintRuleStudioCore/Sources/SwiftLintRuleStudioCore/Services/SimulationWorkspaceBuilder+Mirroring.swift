//
//  SimulationWorkspaceBuilder+Mirroring.swift
//  SwiftLintRuleStudio
//
//  Writing a workspace's mirror to disk, off the main actor, where it behaves as the
//  workspace does.
//

import Foundation

extension SimulationWorkspaceBuilder {
    /// A mirror written to disk, before its configs are read.
    struct Mirrored: Sendable {
        let container: URL
        let root: URL
        let plan: WorkspaceMirrorPlan
        let lock: MirrorLock
        /// The workspace's real path.
        let workspaceRoot: String
    }

    /// `FileManager` isn't `Sendable`, so the walk off the main actor uses the shared default
    /// manager, which is safe to use from any thread, rather than the one this builder holds.
    @concurrent
    nonisolated static func mirrorOffMainActor(
        _ workspaceRoot: URL,
        rootConfig: URL?,
        limit: Int
    ) async throws -> Mirrored {
        try mirror(workspaceRoot, rootConfig: rootConfig, limit: limit, fileManager: .default)
    }

    nonisolated static func mirror(
        _ workspaceRoot: URL,
        rootConfig: URL?,
        limit: Int,
        fileManager: FileManager
    ) throws -> Mirrored {
        let scope = try MirrorScope.make(workspaceRoot: workspaceRoot, rootConfig: rootConfig)
        let parent = try mirrorsFolder(for: scope, fileManager: fileManager)
        MirrorWriter.sweepAbandonedContainers(in: parent, fileManager: fileManager)
        let container = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = container.appendingPathComponent(scope.lintRoot, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let lock: MirrorLock
        do {
            lock = try MirrorLock.acquire(in: container)
        } catch {
            try? fileManager.removeItem(at: container)
            throw error
        }
        do {
            let plan = try WorkspaceMirrorPlan.make(for: scope, outsideEntryLimit: limit, fileManager: fileManager)
            if plan.climbsPastContainer,
               let stray = WorkspaceMirrorPlan.nearestConfig(from: parent, fileManager: fileManager) {
                // The copy's own lookups would find it; the workspace's never do.
                throw MirrorUnsupportedSetupError(
                    reason: "SwiftLint would apply \(stray.path), above the folder the simulation copies the "
                        + "workspace into, to files in the copy."
                )
            }
            try checkCaseSensitivity(of: plan, matches: container)
            try MirrorWriter.write(plan, into: container, fileManager: fileManager)
            return Mirrored(
                container: container,
                root: root,
                plan: plan,
                lock: lock,
                workspaceRoot: scope.workspaceRoot
            )
        } catch {
            try? fileManager.removeItem(at: container)
            lock.release()
            throw error
        }
    }

    /// Where mirrors go.
    ///
    /// SwiftLint reads a path under `/private` — `/tmp`, `/var`, and so the temp folder — under
    /// two spellings, `/private/var/…` and `/var/…`. There it takes the folder it lints for
    /// another, so it looks for a file's nested config above that folder too, and it counts a
    /// file it reaches through two `included` entries twice. Anywhere else it does neither. So a
    /// workspace is mirrored where it lies: one under `/private` in the temp folder, any other in
    /// the caches folder.
    ///
    /// Those are on the startup volume, which tells file names apart by case only when it was
    /// formatted to. A workspace on a volume that differs there would lose a file in the mirror
    /// (`Model.swift` beside `model.swift`), or gain one (`included: [SOURCES]` finding
    /// `Sources`); so its mirror goes on its own volume when that keeps the rest true, and
    /// otherwise the simulation is refused.
    nonisolated static func mirrorsFolder(
        for scope: MirrorScope,
        fileManager: FileManager,
        isCaseSensitive: (URL) -> Bool = isCaseSensitive
    ) throws -> URL {
        let base = scope.isUnderPrivate
            ? fileManager.temporaryDirectory
            : fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first.map {
                $0.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SwiftLintRuleStudio", isDirectory: true)
            } ?? fileManager.temporaryDirectory
        guard MirrorScope.isUnderPrivate(base) == scope.isUnderPrivate else {
            throw MirrorUnsupportedSetupError(
                reason: "The workspace is in \(scope.workspaceRoot), under /private as /tmp and /var are. SwiftLint "
                    + "reads paths there two ways, which changes the configurations and files it uses, and the "
                    + "simulation has nowhere to copy the workspace that behaves the same."
            )
        }
        let workspace = URL(fileURLWithPath: scope.workspaceRoot)
        let wanted = isCaseSensitive(workspace)
        guard isCaseSensitive(existingAncestor(of: base)) != wanted else {
            return base.appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
        }
        // A temporary folder on the workspace's own volume, made to find where those go.
        if let made = try? fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: workspace,
            create: true
        ) {
            let onVolume = made.deletingLastPathComponent()
            try? fileManager.removeItem(at: made)
            if isCaseSensitive(onVolume) == wanted, MirrorScope.isUnderPrivate(onVolume) == scope.isUnderPrivate {
                return onVolume.appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            }
        }
        throw MirrorUnsupportedSetupError(reason: caseMismatchReason(for: scope.workspaceRoot, caseSensitive: wanted))
    }

    /// Refuses a plan copying a folder from a volume that tells names apart by case into a
    /// mirror that doesn't, or the other way round.
    nonisolated private static func checkCaseSensitivity(of plan: WorkspaceMirrorPlan, matches container: URL) throws {
        let mirror = isCaseSensitive(container)
        for folder in plan.externalFolders where isCaseSensitive(folder.original) != mirror {
            throw MirrorUnsupportedSetupError(
                reason: caseMismatchReason(for: folder.original.path, caseSensitive: !mirror)
            )
        }
    }

    nonisolated private static func caseMismatchReason(for path: String, caseSensitive: Bool) -> String {
        "\(path) is on a volume that \(caseSensitive ? "tells" : "doesn't tell") file names apart by case, and "
            + "the simulation has nowhere to copy it that \(caseSensitive ? "does" : "doesn't") too; in a copy, "
            + "names that differ only in case would \(caseSensitive ? "collide" : "come apart")."
    }

    /// Whether the volume holding `url` tells file names apart by case — when it can't say, not,
    /// as the startup volume normally doesn't.
    nonisolated static func isCaseSensitive(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return values?.volumeSupportsCaseSensitiveNames ?? false
    }

    /// `url`, or its nearest ancestor that exists.
    nonisolated private static func existingAncestor(of url: URL) -> URL {
        var current = url
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" {
            current = current.deletingLastPathComponent()
        }
        return current
    }
}
