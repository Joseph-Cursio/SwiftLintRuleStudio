//
//  RuleAuditContent.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - Audit sections

/// The spinner and the rule counter while an audit runs.
/// 
/// Takes the progress, so the audit results accumulating beneath it do not redraw the
/// spinner.
private struct AuditProgressView: View {
    let progress: AuditProgress?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            if let progress {
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
}

/// The audit screen: toolbar, results and status bar, drawn from and acting on the model
/// `RuleAuditView` owns.
struct RuleAuditContent: View {
    @Environment(\.dependencies) var dependencies: DependencyContainer
    /// Read by +Audit, which tells the simulator which rules this edition can't lint.
    @Environment(\.appCapabilities) var capabilities: Set<AppCapability>
    @Bindable var model: RuleAuditModel

    var body: some View {
        VStack(spacing: 0) {
            auditToolbar
            Divider()
            mainContent
            if !model.auditEntries.isEmpty {
                Divider()
                statusBar
            }
        }
        .navigationTitle("Disabled Rule Audit")
        .onChange(of: dependencies.workspaceManager.currentWorkspace?.id) {
            resetAuditState()
        }
        // Leaving the section discards this view and its state; an audit left running would
        // lint every remaining rule for nobody, beside any audit started on coming back.
        .onDisappear {
            model.auditRunner.cancel()
            model.isAuditing = false
            model.auditProgress = nil
        }
        .alert("Error", isPresented: TestGuard.alertBinding($model.showError)) {
            Button("OK") {
                model.errorMessage = nil
                model.showError = false
            }
        } message: {
            Text(model.errorMessage ?? "An error occurred")
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if model.isAuditing {
            AuditProgressView(progress: model.auditProgress)
        } else if model.auditEntries.isEmpty {
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
            .disabled(model.isAuditing || dependencies.workspaceManager.currentWorkspace == nil)
            .accessibilityIdentifier("RunAuditButton")

            if model.isAuditing, let progress = model.auditProgress {
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

            if !model.auditEntries.isEmpty {
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
            model.auditEntries.sort { RuleAuditEntry.isOrderedByViolations($0, $1, ascending: true) }

        case .violationsDescending:
            model.auditEntries.sort { RuleAuditEntry.isOrderedByViolations($0, $1, ascending: false) }

        case .name:
            model.auditEntries.sort { $0.rule.id < $1.rule.id }

        case .category:
            model.auditEntries.sort { $0.rule.category.rawValue < $1.rule.category.rawValue }
        }
    }
}
