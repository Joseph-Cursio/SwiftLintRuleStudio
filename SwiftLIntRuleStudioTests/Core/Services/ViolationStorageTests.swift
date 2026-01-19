//
//  ViolationStorageTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for Violation Storage
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// ViolationStorage is an actor (not @MainActor), so tests don't need @MainActor
struct ViolationStorageTests {
    
    // MARK: - Test Helpers
    
    /// Creates a completely isolated ViolationStorage instance for each test
    /// Each test gets its own unique in-memory database to ensure no shared state
    private func createIsolatedStorage() async throws -> ViolationStorage {
        // Workaround for Swift 6 false positive: ViolationStorage is an actor, not @MainActor
        return try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
    }
    
    private func createTempDatabase() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        return tempDir.appendingPathComponent("test_violations.db")
    }
    
    private func cleanupTempDatabase(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
    
    private func createTestViolation(ruleID: String = "test_rule", filePath: String = "Test.swift") -> Violation {
        return Violation(
            ruleID: ruleID,
            filePath: filePath,
            line: 10,
            column: 5,
            severity: .error,
            message: "Test violation"
        )
    }
    
    // MARK: - Storage Tests
    
    @Test("ViolationStorage stores violations")
    func testStoreViolations() async throws {
        // Use isolated storage to ensure complete test isolation
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1"),
            createTestViolation(ruleID: "rule2")
        ]
        
        try await storage.storeViolations(violations, for: workspaceId)
        
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        let (count, hasRule1, hasRule2) = await MainActor.run {
            (fetched.count, fetched.contains { $0.ruleID == "rule1" }, fetched.contains { $0.ruleID == "rule2" })
        }
        #expect(count == 2)
        #expect(hasRule1 == true)
        #expect(hasRule2 == true)
    }
    
    @Test("ViolationStorage fetches violations by workspace")
    func testFetchViolationsByWorkspace() async throws {
        let storage = try await createIsolatedStorage()
        let workspace1 = UUID()
        let workspace2 = UUID()
        
        let violations1 = [createTestViolation(ruleID: "rule1")]
        let violations2 = [createTestViolation(ruleID: "rule2")]
        
        try await storage.storeViolations(violations1, for: workspace1)
        try await storage.storeViolations(violations2, for: workspace2)
        
        let fetched1 = try await storage.fetchViolations(filter: .all, workspaceId: workspace1)
        let fetched2 = try await storage.fetchViolations(filter: .all, workspaceId: workspace2)
        
        let (count1, ruleID1, count2, ruleID2) = await MainActor.run {
            (fetched1.count, fetched1.first?.ruleID, fetched2.count, fetched2.first?.ruleID)
        }
        #expect(count1 == 1)
        #expect(ruleID1 == "rule1")
        #expect(count2 == 1)
        #expect(ruleID2 == "rule2")
    }
    
    @Test("ViolationStorage filters violations by rule ID")
    func testFilterByRuleID() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let violations = [
            createTestViolation(ruleID: "rule1"),
            createTestViolation(ruleID: "rule2"),
            createTestViolation(ruleID: "rule3")
        ]
        
        try await storage.storeViolations(violations, for: workspaceId)
        
        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.ruleIDs = ["rule1", "rule3"]
            return filter
        }
        
        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        
        let (count, allMatch) = await MainActor.run {
            (fetched.count, fetched.allSatisfy { $0.ruleID == "rule1" || $0.ruleID == "rule3" })
        }
        #expect(count == 2)
        #expect(allMatch == true)
    }
    
    @Test("ViolationStorage filters violations by severity")
    func testFilterBySeverity() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let violations = [
            Violation(ruleID: "rule1", filePath: "Test.swift", line: 1, severity: .error, message: "Error"),
            Violation(ruleID: "rule2", filePath: "Test.swift", line: 2, severity: .warning, message: "Warning"),
            Violation(ruleID: "rule3", filePath: "Test.swift", line: 3, severity: .error, message: "Error")
        ]
        
        try await storage.storeViolations(violations, for: workspaceId)
        
        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.severities = [.error]
            return filter
        }
        
        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        
        let (count, allError) = await MainActor.run {
            (fetched.count, fetched.allSatisfy { $0.severity == .error })
        }
        #expect(count == 2)
        #expect(allError == true)
    }
    
    @Test("ViolationStorage filters violations by file path")
    func testFilterByFilePath() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let violations = [
            createTestViolation(ruleID: "rule1", filePath: "File1.swift"),
            createTestViolation(ruleID: "rule2", filePath: "File2.swift"),
            createTestViolation(ruleID: "rule3", filePath: "File1.swift")
        ]
        
        try await storage.storeViolations(violations, for: workspaceId)
        
        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.filePaths = ["File1.swift"]
            return filter
        }
        
        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        
        let (count, allMatch) = await MainActor.run {
            (fetched.count, fetched.allSatisfy { $0.filePath == "File1.swift" })
        }
        #expect(count == 2)
        #expect(allMatch == true)
    }
    
    @Test("ViolationStorage filters violations by suppressed status")
    func testFilterBySuppressed() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let violations = [
            createTestViolation(ruleID: "rule1"),
            createTestViolation(ruleID: "rule2")
        ]
        
        try await storage.storeViolations(violations, for: workspaceId)
        
        // Suppress first violation
        try await storage.suppressViolations([violations[0].id], reason: "Test reason")
        
        let filter1 = await MainActor.run {
            var filter = ViolationFilter()
            filter.suppressedOnly = true
            return filter
        }
        
        let suppressed = try await storage.fetchViolations(filter: filter1, workspaceId: workspaceId)
        let (suppressedCount, isSuppressed, suppressionReason) = await MainActor.run {
            (suppressed.count, suppressed.first?.suppressed, suppressed.first?.suppressionReason)
        }
        #expect(suppressedCount == 1)
        #expect(isSuppressed == true)
        #expect(suppressionReason == "Test reason")
        
        let filter2 = await MainActor.run {
            var filter = ViolationFilter()
            filter.suppressedOnly = false
            return filter
        }
        let notSuppressed = try await storage.fetchViolations(filter: filter2, workspaceId: workspaceId)
        let (notSuppressedCount, isNotSuppressed) = await MainActor.run {
            (notSuppressed.count, notSuppressed.first?.suppressed)
        }
        #expect(notSuppressedCount == 1)
        #expect(isNotSuppressed == false)
    }
    
    @Test("ViolationStorage suppresses violations")
    func testSuppressViolations() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let violations = [createTestViolation()]
        try await storage.storeViolations(violations, for: workspaceId)
        
        try await storage.suppressViolations([violations[0].id], reason: "Not applicable")
        
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        let (count, isSuppressed, reason) = await MainActor.run {
            (fetched.count, fetched.first?.suppressed, fetched.first?.suppressionReason)
        }
        #expect(count == 1)
        #expect(isSuppressed == true)
        #expect(reason == "Not applicable")
    }
    
    @Test("ViolationStorage resolves violations")
    func testResolveViolations() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let violations = [createTestViolation()]
        try await storage.storeViolations(violations, for: workspaceId)
        
        try await storage.resolveViolations([violations[0].id])
        
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        let (count, hasResolvedAt) = await MainActor.run {
            (fetched.count, fetched.first?.resolvedAt != nil)
        }
        #expect(count == 1)
        #expect(hasResolvedAt == true)
    }
    
    @Test("ViolationStorage deletes violations for workspace")
    func testDeleteViolations() async throws {
        let storage = try await createIsolatedStorage()
        let workspace1 = UUID()
        let workspace2 = UUID()
        
        let violations1 = [createTestViolation(ruleID: "rule1")]
        let violations2 = [createTestViolation(ruleID: "rule2")]
        
        try await storage.storeViolations(violations1, for: workspace1)
        try await storage.storeViolations(violations2, for: workspace2)
        
        try await storage.deleteViolations(for: workspace1)
        
        let fetched1 = try await storage.fetchViolations(filter: .all, workspaceId: workspace1)
        let fetched2 = try await storage.fetchViolations(filter: .all, workspaceId: workspace2)
        
        #expect(fetched1.isEmpty)
        #expect(fetched2.count == 1)
    }
    
    @Test("ViolationStorage gets violation count")
    func testGetViolationCount() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let violations = [
            createTestViolation(ruleID: "rule1"),
            createTestViolation(ruleID: "rule2"),
            createTestViolation(ruleID: "rule3")
        ]
        
        try await storage.storeViolations(violations, for: workspaceId)
        
        let count = try await storage.getViolationCount(filter: .all, workspaceId: workspaceId)
        #expect(count == 3)
        
        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.ruleIDs = ["rule1"]
            return filter
        }
        let filteredCount = try await storage.getViolationCount(filter: filter, workspaceId: workspaceId)
        #expect(filteredCount == 1)
    }
    
    @Test("ViolationStorage handles date range filtering")
    func testFilterByDateRange() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let oldDate = Date().addingTimeInterval(-86400) // 1 day ago
        let newDate = Date()
        
        let oldViolation = Violation(
            ruleID: "rule1",
            filePath: "Test.swift",
            line: 1,
            severity: .error,
            message: "Old",
            detectedAt: oldDate
        )
        
        let newViolation = Violation(
            ruleID: "rule2",
            filePath: "Test.swift",
            line: 2,
            severity: .error,
            message: "New",
            detectedAt: newDate
        )
        
        try await storage.storeViolations([oldViolation, newViolation], for: workspaceId)
        
        let yesterday = Date().addingTimeInterval(-43200) // 12 hours ago
        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.dateRange = yesterday...Date()
            return filter
        }
        
        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        let (count, ruleID) = await MainActor.run {
            (fetched.count, fetched.first?.ruleID)
        }
        #expect(count == 1)
        #expect(ruleID == "rule2")
    }
    
    @Test("ViolationStorage handles empty database")
    func testEmptyDatabase() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.isEmpty)
        
        let count = try await storage.getViolationCount(filter: .all, workspaceId: workspaceId)
        #expect(count == 0)
    }
    
    @Test("ViolationStorage handles large batch inserts")
    func testLargeBatchInsert() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        // Create 100 violations
        let violations = (0..<100).map { index in
            createTestViolation(ruleID: "rule\(index)", filePath: "File\(index).swift")
        }
        
        try await storage.storeViolations(violations, for: workspaceId)
        
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 100)
    }
    
    @Test("ViolationStorage handles very large batch inserts with transaction")
    func testVeryLargeBatchInsert() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        // Create 1000 violations to test transaction handling
        let violations = (0..<1000).map { index in
            createTestViolation(ruleID: "rule\(index)", filePath: "File\(index % 10).swift")
        }
        
        try await storage.storeViolations(violations, for: workspaceId)
        
        // Verify all violations were stored
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1000)
        
        // Verify violation count matches
        let count = try await storage.getViolationCount(filter: .all, workspaceId: workspaceId)
        #expect(count == 1000)
        
        // Verify we can fetch specific violations
        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.ruleIDs = ["rule0", "rule500", "rule999"]
            return filter
        }
        let filtered = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        #expect(filtered.count == 3)
    }
    
    @Test("ViolationStorage preserves violation metadata")
    func testPreserveViolationMetadata() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        let original = Violation(
            id: UUID(),
            ruleID: "test_rule",
            filePath: "Test.swift",
            line: 42,
            column: 10,
            severity: .warning,
            message: "Test message",
            detectedAt: Date(),
            resolvedAt: nil,
            suppressed: false,
            suppressionReason: nil
        )
        
        try await storage.storeViolations([original], for: workspaceId)
        
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        let captured = await MainActor.run {
            fetched.first.map {
                (
                    count: fetched.count,
                    id: $0.id,
                    ruleID: $0.ruleID,
                    filePath: $0.filePath,
                    line: $0.line,
                    column: $0.column,
                    severity: $0.severity,
                    message: $0.message
                )
            }
        }
        let unwrapped = try #require(captured)
        let comparison = await MainActor.run {
            (
                idMatch: unwrapped.id == original.id,
                ruleIDMatch: unwrapped.ruleID == original.ruleID,
                filePathMatch: unwrapped.filePath == original.filePath,
                lineMatch: unwrapped.line == original.line,
                columnMatch: unwrapped.column == original.column,
                severityMatch: unwrapped.severity == original.severity,
                messageMatch: unwrapped.message == original.message
            )
        }
        #expect(unwrapped.count == 1)
        #expect(comparison.idMatch == true)
        #expect(comparison.ruleIDMatch == true)
        #expect(comparison.filePathMatch == true)
        #expect(comparison.lineMatch == true)
        #expect(comparison.columnMatch == true)
        #expect(comparison.severityMatch == true)
        #expect(comparison.messageMatch == true)
    }
    
    @Test("ViolationStorage handles duplicate IDs with INSERT OR REPLACE")
    func testDuplicateIDsAreReplaced() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        // Create violations with the same ID (should replace each other)
        let sharedID = UUID()
        let violation1 = Violation(
            id: sharedID,
            ruleID: "rule1",
            filePath: "File1.swift",
            line: 10,
            severity: .error,
            message: "First message"
        )
        
        let violation2 = Violation(
            id: sharedID, // Same ID
            ruleID: "rule2",
            filePath: "File2.swift",
            line: 20,
            severity: .warning,
            message: "Second message"
        )
        
        // Store both violations with the same ID
        try await storage.storeViolations([violation1, violation2], for: workspaceId)
        
        // Should only have 1 violation (the second one replaced the first)
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1)
        
        // The stored violation should be the last one (violation2)
        let stored = await MainActor.run {
            fetched.first.map {
                (id: $0.id, ruleID: $0.ruleID, filePath: $0.filePath, message: $0.message)
            }
        }
        let unwrapped = try #require(stored)
        let storedComparison = await MainActor.run {
            (
                idMatch: unwrapped.id == sharedID,
                ruleID: unwrapped.ruleID,
                filePath: unwrapped.filePath,
                message: unwrapped.message
            )
        }
        #expect(storedComparison.idMatch == true)
        #expect(storedComparison.ruleID == "rule2")
        #expect(storedComparison.filePath == "File2.swift")
        #expect(storedComparison.message == "Second message")
    }
    
    @Test("ViolationStorage ensures all violations have unique IDs")
    func testAllViolationsHaveUniqueIDs() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        // Create 100 violations - each should have a unique ID
        let violations = (0..<100).map { index in
            createTestViolation(ruleID: "rule\(index)", filePath: "File\(index).swift")
        }
        
        // Verify all IDs are unique
        let ids = await MainActor.run {
            Set(violations.map { $0.id })
        }
        let uniqueCount1 = await MainActor.run {
            ids.count
        }
        #expect(uniqueCount1 == 100, "All violations should have unique IDs")
        
        try await storage.storeViolations(violations, for: workspaceId)
        
        // Verify all violations were stored
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 100)
        
        // Verify all fetched violations have unique IDs
        let fetchedIDs = await MainActor.run {
            Set(fetched.map { $0.id })
        }
        let uniqueCount2 = await MainActor.run {
            fetchedIDs.count
        }
        #expect(uniqueCount2 == 100, "All fetched violations should have unique IDs")
    }
    
    @Test("ViolationStorage deletes old violations before storing new ones")
    func testStoreViolationsDeletesOldOnes() async throws {
        let storage = try await createIsolatedStorage()
        let workspaceId = UUID()
        
        // Store first set of violations
        let firstViolations = [
            createTestViolation(ruleID: "rule1"),
            createTestViolation(ruleID: "rule2"),
            createTestViolation(ruleID: "rule3")
        ]
        try await storage.storeViolations(firstViolations, for: workspaceId)
        
        // Verify they were stored
        let firstFetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(firstFetched.count == 3)
        
        // Store a different set of violations for the same workspace
        let secondViolations = [
            createTestViolation(ruleID: "rule4"),
            createTestViolation(ruleID: "rule5")
        ]
        try await storage.storeViolations(secondViolations, for: workspaceId)
        
        // Verify only the new violations exist (old ones were deleted)
        let secondFetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        let (count, allMatch, hasRule4, hasRule5, hasRule1, hasRule2, hasRule3) = await MainActor.run {
            (
                secondFetched.count,
                secondFetched.allSatisfy { $0.ruleID == "rule4" || $0.ruleID == "rule5" },
                secondFetched.contains { $0.ruleID == "rule4" },
                secondFetched.contains { $0.ruleID == "rule5" },
                secondFetched.contains { $0.ruleID == "rule1" },
                secondFetched.contains { $0.ruleID == "rule2" },
                secondFetched.contains { $0.ruleID == "rule3" }
            )
        }
        #expect(count == 2)
        #expect(allMatch == true)
        #expect(hasRule4 == true)
        #expect(hasRule5 == true)
        
        // Verify old violations are gone
        #expect(hasRule1 == false)
        #expect(hasRule2 == false)
        #expect(hasRule3 == false)
    }
}

