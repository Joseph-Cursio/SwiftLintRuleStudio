//
//  TagResolutionHarness.swift
//  SwiftLintRuleStudio
//
//  The switch for `TagResolutionHarnessView`, kept beside `TestGuard` so every
//  "am I running under a UI test?" check lives in one place.
//

import Foundation

enum TagResolutionHarness {
    /// True only under `-uiTesting` with `UI_TEST_TAG_HARNESS=1`, so the harness cannot appear in
    /// a normal launch even if the environment variable is set by accident.
    static var isEnabled: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("-uiTesting")
            && processInfo.environment["UI_TEST_TAG_HARNESS"] == "1"
    }
}
