//
//  MirrorUnsupportedSetupError.swift
//  SwiftLintRuleStudio
//
//  Why a simulation mirror can't reproduce a workspace.
//

import Foundation

/// A setup the mirror can't reproduce faithfully. Rather than measure a count that might be
/// short — and a short count reads as "safe to enable" — the simulation fails with this.
nonisolated struct MirrorUnsupportedSetupError: LocalizedError, Sendable {
    let reason: String

    var errorDescription: String? {
        reason + " The simulation can't reproduce that, so it stopped rather than report a count that might be short."
    }
}
