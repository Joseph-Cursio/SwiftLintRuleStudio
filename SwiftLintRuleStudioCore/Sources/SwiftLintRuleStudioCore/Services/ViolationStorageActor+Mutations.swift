import Foundation

/// A finding's cross-run identity, used to carry suppression/resolution state
/// forward when a re-analysis re-reports the same issue. Two violations are "the
/// same finding" when they share rule, file, line, and message — deliberately
/// excluding `id` (regenerated every parse), `column`, and `severity`, none of
/// which identify the underlying issue.
private extension Violation {
    nonisolated var contentKey: String {
        Self.contentKey(ruleID: ruleID, filePath: filePath, line: line, message: message)
    }

    nonisolated static func contentKey(ruleID: String, filePath: String, line: Int, message: String) -> String {
        [ruleID, filePath, String(line), message].joined(separator: "\u{1}")
    }
}

extension ViolationStorageActor {
    /// Store violations for a workspace, reconciling against any existing rows.
    ///
    /// Findings the analysis no longer reports are removed, and suppression/
    /// resolution state (plus first-seen `detectedAt`) is carried forward for
    /// findings that are still reported — so re-running analysis never silently
    /// discards a user's suppress/resolve decisions.
    public func storeViolations(_ violations: [Violation], for workspaceId: UUID) throws {
        guard let database else {
            throw ViolationStorageError.databaseNotOpen
        }

        // Use transaction for performance
        try executeSQL("BEGIN TRANSACTION")

        var transactionCommitted = false
        defer {
            if !transactionCommitted {
                // Only rollback if we didn't commit successfully
                try? executeSQL("ROLLBACK")
            }
        }

        // Read the prior state *before* deleting, then carry it forward onto the
        // freshly-reported findings that match by content.
        let preservedState = try existingStateByContentKey(for: workspaceId, in: database)
        let reconciled = violations.map { carryingForwardState($0, from: preservedState) }

        let deleted = try deleteExistingViolations(for: workspaceId, in: database)
        logDeletedViolations(deleted)

        let statement = try prepareInsertStatement(in: database)

        let insertionResult = try insertViolations(
            reconciled,
            workspaceId: workspaceId,
            in: database,
            statement: statement
        )
        logDuplicateViolations(insertionResult, total: reconciled.count)

        // Commit transaction
        try executeSQL("COMMIT")
        transactionCommitted = true
    }

    /// The suppression/resolution state of a finding as it currently stands in storage.
    private struct PreservedViolationState {
        let detectedAt: Date
        let resolvedAt: Date?
        let suppressed: Bool
        let suppressionReason: String?
    }

    /// Snapshot the current per-finding state for a workspace, keyed by content, so
    /// it can be reapplied to the next analysis's freshly-reported findings.
    private func existingStateByContentKey(
        for workspaceId: UUID,
        in database: SQLiteDatabase
    ) throws -> [String: PreservedViolationState] {
        let sql = """
        SELECT rule_id, file_path, line, message, detected_at, resolved_at, suppressed, suppression_reason
        FROM violations WHERE workspace_id = ?;
        """
        let statement = try database.prepare(sql)
        statement.bind(workspaceId.uuidString, at: 1)

        var stateByKey: [String: PreservedViolationState] = [:]
        while statement.step() == .row {
            guard let ruleID = statement.columnText(at: 0),
                  let filePath = statement.columnText(at: 1),
                  let message = statement.columnText(at: 3) else {
                continue
            }
            let line = statement.columnInt(at: 2)
            let key = Violation.contentKey(ruleID: ruleID, filePath: filePath, line: line, message: message)
            // Duplicate findings (same content, different column) are indistinguishable;
            // the first one's state is representative.
            guard stateByKey[key] == nil else { continue }

            let detectedAt = Date(timeIntervalSince1970: statement.columnDouble(at: 4))
            let resolvedAt = statement.columnIsNull(at: 5)
                ? nil
                : Date(timeIntervalSince1970: statement.columnDouble(at: 5))
            let suppressed = statement.columnInt(at: 6) != 0
            let reason = statement.columnIsNull(at: 7) ? nil : statement.columnText(at: 7)
            stateByKey[key] = PreservedViolationState(
                detectedAt: detectedAt,
                resolvedAt: resolvedAt,
                suppressed: suppressed,
                suppressionReason: reason
            )
        }
        return stateByKey
    }

    /// Reapply preserved state to a freshly-reported finding. A finding with no prior
    /// match is stored as-is (a genuinely new, unsuppressed violation).
    private func carryingForwardState(
        _ violation: Violation,
        from preservedState: [String: PreservedViolationState]
    ) -> Violation {
        guard let state = preservedState[violation.contentKey] else {
            return violation
        }
        return Violation(
            ruleID: violation.ruleID,
            filePath: violation.filePath,
            line: violation.line,
            severity: violation.severity,
            message: violation.message,
            id: violation.id,
            column: violation.column,
            detectedAt: state.detectedAt,
            resolvedAt: state.resolvedAt,
            suppressed: state.suppressed,
            suppressionReason: state.suppressionReason
        )
    }

    private struct InsertionResult {
        let insertedCount: Int
        let duplicateIDs: Set<String>
        let uniqueCount: Int
    }

