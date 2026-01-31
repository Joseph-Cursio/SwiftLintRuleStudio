//
//  ViolationStorageSQLTests.swift
//  SwiftLIntRuleStudioTests
//
//  SQL error tests for ViolationStorage
//

import Testing
@testable import SwiftLIntRuleStudio

struct ViolationStorageSQLTests {
    @Test("ViolationStorage executeSQL throws when database is closed")
    func testExecuteSQLDatabaseClosed() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        await storage.closeDatabase()

        await #expect(throws: ViolationStorageError.self) {
            try await storage.executeSQL("SELECT 1;")
        }
    }

    @Test("ViolationStorage executeSQL throws on invalid SQL")
    func testExecuteSQLInvalidSQL() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()

        await #expect(throws: ViolationStorageError.self) {
            try await storage.executeSQL("INVALID SQL STATEMENT")
        }
    }

    @Test("ViolationStorage executeSQL throws on step error")
    func testExecuteSQLStepError() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()

        try await storage.executeSQL("CREATE TABLE test_table (id INTEGER NOT NULL);")
        await #expect(throws: ViolationStorageError.self) {
            try await storage.executeSQL("INSERT INTO test_table (id) VALUES (NULL);")
        }
    }

    @Test("ViolationStorageError provides descriptions")
    func testViolationStorageErrorDescriptions() {
        let notOpen = ViolationStorageError.databaseNotOpen
        #expect(notOpen.errorDescription?.contains("not open") == true)

        let openFailed = ViolationStorageError.databaseOpenFailed("boom")
        #expect(openFailed.errorDescription?.contains("boom") == true)

        let sqlError = ViolationStorageError.sqlError("bad SQL")
        #expect(sqlError.errorDescription?.contains("bad SQL") == true)
    }
}
