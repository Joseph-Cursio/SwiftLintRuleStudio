//
//  RecordingXcodeLauncher.swift
//  SwiftLintRuleStudioTests
//
//  A launcher double for XcodeIntegrationService tests: it records what the
//  service asked to launch and never starts Xcode.
//

import Foundation
@testable import SwiftLintRuleStudioCore

/// Records every `xed` run and URL open, and answers with configured results.
@MainActor
public final class RecordingXcodeLauncher: XcodeLaunching {
    /// The arguments of each `xed` run, in order
    public private(set) var xedRuns: [[String]] = []
    /// Each URL asked to be opened, in order
    public private(set) var openedURLs: [URL] = []

    /// What `runXed` answers: true means xed started
    public var xedSucceeds: Bool
    /// What `open` answers for an `xcode://` URL
    public var xcodeURLOpens: Bool
    /// What `open` answers for any other URL, such as the file itself
    public var fileURLOpens: Bool

    /// By default xed starts, so the service stops at its first method
    public init(xedSucceeds: Bool = true, xcodeURLOpens: Bool = true, fileURLOpens: Bool = true) {
        self.xedSucceeds = xedSucceeds
        self.xcodeURLOpens = xcodeURLOpens
        self.fileURLOpens = fileURLOpens
    }

    public func runXed(arguments: [String]) -> Bool {
        xedRuns.append(arguments)
        return xedSucceeds
    }

    public func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return url.scheme == "xcode" ? xcodeURLOpens : fileURLOpens
    }
}
