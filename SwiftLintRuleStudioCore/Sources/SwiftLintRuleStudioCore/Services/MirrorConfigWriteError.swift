//
//  MirrorConfigWriteError.swift
//  SwiftLintRuleStudio
//
//  A config the simulation wrote that SwiftLint couldn't read.
//

import Foundation
import Yams

/// The simulation wrote a config into its mirror that SwiftLint can't read. SwiftLint would
/// replace it with its defaults — and every rule would then measure as if nothing were
/// configured, often 0, which reads as "safe to enable" — so nothing is measured.
nonisolated struct MirrorConfigWriteError: LocalizedError, Sendable {
    /// The config's path relative to the mirror's lint root.
    let path: String
    let detail: String

    var errorDescription: String? {
        "The simulation couldn't write a configuration SwiftLint can read (\(path): \(detail)), so it stopped "
            + "rather than lint with SwiftLint's defaults in its place."
    }

    /// Reads the config at `url` back as SwiftLint will — YAML holding a mapping, or nothing —
    /// and throws when it can't be.
    static func checkReadable(_ url: URL, writtenFor path: String) throws {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw Self(path: path, detail: error.localizedDescription)
        }
        let value: Any?
        do {
            value = try Yams.load(yaml: text)
        } catch {
            // Yams's message runs to several lines, quoting the YAML; the first says what's wrong.
            let message = String(describing: error).split(separator: "\n").first.map(String.init) ?? "\(error)"
            throw Self(path: path, detail: message)
        }
        guard value == nil || value is [String: Any] else {
            throw Self(path: path, detail: "not a mapping of keys to values")
        }
    }
}
