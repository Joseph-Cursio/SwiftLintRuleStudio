//
//  SafeRulesDiscoveryView.swift
//  SwiftLintRuleStudio
//
//  View for discovering and bulk-enabling safe rules (zero violations)
//

import SwiftUI

struct SafeRulesDiscoveryView: View {
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @ScaledMetric(relativeTo: .largeTitle) var iconSizeLarge: CGFloat = 64

    @State var isDiscovering = false
    @State var discoveryProgress: DiscoveryProgress?
    @State var safeRules: [RuleImpactResult] = []
    @State var selectedRules: Set<String> = []
    @State var isEnabling = false
    @State var showError = false
    @State var errorMessage: String?

    init() {}

    init(
        safeRules: [RuleImpactResult],
        selectedRules: Set<String> = [],
        isDiscovering: Bool = false,
        discoveryProgress: DiscoveryProgress? = nil
    ) {
        _safeRules = State(initialValue: safeRules)
        _selectedRules = State(initialValue: selectedRules)
        _isDiscovering = State(initialValue: isDiscovering)
        _discoveryProgress = State(initialValue: discoveryProgress)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                Divider()
                mainContent
            }
            .navigationTitle("Safe Rules Discovery")
            .toolbar { discoveryToolbar }
        }
        .frame(width: 800, height: 600)
        .alert("Error", isPresented: TestGuard.alertBinding($showError)) {
            Button("OK") {
                errorMessage = nil
                showError = false
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isDiscovering {
            discoveringView
        } else if safeRules.isEmpty {
            emptyStateView
        } else {
            rulesListView
        }
    }

    @ToolbarContentBuilder
    private var discoveryToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                dismiss()
            }
        }

        if !safeRules.isEmpty {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    enableSelectedRules()
                } label: {
                    if isEnabling {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Enable Selected (\(selectedRules.count))")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRules.isEmpty || isEnabling)
            }
        }
    }
}

#Preview {
    SafeRulesDiscoveryView()
        .environment(\.dependencies, DependencyContainer())
}
