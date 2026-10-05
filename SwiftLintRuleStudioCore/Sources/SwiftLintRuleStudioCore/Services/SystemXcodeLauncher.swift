//
//  SystemXcodeLauncher.swift
//  SwiftLintRuleStudio
//
//  The launcher the app uses: `/usr/bin/xed` and `NSWorkspace`.
//

import AppKit
import Foundation

/// The real launcher: `/usr/bin/xed` and `NSWorkspace`.
@MainActor
public final class SystemXcodeLauncher: XcodeLaunching {
    // xed is typically in /usr/bin/xed, but can also be accessed via xcode-select
    private let xedPath = "/usr/bin/xed"

    public init() {}

    public func runXed(arguments: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: xedPath) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xedPath)
        process.arguments = arguments
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            // Don't wait for exit - xed opens Xcode asynchronously
            // Return true if process started successfully
            return true
        } catch {
            return false
        }
    }

    public func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
