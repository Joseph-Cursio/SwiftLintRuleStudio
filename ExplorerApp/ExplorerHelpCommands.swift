//
//  ExplorerHelpCommands.swift
//  SwiftLintRuleExplorer
//
//  Help menu for the sandboxed edition.
//

import SwiftUI

/// Replaces the default Help menu item, which only reports that help isn't
/// available, with one that opens the in-app help window.
struct ExplorerHelpCommands: Commands {
    static let windowID = "help"

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("\(Bundle.main.appDisplayName) Help") {
                openWindow(id: Self.windowID)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
