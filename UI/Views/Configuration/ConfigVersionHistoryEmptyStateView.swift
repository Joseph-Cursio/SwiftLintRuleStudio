//
//  ConfigVersionHistoryEmptyStateView.swift
//  SwiftLintRuleStudio
//

import SwiftUI

struct ConfigVersionHistoryEmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Version History", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Configuration backups will appear here after you save changes.")
        }
    }
}
