//
//  ResolvedRuleRow.swift
//  SwiftLintRuleStudio
//

/// One rule's row in the resolved-config inspector.
public struct ResolvedRuleRow: Identifiable, Sendable {
    /// The rule identifier (also the row id).
    nonisolated public let id: String
    /// Human-readable state: `off (disabled)`, `on (opt-in)`, `warning`, `error`,
    /// `configured`, `analyzer`.
    nonisolated public let state: String
    /// The layer that set this state (`root`, `Tests`).
    nonisolated public let setBy: String
    /// Optional override detail (`overrides root`), or nil.
    nonisolated public let detail: String?

    nonisolated public var ruleIdentifier: String { id }

    nonisolated public init(id: String, state: String, setBy: String, detail: String?) {
        self.id = id
        self.state = state
        self.setBy = setBy
        self.detail = detail
    }
}
