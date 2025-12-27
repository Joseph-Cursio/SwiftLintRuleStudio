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
                openInXcode()
            } label: {
                Label("Open in Xcode", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
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
        NavigationView {
            Form {
                Section {
                    TextField("Reason (optional)", text: $suppressReason, axis: .vertical)
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
                    Button("Cancel") {
                        showSuppressDialog = false
                        suppressReason = ""
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Suppress") {
                        onSuppress(suppressReason.isEmpty ? "Suppressed via Violation Inspector" : suppressReason)
                        showSuppressDialog = false
                        suppressReason = ""
                    }
                }
            }
        }
        .frame(width: 500, height: 300)
    }
    
    private func openInXcode() {
        // Generate xcode:// URL to open file at specific line
        // Format: xcode://file/path/to/file.swift:line:column
        let fileURL = URL(fileURLWithPath: violation.filePath)
        var urlString = "xcode://file\(fileURL.path):\(violation.line)"
        if let column = violation.column {
            urlString += ":\(column)"
        }
        
        if let xcodeURL = URL(string: urlString) {
            NSWorkspace.shared.open(xcodeURL)
        } else {
            // Fallback: try to open the file in default editor
            NSWorkspace.shared.open(fileURL)
        }
    }
}

