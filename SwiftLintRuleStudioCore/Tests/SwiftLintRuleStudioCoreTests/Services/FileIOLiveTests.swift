//
//  FileIOLiveTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The real file system's `copy`, which takes the safety backup before a restore: it must
//  never overwrite a backup, and must make the store folder a restore may be the first to need.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct FileIOLiveTests {

    @Test("copy creates the destination's folder and never overwrites")
    func copyCreatesFoldersAndNeverOverwrites() throws {
        let directory = TestTempDirectory.make("fileio")
        let source = directory.appendingPathComponent("source.yml")
        try "new\n".write(to: source, atomically: true, encoding: .utf8)

        let fresh = directory.appendingPathComponent("a/b/copy.yml")
        try FileIO.live.copy(source, fresh)
        #expect(try String(contentsOf: fresh, encoding: .utf8) == "new\n")

        let existing = directory.appendingPathComponent("existing.yml")
        try "kept\n".write(to: existing, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try FileIO.live.copy(source, existing) }
        #expect(try String(contentsOf: existing, encoding: .utf8) == "kept\n")
    }
}
