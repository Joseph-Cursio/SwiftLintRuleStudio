//
//  MirrorDirectoryEntry.swift
//  SwiftLintRuleStudio
//
//  One entry of a folder, classified the way a simulation mirror needs it.
//

import Foundation

/// One entry of a folder, classified the way the mirror needs it.
nonisolated struct MirrorDirectoryEntry {
    enum Kind {
        case file
        case folder
        case folderLink(URL)
        case fileLink(URL)
    }

    let url: URL
    let name: String
    let kind: Kind

    /// The entries of `folder` worth mirroring, skipping dangling links, which SwiftLint skips
    /// too. An unreadable folder has none: SwiftLint can't read it either.
    ///
    /// Nothing is pruned by name. Folders like `.build`, `Pods` or `node_modules` are linted by
    /// SwiftLint unless the config excludes them, and so are they here; the config's `excluded`
    /// decides in the mirror as it does in the workspace.
    static func list(_ folder: URL, fileManager: FileManager) -> [Self] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        // Not `.skipsHiddenFiles`: `.swiftlint.yml` is hidden, and SwiftLint lists hidden files.
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return [] }

        return contents.compactMap { listed in
            let name = listed.lastPathComponent
            let url = folder.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            // A link reports `isDirectory == false` whatever it points to, so ask about it first.
            if values.isSymbolicLink == true {
                let target = url.resolvingSymlinksInPath()
                guard let targetValues = try? target.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                else { return nil }
                if targetValues.isDirectory == true {
                    return Self(url: url, name: name, kind: .folderLink(target))
                }
                return targetValues.isRegularFile == true ? Self(url: url, name: name, kind: .fileLink(target)) : nil
            }
            if values.isDirectory == true {
                return Self(url: url, name: name, kind: .folder)
            }
            return values.isRegularFile == true ? Self(url: url, name: name, kind: .file) : nil
        }
    }
}