    private func insertViolations(
        _ violations: [Violation],
        workspaceId: UUID,
        in database: SQLiteDatabase,
        statement: SQLiteStatement
    ) throws -> InsertionResult {
        var insertedCount = 0
        var seenIDs = Set<String>()
        var duplicateIDs = Set<String>()

        for (index, violation) in violations.enumerated() {
            if index > 0 {
                statement.reset()
            }
            trackDuplicateIDs(
                violation: violation,
                index: index,
                seenIDs: &seenIDs,
                duplicateIDs: &duplicateIDs
            )

            bindViolation(violation, workspaceId: workspaceId, statement: statement)

            if statement.step() == .done {
                insertedCount += 1
            } else {
                let errorMsg = database.lastErrorMessage
                statement.reset()
                throw ViolationStorageError.sqlError("Failed to insert violation at index \(index): \(errorMsg)")
            }
        }

        return InsertionResult(
            insertedCount: insertedCount,
            duplicateIDs: duplicateIDs,
            uniqueCount: seenIDs.count
        )
    }

    private func trackDuplicateIDs(
        violation: Violation,
        index _: Int,
        seenIDs: inout Set<String>,
        duplicateIDs: inout Set<String>
    ) {
        let idString = violation.id.uuidString
        if seenIDs.contains(idString) {
            duplicateIDs.insert(idString)
        } else {
            seenIDs.insert(idString)
        }
    }

    private func logDeletedViolations(_: Int) {
        // Intentionally empty - violation count tracked internally
    }

    private func logDuplicateViolations(_: InsertionResult, total _: Int) {
        // Intentionally empty - duplicate tracking handled by InsertionResult
    }

    private func deleteExistingViolations(for workspaceId: UUID, in database: SQLiteDatabase) throws -> Int {
        let statement = try database.prepare("DELETE FROM violations WHERE workspace_id = ?;")
        statement.bind(workspaceId.uuidString, at: 1)
        guard statement.step() == .done else {
            throw ViolationStorageError.sqlError(database.lastErrorMessage)
        }
        return database.changes
    }

    private func prepareInsertStatement(in database: SQLiteDatabase) throws -> SQLiteStatement {
        let insertSQL = """
        INSERT OR REPLACE INTO violations
        (id, workspace_id, rule_id, file_path, line, column, severity, message,
         detected_at, resolved_at, suppressed, suppression_reason)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        return try database.prepare(insertSQL)
    }

    private func bindViolation(_ violation: Violation, workspaceId: UUID, statement: SQLiteStatement) {
        statement.bind(violation.id.uuidString, at: 1)
        statement.bind(workspaceId.uuidString, at: 2)
        statement.bind(violation.ruleID, at: 3)
        statement.bind(violation.filePath, at: 4)
        statement.bind(Int32(violation.line), at: 5)
        if let column = violation.column {
            statement.bind(Int32(column), at: 6)
        } else {
            statement.bindNull(at: 6)
        }
        statement.bind(violation.severity.rawValue, at: 7)
        statement.bind(violation.message, at: 8)
        statement.bind(violation.detectedAt.timeIntervalSince1970, at: 9)
        if let resolvedAt = violation.resolvedAt {
            statement.bind(resolvedAt.timeIntervalSince1970, at: 10)
        } else {
            statement.bindNull(at: 10)
        }
        statement.bind(Int32(violation.suppressed ? 1 : 0), at: 11)
        if let reason = violation.suppressionReason {
            statement.bind(reason, at: 12)
        } else {
            statement.bindNull(at: 12)
        }
    }

    /// Binds each violation ID to `statement` (starting at `startIndex`), then executes
    /// it and verifies completion. SQLite copies each bound string immediately
    /// (`SQLITE_TRANSIENT`), so no manual buffer management is needed.
    private func bindIDsAndExecute(
        _ statement: SQLiteStatement,
        in database: SQLiteDatabase,
        violationIds: [UUID],
        startIndex: Int32
    ) throws {
        for (index, identifier) in violationIds.enumerated() {
            statement.bind(identifier.uuidString, at: startIndex + Int32(index))
        }
        guard statement.step() == .done else {
            throw ViolationStorageError.sqlError(database.lastErrorMessage)
        }
    }

    /// Mark violations as suppressed with the given reason
    public func suppressViolations(_ violationIds: [UUID], reason: String) throws {
        guard let database else {
            throw ViolationStorageError.databaseNotOpen
        }

        let placeholders = violationIds.map { _ in "?" }.joined(separator: ", ")
        let sql = "UPDATE violations SET suppressed = 1, suppression_reason = ? WHERE id IN (\(placeholders));"

        let statement = try database.prepare(sql)
        statement.bind(reason, at: 1)
        try bindIDsAndExecute(statement, in: database, violationIds: violationIds, startIndex: 2)
    }

    /// Mark violations as resolved with the current timestamp
    public func resolveViolations(_ violationIds: [UUID]) throws {
        guard let database else {
            throw ViolationStorageError.databaseNotOpen
        }

        let placeholders = violationIds.map { _ in "?" }.joined(separator: ", ")
        let sql = "UPDATE violations SET resolved_at = ? WHERE id IN (\(placeholders));"

        let statement = try database.prepare(sql)
        statement.bind(Date.now.timeIntervalSince1970, at: 1)
        try bindIDsAndExecute(statement, in: database, violationIds: violationIds, startIndex: 2)
    }

    /// Delete all violations for a workspace
    public func deleteViolations(for workspaceId: UUID) throws {
        guard let database else {
            throw ViolationStorageError.databaseNotOpen
        }

        let statement = try database.prepare("DELETE FROM violations WHERE workspace_id = ?;")
        statement.bind(workspaceId.uuidString, at: 1)
        guard statement.step() == .done else {
            throw ViolationStorageError.sqlError(database.lastErrorMessage)
        }
    }
}
