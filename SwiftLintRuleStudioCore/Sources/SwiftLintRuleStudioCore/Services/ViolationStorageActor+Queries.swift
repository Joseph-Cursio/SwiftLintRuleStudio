import Foundation

extension ViolationStorageActor {
    /// Fetch violations matching the given filter criteria
    public func fetchViolations(
        filter: ViolationFilter,
        workspaceId: UUID?
    ) throws -> [Violation] {
        guard let database else {
            throw ViolationStorageError.databaseNotOpen
        }
        let query = buildFilterQuery(filter: filter, workspaceId: workspaceId)
        let sql = [
            "SELECT id, workspace_id, rule_id, file_path, line, column, severity, message,",
            "detected_at, resolved_at, suppressed, suppression_reason",
            "FROM violations \(query.whereClause)",
            "ORDER BY detected_at DESC;"
        ].joined(separator: " ")

        let statement = try database.prepare(sql)
        bindParameters(query.parameters, to: statement)

        var violations: [Violation] = []
        while statement.step() == .row {
            if let violation = parseViolation(from: statement) {
                violations.append(violation)
            }
        }
        return violations
    }

    /// Get the count of violations matching the given filter criteria
    public func getViolationCount(
        filter: ViolationFilter,
        workspaceId: UUID?
    ) throws -> Int {
        guard let database else {
            throw ViolationStorageError.databaseNotOpen
        }
        let query = buildFilterQuery(filter: filter, workspaceId: workspaceId)
        let sql = "SELECT COUNT(*) FROM violations \(query.whereClause);"

        let statement = try database.prepare(sql)
        bindParameters(query.parameters, to: statement)

        guard statement.step() == .row else {
            throw ViolationStorageError.sqlError(database.lastErrorMessage)
        }
        return statement.columnInt(at: 0)
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
            parameters.append(contentsOf: severities.map(\.rawValue))
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

    private func bindParameters(_ parameters: [Any], to statement: SQLiteStatement) {
        for (index, param) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            if let string = param as? String {
                statement.bind(string, at: bindIndex)
            } else if let int = param as? Int {
                statement.bind(Int32(int), at: bindIndex)
            } else if let double = param as? Double {
                statement.bind(double, at: bindIndex)
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

    private func parseViolation(from statement: SQLiteStatement) -> Violation? {
        guard let idString = statement.columnText(at: ColumnIndex.violationId),
              let id = UUID(uuidString: idString),
              let ruleID = statement.columnText(at: ColumnIndex.ruleId),
              let filePath = statement.columnText(at: ColumnIndex.filePath),
              let severityString = statement.columnText(at: ColumnIndex.severity),
              let message = statement.columnText(at: ColumnIndex.message) else {
            return nil
        }

        let line = statement.columnInt(at: ColumnIndex.line)
        let column = statement.columnIsNull(at: ColumnIndex.column)
            ? nil
            : statement.columnInt(at: ColumnIndex.column)
        let detectedAt = Date(timeIntervalSince1970: statement.columnDouble(at: ColumnIndex.detectedAt))
        let resolvedAt = statement.columnIsNull(at: ColumnIndex.resolvedAt)
            ? nil
            : Date(timeIntervalSince1970: statement.columnDouble(at: ColumnIndex.resolvedAt))
        let suppressed = statement.columnInt(at: ColumnIndex.suppressed) != 0
        let suppressionReason = statement.columnIsNull(at: ColumnIndex.suppressionReason)
            ? nil
            : statement.columnText(at: ColumnIndex.suppressionReason)
        let severity = Severity(rawValue: severityString) ?? .warning

        return Violation(
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            severity: severity,
            message: message,
            id: id,
            column: column,
            detectedAt: detectedAt,
            resolvedAt: resolvedAt,
            suppressed: suppressed,
            suppressionReason: suppressionReason
        )
    }
}
