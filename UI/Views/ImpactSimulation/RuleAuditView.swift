//
//  RuleAuditView.swift
//  SwiftLintRuleStudio
//
//  View for auditing all rules against the workspace
//

import SwiftUI
import SwiftLintRuleStudioCore

struct RuleAuditView: View {
    @Environment(\.dependencies) var dependencies: DependencyContainer

    @State var isAuditing = false
    @State var auditProgress: AuditProgress?
    @State var auditEntries: [RuleAuditEntry] = []
    @State var selectedRules: Set<String> = []
    @State var expandedRuleId: String?
    @State var totalSwiftFiles: Int = 0
    @State var auditDuration: TimeInterval = 0
    @State var isEnabling = false
    @State var showError = false
    @State var errorMessage: String?

    init() {}

    init(
        auditEntries: [RuleAuditEntry],
        selectedRules: Set<String> = [],
        totalSwiftFiles: Int = 0,
        auditDuration: TimeInterval = 0
    ) {
        _auditEntries = State(initialValue: auditEntries)
        _selectedRules = State(initialValue: selectedRules)
        _totalSwiftFiles = State(initialValue: totalSwiftFiles)
        _auditDuration = State(initialValue: auditDuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            auditToolbar
            Divider()
            mainContent
            if !auditEntries.isEmpty {
                Divider()
                statusBar
            }
        }
        .navigationTitle("Disabled Rule Audit")
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
        if isAuditing {
            auditingProgressView
        } else if auditEntries.isEmpty {
            emptyStateView
        } else {
            auditResultsView
        }
    }

    private var auditToolbar: some View {
        HStack(spacing: 12) {
            Button {
                runAudit()
            } label: {
                Label("Run Audit", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuditing || dependencies.workspaceManager.currentWorkspace == nil)
            .accessibilityIdentifier("RunAuditButton")

            if isAuditing, let progress = auditProgress {
                ProgressView(
                    value: Double(progress.current),
                    total: Double(progress.total)
                )
                .frame(width: 200)

                Text("\(progress.current) / \(progress.total) rules tested")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !auditEntries.isEmpty {
                sortMenu
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var sortMenu: some View {
        Menu {
            Button("Violations (low first)") { sortEntries(by: .violationsAscending) }
            Button("Violations (high first)") { sortEntries(by: .violationsDescending) }
            Button("Name") { sortEntries(by: .name) }
            Button("Category") { sortEntries(by: .category) }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private var auditingProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            if let progress = auditProgress {
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

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Audit Results")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Click 'Run Audit' to test disabled rules against your workspace")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var auditResultsView: some View {
        VStack(spacing: 0) {
            summaryCardsView
            Divider()
            ruleListView
        }
    }

    // MARK: - Sorting

    enum SortOrder {
        case violationsAscending
        case violationsDescending
        case name
        case category
    }

    func sortEntries(by order: SortOrder) {
        switch order {
        case .violationsAscending:
            auditEntries.sort { $0.violationCount < $1.violationCount }
        case .violationsDescending:
            auditEntries.sort { $0.violationCount > $1.violationCount }
        case .name:
            auditEntries.sort { $0.rule.id < $1.rule.id }
        case .category:
            auditEntries.sort { $0.rule.category.rawValue < $1.rule.category.rawValue }
        }
    }
}

#Preview {
    RuleAuditView()
        .environment(\.dependencies, DependencyContainer())
}
