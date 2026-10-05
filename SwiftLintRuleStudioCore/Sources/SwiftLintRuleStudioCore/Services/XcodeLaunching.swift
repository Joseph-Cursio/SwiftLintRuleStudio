//
//  XcodeLaunching.swift
//  SwiftLintRuleStudio
//
//  The side effects of opening a file in Xcode, behind a seam. The service
//  decides what to open; a launcher does it. Tests inject a recording double, so
//  no test ever starts Xcode or asks Launch Services to open a temporary file
//  that is deleted before Xcode gets to it.
//

import Foundation

/// Launches Xcode, or whatever opens a URL, on behalf of `XcodeIntegrationService`.
@MainActor
public protocol XcodeLaunching: AnyObject {
    /// Run `xed` with these arguments, without waiting for it to exit.
    /// - Returns: False when `xed` is not installed or could not be started.
    func runXed(arguments: [String]) -> Bool

    /// Open a URL with the application registered for it.
    /// - Returns: Whether Launch Services accepted the request.
    func open(_ url: URL) -> Bool
}
