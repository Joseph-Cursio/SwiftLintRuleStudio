//
//  SQLiteDatabaseTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Opening the violations database, and running a prepared statement again.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct SQLiteDatabaseTests {
    /// What opening the database at `path` fails with, or nil when it opens.
    private func openFailure(at path: URL, useInMemory: Bool = false) -> String? {
        do {
            _ = try SQLiteDatabase.open(at: path, useInMemory: useInMemory)
            return nil
        } catch ViolationStorageError.databaseOpenFailed(let message) {
            return message
        } catch {
            return "\(error)"
        }
    }

    @Test("a database file opens in a folder that exists, and is refused naming the folder in one that doesn't")
    func openingAFile() {
        let folder = TestTempDirectory.make("sqlite")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("violations.db")
        let missing = folder.appendingPathComponent("Missing", isDirectory: true)

        #expect(openFailure(at: file) == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(openFailure(at: missing.appendingPathComponent("violations.db"))
            == "Database directory does not exist: \(missing.path)")
    }

    @Test("an in-memory database opens whatever path it is given")
    func inMemoryIgnoresThePath() {
        let nowhere = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/violations.db")

        #expect(openFailure(at: nowhere, useInMemory: true) == nil)
    }

    @Test("a path SQLite can't open is refused with SQLite's own reason")
    func sqliteGivesTheReason() {
        let folder = TestTempDirectory.make("sqlite")
        defer { try? FileManager.default.removeItem(at: folder) }

        // A folder, which exists, is no database file.
        #expect(openFailure(at: folder) == "Failed to open database at '\(folder.path)': unable to open database file")
    }

    @Test("resetting a statement clears its bindings, unless it is asked to keep them")
    func resetClearsBindings() throws {
        let database = try SQLiteDatabase.open(at: URL(fileURLWithPath: ":memory:"), useInMemory: true)
        let statement = try database.prepare("SELECT ?")
        statement.bind(Int32(42), at: 1)
        let selected = { () -> Int? in
            guard statement.step() == .row, !statement.columnIsNull(at: 0) else { return nil }
            return statement.columnInt(at: 0)
        }

        #expect(selected() == 42)
        statement.reset(clearingBindings: false)
        #expect(selected() == 42)
        statement.reset()
        #expect(selected() == nil, "an unbound parameter is NULL")
    }

    @Test("the storage's database is the file given, and none in memory")
    func storageDatabasePath() throws {
        let given = URL(fileURLWithPath: "/tmp/violations-\(UUID().uuidString).db")
        let inMemory = URL(fileURLWithPath: ":memory:")

        #expect(try ViolationStorageActor.resolveDatabasePath(databasePath: given, useInMemory: false) == given)
        #expect(try ViolationStorageActor.resolveDatabasePath(databasePath: given, useInMemory: true) == inMemory)
    }
}
