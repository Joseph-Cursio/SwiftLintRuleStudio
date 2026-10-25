//
//  LintReportDecoder.swift
//  SwiftLintRuleStudio
//
//  Reads SwiftLint's JSON report off the main actor.
//

import Foundation

/// One violation as SwiftLint's JSON report gives it, with its path made relative to the
/// workspace — or put back at its real place, for a file in a mirrored outside folder.
nonisolated struct DecodedViolation: Sendable {
    let ruleID: String
    let filePath: String
    let line: Int
    /// Nil for a line-level violation.
    let column: Int?
    /// As reported, lowercased; `Severity`'s raw value.
    let severity: String
    let message: String
}

/// Reads SwiftLint's JSON report.
///
/// A simulation's report carries every enabled rule's violations, not just the simulated
/// one's — tens of megabytes on a large workspace — so it is read off the main actor, keeping
/// only the rule asked for.
nonisolated enum LintReportDecoder {
    @concurrent
    static func decodeOffMainActor(
        _ data: Data,
        workspacePath: URL,
        mapping: MirrorPathMapping?,
        ruleIds: Set<String>?
    ) async throws -> [DecodedViolation] {
        try decode(data, workspacePath: workspacePath, mapping: mapping, ruleIds: ruleIds)
    }

    /// The report's violations — of `ruleIds` alone when given.
    static func decode(
        _ data: Data,
        workspacePath: URL,
        mapping: MirrorPathMapping?,
        ruleIds: Set<String>?
    ) throws -> [DecodedViolation] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        // SwiftLint spells a path under a firmlink such as `/var` either way — as
        // `/private/var/…` once it has resolved a link on the way — so a path is under the
        // workspace in any of its spellings.
        let workspaceSpellings = spellings(of: workspacePath.path)

        return json.compactMap { item in
            guard let reportedRule = item["rule_id"] as? String,
                  ruleIds?.contains(reportedRule) ?? true,
                  let reason = item["reason"] as? String,
                  let severity = item["severity"] as? String,
                  let file = item["file"] as? String else { return nil }

            let fullPath = URL(fileURLWithPath: file).path
            let relativePath: String
            if let root = workspaceSpellings.first(where: { fullPath.hasPrefix($0 + "/") }) {
                relativePath = String(fullPath.dropFirst(root.count + 1))
            } else {
                relativePath = mapping?.originalPath(of: fullPath) ?? file
            }
            // SwiftLint's JSON reporter names the column "character", as WorkspaceAnalyzer reads it.
            return DecodedViolation(
                ruleID: reportedRule,
                filePath: relativePath,
                line: item["line"] as? Int ?? 0,
                column: item["character"] as? Int,
                severity: severity.lowercased(),
                message: reason
            )
        }
    }

    /// `path` as itself, resolved, and with or without the `/private` prefix macOS hides.
    private static func spellings(of path: String) -> [String] {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var spellings = [path, resolved]
        for spelling in [path, resolved] {
            let isPrivate = spelling.hasPrefix("/private/")
            spellings.append(isPrivate ? String(spelling.dropFirst("/private".count)) : "/private" + spelling)
        }
        return spellings.reduce(into: []) { unique, spelling in
            if !unique.contains(spelling) { unique.append(spelling) }
        }
    }
}
