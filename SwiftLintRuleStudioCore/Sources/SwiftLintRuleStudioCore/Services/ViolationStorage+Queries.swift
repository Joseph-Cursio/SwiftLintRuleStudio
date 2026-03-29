import Foundation
import SQLite3

extension ViolationStorageActor {
    public func fetchViolations(
        filter: ViolationFilter,
        workspaceId: UUID?
    ) throws -> [Violation] {
        guard let handle = database else {
            throw ViolationStorageError.databaseNotOpen
        }
        let query = buildFilterQuery(filter: filter, workspaceId: workspaceId)
        let sql = [
            "SELECT id, workspace_id, rule_id, file_path, line, column, severity, message,",
            "detected_at, resolved_at, suppressed, suppression_reason",
            "FROM violations \(query.whereClause)",
            "ORDER BY detected_at DESC;"
        ].joined(separator: " ")

        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }

        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(handle)))
        }

        let bindError = "Failed to allocate memory for parameter"
        try bindParameters(query.parameters, to: statement, errorMessagePrefix: bindError)

        var violations: [Violation] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            if let violation = parseViolation(from: statement) {
                violations.append(violation)
            }
        }

        return violations
    }

    public func getViolationCount(
        filter: ViolationFilter,
        workspaceId: UUID?
    ) throws -> Int {
        guard let handle = database else {
            throw ViolationStorageError.databaseNotOpen
        }
        let query = buildFilterQuery(filter: filter, workspaceId: workspaceId)
        let sql = "SELECT COUNT(*) FROM violations \(query.whereClause);"

        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }

        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(handle)))
        }

        let countError = "Failed to allocate memory for count parameter"
        try bindParameters(query.parameters, to: statement, errorMessagePrefix: countError)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(handle)))
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    private struct FilterQuery {
        let whereClause: String
        let parameters: [Any]
    }

    private func buildFilterQuery(filter: ViolationFilter, workspaceId: UUID?) -> FilterQuery {
        var conditions: [String] = []
        var parameters: [Any] = []

        if let workspaceId = workspaceId {
            conditions.append("workspace_id = ?")
            parameters.append(workspaceId.uuidString)
        }

        if let ruleIDs = filter.ruleIDs, !ruleIDs.isEmpty {
            let placeholders = ruleIDs.map { _ in "?" }.joined(separator: ", ")
            conditions.append("rule_id IN (\(placeholders))")
            parameters.append(contentsOf: ruleIDs)
        }

        if let filePaths = filter.filePaths, !filePaths.isEmpty {
            let placeholders = filePaths.map { _ in "?" }.joined(separator: ", ")
            conditions.append("file_path IN (\(placeholders))")
            parameters.append(contentsOf: filePaths)
        }

        if let severities = filter.severities, !severities.isEmpty {
            let placeholders = severities.map { _ in "?" }.joined(separator: ", ")
            conditions.append("severity IN (\(placeholders))")
            parameters.append(contentsOf: severities.map { $0.rawValue })
        }

        if let suppressedOnly = filter.suppressedOnly {
            conditions.append("suppressed = ?")
            parameters.append(suppressedOnly ? 1 : 0)
        }

        if let dateRange = filter.dateRange {
            conditions.append("detected_at >= ? AND detected_at <= ?")
            parameters.append(dateRange.lowerBound.timeIntervalSince1970)
            parameters.append(dateRange.upperBound.timeIntervalSince1970)
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return FilterQuery(whereClause: whereClause, parameters: parameters)
    }

    private func bindParameters(
        _ parameters: [Any],
        to statement: OpaquePointer?,
        errorMessagePrefix: String
    ) throws {
        for (index, param) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            if let string = param as? String {
                guard let stringCString = strdup(string) else {
                    throw ViolationStorageError.sqlError("\(errorMessagePrefix) \(bindIndex)")
                }
                sqlite3_bind_text(statement, bindIndex, stringCString, -1, free)
            } else if let int = param as? Int {
                sqlite3_bind_int(statement, bindIndex, Int32(int))
            } else if let double = param as? Double {
                sqlite3_bind_double(statement, bindIndex, double)
            }
        }
    }

    private enum ColumnIndex {
        static let violationId: Int32 = 0
        static let ruleId: Int32 = 2
        static let filePath: Int32 = 3
        static let line: Int32 = 4
        static let column: Int32 = 5
        static let severity: Int32 = 6
        static let message: Int32 = 7
        static let detectedAt: Int32 = 8
        static let resolvedAt: Int32 = 9
        static let suppressed: Int32 = 10
        static let suppressionReason: Int32 = 11
    }

    private func parseViolation(from statement: OpaquePointer?) -> Violation? {
        guard let idString = sqlite3_column_text(statement, ColumnIndex.violationId),
              let id = UUID(uuidString: String(cString: idString)),
              let ruleID = sqlite3_column_text(statement, ColumnIndex.ruleId),
              let filePath = sqlite3_column_text(statement, ColumnIndex.filePath),
              let severityString = sqlite3_column_text(statement, ColumnIndex.severity),
              let message = sqlite3_column_text(statement, ColumnIndex.message) else {
            return nil
        }

        let line = Int(sqlite3_column_int(statement, ColumnIndex.line))
        let column = sqlite3_column_type(statement, ColumnIndex.column) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int(statement, ColumnIndex.column))
        let detectedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, ColumnIndex.detectedAt))
        let resolvedAt = sqlite3_column_type(statement, ColumnIndex.resolvedAt) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, ColumnIndex.resolvedAt))
        let suppressed = sqlite3_column_int(statement, ColumnIndex.suppressed) != 0
        let suppressionReason = sqlite3_column_type(statement, ColumnIndex.suppressionReason) == SQLITE_NULL
            ? nil
            : String(cString: sqlite3_column_text(statement, ColumnIndex.suppressionReason))
        let severity = Severity(rawValue: String(cString: severityString)) ?? .warning

        return Violation(
            id: id,
            ruleID: String(cString: ruleID),
            filePath: String(cString: filePath),
            line: line,
            column: column,
            severity: severity,
            message: String(cString: message),
            detectedAt: detectedAt,
            resolvedAt: resolvedAt,
            suppressed: suppressed,
            suppressionReason: suppressionReason
        )
    }
}
