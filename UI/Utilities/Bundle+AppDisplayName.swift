//
//  Bundle+AppDisplayName.swift
//  SwiftLintRuleStudio
//
//  The user-facing name of whichever edition is running.
//

import Foundation

extension Bundle {
    /// The edition's user-facing name. The sandboxed Explorer target sets a display
    /// name ("Rule Explorer for SwiftLint"); the Studio target sets none.
    var appDisplayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "SwiftLint Rule Studio"
    }
}
