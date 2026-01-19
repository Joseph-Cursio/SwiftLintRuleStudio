//
//  FileTracker.swift
//  SwiftLintRuleStudio
//
//  Tracks file modification times for incremental analysis
//

import Foundation

/// Tracks file modification times to enable incremental analysis
class FileTracker {
    
    // MARK: - Types
    
    struct FileMetadata: Codable {
        let path: String
        let lastModified: Date
        let fileSize: Int64
    }
    
    // MARK: - Properties
    
    private var trackedFiles: [String: FileMetadata] = [:]
    private let cacheURL: URL?
    
    // MARK: - Initialization
    
    init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL
        loadCache()
    }
    
    // MARK: - File Tracking
    
    /// Get metadata for a file path
    func getMetadata(for filePath: String) -> FileMetadata? {
        return trackedFiles[filePath]
    }
    
    /// Check if a file has changed since last tracking
    func hasFileChanged(_ filePath: String) -> Bool {
        guard let tracked = trackedFiles[filePath] else {
            return true // New file, consider it changed
        }
        
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let modificationDate = attributes[.modificationDate] as? Date,
              let fileSize = attributes[.size] as? Int64 else {
            return true // Can't read file, consider it changed
        }
        
        // File changed if modification date or size changed
        return modificationDate != tracked.lastModified || fileSize != tracked.fileSize
    }
    
    /// Update tracking for a file
    func updateTracking(for filePath: String) throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let modificationDate = attributes[.modificationDate] as? Date,
              let fileSize = attributes[.size] as? Int64 else {
            throw FileTrackerError.cannotReadFile(filePath)
        }
        
        let metadata = FileMetadata(
            path: filePath,
            lastModified: modificationDate,
            fileSize: fileSize
        )
        
        trackedFiles[filePath] = metadata
        saveCache()
    }
    
    /// Update tracking for multiple files
    func updateTracking(for filePaths: [String]) throws {
        for filePath in filePaths {
            try updateTracking(for: filePath)
        }
    }
    
    /// Remove tracking for a file (e.g., when file is deleted)
    func removeTracking(for filePath: String) {
        trackedFiles.removeValue(forKey: filePath)
        saveCache()
    }
    
    /// Get all changed files from a list
    func getChangedFiles(from filePaths: [String]) -> [String] {
        return filePaths.filter { hasFileChanged($0) }
    }
    
    /// Clear all tracking
    func clear() {
        trackedFiles.removeAll()
        saveCache()
    }
    
    /// Get all tracked file paths
    func getAllTrackedPaths() -> [String] {
        return Array(trackedFiles.keys)
    }
    
    // MARK: - Cache Management
    
    private func loadCache() {
        guard let cacheURL = cacheURL,
              FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: FileMetadata].self, from: data) else {
            return
        }
        
        // Filter out files that no longer exist
        trackedFiles = decoded.filter { filePath, _ in
            FileManager.default.fileExists(atPath: filePath)
        }
    }
    
    private func saveCache() {
        guard let cacheURL = cacheURL else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(trackedFiles)
            try data.write(to: cacheURL)
        } catch {
            // Silently fail - cache is not critical
            print("Warning: Failed to save file tracker cache: \(error)")
        }
    }
}

// MARK: - Errors

enum FileTrackerError: LocalizedError {
    case cannotReadFile(String)
    
    var errorDescription: String? {
        switch self {
        case .cannotReadFile(let path):
            return "Cannot read file attributes: \(path)"
        }
    }
}

