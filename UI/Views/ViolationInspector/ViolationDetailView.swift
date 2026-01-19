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
    @EnvironmentObject var dependencies: DependencyContainer
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerView
                
                Divider()
                
                // Location
                locationView
                
                Divider()
                
                // Message
                messageView
                
                Divider()
                
                // Code snippet (if available)
                codeSnippetView
                
                Divider()
                
                // Actions
                actionsView
            }
            .padding()
        }
        .navigationTitle(violation.ruleID)
        .sheet(isPresented: $showSuppressDialog) {
            suppressDialog
        }
        .alert("Error Opening File", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SeverityBadge(severity: violation.severity)
                
                if violation.suppressed {
                    Label("Suppressed", systemImage: "eye.slash")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if violation.resolvedAt != nil {
                    Label("Resolved", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
            
            Text("Rule: \(violation.ruleID)")
                .font(.title2)
                .fontWeight(.bold)
        }
    }
    
    private var locationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("File")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(violation.filePath)
                        .font(.body)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Line")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(violation.line)")
                        .font(.body)
                }
                
                if let column = violation.column {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Column")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(column)")
                            .font(.body)
                    }
                }
            }
            
            Button {
                Task {
                    await openInXcode()
                }
            } label: {
                if isOpeningInXcode {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Label("Open in Xcode", systemImage: "arrow.right.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isOpeningInXcode)
        }
    }
    
    private var messageView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(.headline)
            
            Text(violation.message)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
    
    private var codeSnippetView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code Context")
                .font(.headline)
            
            // TODO: Load and display code snippet from file
            Text("Code snippet loading not yet implemented")
                .font(.body)
                .foregroundColor(.secondary)
                .italic()
        }
    }
    
    private var actionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)
            
            HStack(spacing: 12) {
                if !violation.suppressed {
                    Button {
                        showSuppressDialog = true
                    } label: {
                        Label("Suppress", systemImage: "eye.slash")
                    }
                    .buttonStyle(.bordered)
                }
                
                if violation.resolvedAt == nil {
                    Button {
                        onResolve()
                    } label: {
                        Label("Mark as Resolved", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private var suppressDialog: some View {
        buildSuppressDialog(
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

#if DEBUG
    // Test-only: expose suppress dialog content for ViewInspector without presenting a sheet.
    var suppressDialogForTesting: some View {
        buildSuppressDialog(reason: $suppressReason, onSuppress: { _ in }, onCancel: {})
    }
    
    /// Test-only builder that allows custom state binding.
    static func suppressDialogForTesting(
        reason: Binding<String>,
        onSuppress: @escaping (String) -> Void
    ) -> some View {
        buildSuppressDialog(reason: reason, onSuppress: onSuppress, onCancel: {})
    }

    /// Test-only alias kept for existing interaction tests.
    static func makeSuppressDialogForTesting(
        reason: Binding<String>,
        onSuppress: @escaping (String) -> Void
    ) -> some View {
        suppressDialogForTesting(reason: reason, onSuppress: onSuppress)
    }
#endif
    
    private func openInXcode() async {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            errorMessage = "No workspace is currently open. Please select a workspace first."
            showErrorAlert = true
            return
        }
        
        isOpeningInXcode = true
        defer { isOpeningInXcode = false }
        
        do {
            let success = try await dependencies.xcodeIntegrationService.openFile(
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

fileprivate func buildSuppressDialog(
    reason: Binding<String>,
    onSuppress: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
) -> some View {
    NavigationView {
        Form {
            Section {
                TextField("Reason (optional)", text: reason, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Suppression Reason")
            } footer: {
                Text("Provide a reason for suppressing this violation. This helps with code review and maintenance.")
            }
        }
        .navigationTitle("Suppress Violation")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Suppress") {
                    onSuppress(reason.wrappedValue.isEmpty ? "Suppressed via Violation Inspector" : reason.wrappedValue)
                }
            }
        }
    }
    .frame(width: 500, height: 300)
}
