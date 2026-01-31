//
//  WorkspaceManager+WorkspaceValidation.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

extension WorkspaceManager {
    /// Validate that a directory is a valid Swift project workspace
    func validateSwiftWorkspace(at url: URL) throws {
        let path = url.path
        let indicators = try scanTopLevelIndicators(at: url)
        if indicators.hasProjectMarker {
            return
        }

        let hasSwiftFiles = indicators.hasSwiftFiles || hasSwiftFilesWithinDepth(
            at: url,
            rootPath: path,
            maxDepth: 3
        )
        if !hasSwiftFiles {
            throw WorkspaceError.notASwiftProject(directory: url.lastPathComponent)
        }
    }
}

private extension WorkspaceManager {
    struct WorkspaceIndicators {
        let hasProjectMarker: Bool
        let hasSwiftFiles: Bool
    }

    func scanTopLevelIndicators(at url: URL) throws -> WorkspaceIndicators {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]
            )
            var hasSwiftFiles = false
            var hasProjectMarker = false

            for item in contents {
                if isProjectMarker(item) {
                    hasProjectMarker = true
                }
                if item.pathExtension.lowercased() == "swift" {
                    hasSwiftFiles = true
                }
            }

            return WorkspaceIndicators(hasProjectMarker: hasProjectMarker, hasSwiftFiles: hasSwiftFiles)
        } catch {
            throw WorkspaceError.accessDenied
        }
    }

    func isProjectMarker(_ url: URL) -> Bool {
        let itemName = url.lastPathComponent
        if itemName.hasSuffix(".xcodeproj") || itemName.hasSuffix(".xcworkspace") {
            return true
        }
        return itemName == "Package.swift" || itemName == ".swiftpm"
    }

    func hasSwiftFilesWithinDepth(at url: URL, rootPath: String, maxDepth: Int) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: rootPath + "/", with: "")
            let depth = relativePath.components(separatedBy: "/").count

            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if shouldSkipWorkspaceScan(path: fileURL.path) {
                enumerator.skipDescendants()
                continue
            }

            if fileURL.pathExtension.lowercased() == "swift" {
                return true
            }
        }

        return false
    }

    func shouldSkipWorkspaceScan(path: String) -> Bool {
        if path.contains("/.build/") ||
            path.contains("/Pods/") ||
            path.contains("/node_modules/") ||
            path.contains("/.git/") {
            return true
        }
        return false
    }
}
