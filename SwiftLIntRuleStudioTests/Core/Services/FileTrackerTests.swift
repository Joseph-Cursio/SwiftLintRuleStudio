//
//  FileTrackerTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for FileTracker
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

@MainActor
struct FileTrackerTests {
    
    @Test("FileTracker tracks changes and metadata")
    func testFileTrackingAndChanges() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTrackerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileURL = tempDir.appendingPathComponent("sample.txt")
        try "initial".data(using: .utf8)?.write(to: fileURL)
        
        let cacheURL = tempDir.appendingPathComponent("cache.json")
        let tracker = FileTracker(cacheURL: cacheURL)
        
        try tracker.updateTracking(for: fileURL.path)
        #expect(tracker.hasFileChanged(fileURL.path) == false)
        #expect(tracker.getMetadata(for: fileURL.path) != nil)
        
        // Modify file to change metadata
        try "updated".data(using: .utf8)?.write(to: fileURL)
        #expect(tracker.hasFileChanged(fileURL.path) == true)
        
        try tracker.updateTracking(for: fileURL.path)
        #expect(tracker.hasFileChanged(fileURL.path) == false)
    }
    
    @Test("FileTracker reports changed files and clears tracking")
    func testChangedFilesAndClear() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTrackerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileURL = tempDir.appendingPathComponent("tracked.txt")
        try "data".data(using: .utf8)?.write(to: fileURL)
        
        let tracker = FileTracker()
        try tracker.updateTracking(for: fileURL.path)
        
        let changed = tracker.getChangedFiles(from: [fileURL.path])
        #expect(changed.isEmpty == true)
        
        tracker.removeTracking(for: fileURL.path)
        #expect(tracker.getMetadata(for: fileURL.path) == nil)
        
        tracker.clear()
        #expect(tracker.getAllTrackedPaths().isEmpty == true)
    }
    
    @Test("FileTracker persists cache and handles missing files")
    func testCachePersistenceAndMissingFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTrackerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileURL = tempDir.appendingPathComponent("persisted.txt")
        try "cache".data(using: .utf8)?.write(to: fileURL)
        
        let cacheURL = tempDir.appendingPathComponent("cache.json")
        let tracker = FileTracker(cacheURL: cacheURL)
        try tracker.updateTracking(for: fileURL.path)
        
        let newTracker = FileTracker(cacheURL: cacheURL)
        #expect(newTracker.getMetadata(for: fileURL.path) != nil)
        
        try FileManager.default.removeItem(at: fileURL)
        #expect(newTracker.hasFileChanged(fileURL.path) == true)
        
        #expect(throws: FileTrackerError.self) {
            try newTracker.updateTracking(for: fileURL.path)
        }
    }
}

