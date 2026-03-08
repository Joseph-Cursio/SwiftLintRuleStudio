//
//  ViolationDetailView.swift
//  SwiftLintRuleStudio
//
//  Detailed view of a single violation
//

import SwiftUI

struct ViolationDetailView: View {
    let violation: Violation
    let onSuppress: (String) -> Void
    let onResolve: () -> Void

    @State private var showSuppressDialog = false
    @State private var suppressReason = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isOpeningInXcode = false
    @Environment(\.dependencies) var dependencies: DependencyContainer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ViolationDetailHeaderView(violation: violation)

                Divider()

                ViolationDetailLocationView(
                    violation: violation,
                    isOpeningInXcode: $isOpeningInXcode,
                    openInXcode: openInXcode
                )

                Divider()

                ViolationDetailMessageView(violation: violation)

                Divider()

                ViolationDetailCodeSnippetView()

                Divider()

                ViolationDetailActionsView(
                    violation: violation,
                    showSuppressDialog: $showSuppressDialog,
                    onResolve: onResolve
                )
            }
            .padding()
        }
        .navigationTitle(violation.ruleID)
        .sheet(isPresented: $showSuppressDialog) {
            SuppressViolationDialog(
                reason: $suppressReason,
                onSuppress: { reason in
                    onSuppress(reason)
                    showSuppressDialog = false
                    suppressReason = ""
                },
                onCancel: {
                    showSuppressDialog = false
                    suppressReason = ""
                }
            )
        }
        .alert("Error Opening File", isPresented: TestGuard.alertBinding($showErrorAlert)) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

#if DEBUG
    // Test-only: expose suppress dialog content for ViewInspector without presenting a sheet.
    var suppressDialogForTesting: some View {
        SuppressViolationDialog(reason: $suppressReason, onSuppress: { _ in }, onCancel: {})
    }

    /// Test-only builder that allows custom state binding.
    static func suppressDialogForTesting(
        reason: Binding<String>,
        onSuppress: @escaping (String) -> Void
    ) -> some View {
        SuppressViolationDialog(reason: reason, onSuppress: onSuppress, onCancel: {})
    }

    /// Test-only alias kept for existing interaction tests.
    static func makeSuppressDialogForTesting(
        reason: Binding<String>,
        onSuppress: @escaping (String) -> Void
    ) -> some View {
        suppressDialogForTesting(reason: reason, onSuppress: onSuppress)
    }
#endif

    private func openInXcode() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            errorMessage = "No workspace is currently open. Please select a workspace first."
            showErrorAlert = true
            return
        }

        isOpeningInXcode = true
        defer { isOpeningInXcode = false }

        do {
            let success = try dependencies.xcodeIntegrationService.openFile(
                at: violation.filePath,
                line: violation.line,
                column: violation.column,
                in: workspace
            )

            if !success {
                errorMessage = "Failed to open file in Xcode. Please ensure Xcode is installed and try again."
                showErrorAlert = true
            }
        } catch let error as XcodeIntegrationError {
            switch error {
            case .fileNotFound(let path):
                errorMessage = "File not found: \(path)\n\nThe file may have been moved or deleted."
            case .invalidPath(let path):
                errorMessage = "Invalid file path: \(path)\n\nPlease verify the violation file path."
            case .xcodeNotInstalled:
                errorMessage = "Xcode is not installed.\n\nPlease install Xcode from the App Store to use this feature."
            case .failedToOpen:
                errorMessage = "Failed to open file in Xcode.\n\nPlease ensure Xcode is installed and try again."
            }
            showErrorAlert = true
        } catch {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}
