//
//  ConfigWriter.swift
//  SwiftLintRuleStudioCoreTests
//
//  The two ways the engine turns a configuration into text, for tests that must hold for both.
//

import Foundation
@testable import SwiftLintRuleStudioCore

/// `save` edits the file it replaces; `serialize(_:)` writes from scratch, and is what the diff
/// preview, templates and save's own fallback produce.
enum ConfigWriter: String, CaseIterable, Sendable {
    case save
    case serialize

    /// The text `config` becomes, written over `file` for `.save`.
    func text(of config: YAMLConfigurationEngine.YAMLConfig, over file: URL) throws -> String {
        switch self {
        case .save:
            try YAMLConfigurationEngine.save(config, to: file, createBackup: false)
            return try String(contentsOf: file, encoding: .utf8)
        case .serialize:
            return try YAMLConfigurationEngine.serialize(config)
        }
    }
}
