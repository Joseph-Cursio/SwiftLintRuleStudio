//
//  SafeRulesDiscoveryView+Subviews.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

extension SafeRulesDiscoveryView {
    var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discover Safe Rules")
                .font(.title2)
                .fontWeight(.bold)

            Text("Find disabled rules that would produce zero violations if enabled")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                discoverSafeRules()
            } label: {
                Label("Discover Safe Rules", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDiscovering || dependencies.workspaceManager.currentWorkspace == nil)
            .accessibilityIdentifier("SafeRulesDiscoverButton")
        }
        .padding()
    }

    var discoveringView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            if let progress = discoveryProgress {
                Text("Analyzing rule \(progress.current) of \(progress.total)")
                    .font(.headline)

                Text("Checking: \(progress.ruleId)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .frame(width: 400)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Safe Rules Discovered")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Click 'Discover Safe Rules' to analyze disabled rules in your workspace")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var rulesListView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Found \(safeRules.count) safe rule\(safeRules.count == 1 ? "" : "s")")
                    .font(.headline)

                Spacer()

                Button {
                    selectedRules = Set(safeRules.map { $0.ruleId })
                } label: {
                    Text("Select All")
                }
                .buttonStyle(.bordered)

                Button {
                    selectedRules.removeAll()
                } label: {
                    Text("Deselect All")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            List {
                ForEach(safeRules, id: \.ruleId) { ruleResult in
                    SafeRuleRow(
                        ruleResult: ruleResult,
                        isSelected: selectedRules.contains(ruleResult.ruleId),
                        onToggle: {
                            toggleSelection(for: ruleResult.ruleId)
                        }
                    )
                }
            }
        }
    }
}
