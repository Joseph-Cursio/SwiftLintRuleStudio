//
//  RuleParameterValues.swift
//  SwiftLintRuleStudio
//
//  Resolves typed parameter values for the rule parameter editor.
//  Encapsulates the read-with-default fallback chain and array-item
//  normalization that previously lived inline in SwiftUI Binding closures,
//  so the logic can be unit-tested independently of the view layer.
//

import Foundation

/// Mutable wrapper around a `[String: AnyCodable]` parameter dictionary that
/// resolves typed values for a `RuleParameter`, falling back to the
/// parameter's `defaultValue` and then to a type-appropriate zero value
/// when no usable value is available.
public struct RuleParameterValues: Sendable {
    /// Underlying parameter storage. Reads and writes flow through this dictionary
    /// so callers can round-trip the wrapper back into the source of truth.
    public var values: [String: AnyCodable]

    public init(values: [String: AnyCodable] = [:]) {
        self.values = values
    }

    // MARK: - Typed Readers

    /// Returns the stored `Int` for `param`, the parameter's default `Int`, or `0`.
    public func intValue(for param: RuleParameter) -> Int {
        if let stored = values[param.name]?.value as? Int {
            return stored
        }
        return param.defaultValue.value as? Int ?? 0
    }

    /// Returns the stored `Bool` for `param`, the parameter's default `Bool`, or `false`.
    public func boolValue(for param: RuleParameter) -> Bool {
        if let stored = values[param.name]?.value as? Bool {
            return stored
        }
        return param.defaultValue.value as? Bool ?? false
    }

    /// Returns the stored `String` for `param`, the parameter's default `String`, or `""`.
    public func stringValue(for param: RuleParameter) -> String {
        if let stored = values[param.name]?.value as? String {
            return stored
        }
        return param.defaultValue.value as? String ?? ""
    }

    /// Returns a `[String]` view of the stored value (mapped via `String(describing:)`),
    /// falling back to the same conversion of the parameter's default, then to `[]`.
    ///
    /// The `String(describing:)` mapping mirrors the original Binding behavior so that
    /// numeric/heterogeneous defaults (e.g. `[Int]`) surface as user-editable strings
    /// rather than being silently dropped.
    public func arrayValue(for param: RuleParameter) -> [String] {
        if let stored = values[param.name]?.value as? [Any] {
            return stored.map { String(describing: $0) }
        }
        if let fallback = param.defaultValue.value as? [Any] {
            return fallback.map { String(describing: $0) }
        }
        return []
    }

    // MARK: - Writer

    /// Wraps `raw` in an `AnyCodable` and stores it under `param.name`,
    /// replacing any existing entry. Used by the editor's `Binding.set` closures.
    public mutating func setValue(_ raw: Any, for param: RuleParameter) {
        values[param.name] = AnyCodable(raw)
    }

    // MARK: - Array Item Normalization

    /// Trims surrounding whitespace from `raw` and returns the result,
    /// or `nil` if the trimmed string is empty.
    ///
    /// Used by the array-item add flow to reject whitespace-only entries
    /// without coupling that policy to the view.
    public static func sanitizedArrayItem(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
