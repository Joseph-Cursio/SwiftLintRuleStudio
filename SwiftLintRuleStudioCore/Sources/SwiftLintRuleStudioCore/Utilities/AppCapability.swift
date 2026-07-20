//
//  AppCapability.swift
//  SwiftLintRuleStudio
//
//  Edition-specific capabilities the shared UI conditions on. The non-sandboxed
//  Studio target has all of them; the sandboxed Explorer target has none of these
//  external-tool integrations (the App Sandbox blocks launching other executables,
//  and SwiftLint is linked in-process rather than detected on disk).
//

import Foundation

public enum AppCapability: String, Sendable, Hashable, CaseIterable {
    /// Detect and use an externally-installed `swiftlint` binary (subprocess
    /// edition). Absent in the in-process edition, where SwiftLint is linked in
    /// and there is nothing to detect.
    case detectInstalledSwiftLint

    /// Open files in Xcode via the `xed` command-line tool. Absent under the App
    /// Sandbox, which blocks launching external executables.
    case openInXcode

    /// Evaluate SourceKit-backed rules during in-app linting. Absent in the
    /// sandboxed edition, where SourceKit cannot load (the in-process backend
    /// sets `SWIFTLINT_DISABLE_SOURCEKIT`), so these rules produce no violations.
    /// When absent, the UI marks such rules as unavailable rather than pretending
    /// they run — see `Rule.isUnavailableForLinting(capabilities:)`.
    case sourceKitRules
}
