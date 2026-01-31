//
//  WorkspaceSelectionView.swift
//  SwiftLintRuleStudio
//
//  View for selecting and opening workspaces
//

import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSelectionView: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    @State private var isShowingFilePicker = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
                
                Text("Select a Workspace")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Choose a directory containing your Swift project")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            
            // Current Workspace (if any)
            if let current = workspaceManager.currentWorkspace {
                currentWorkspaceView(current)
            }
            
            // Recent Workspaces
            if !workspaceManager.recentWorkspaces.isEmpty {
                recentWorkspacesView
            }
            
            // Actions
            VStack(spacing: 12) {
                Button {
                    isShowingFilePicker = true
                } label: {
                    Label("Open Workspace...", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                if workspaceManager.currentWorkspace != nil {
                    Button {
                        workspaceManager.closeWorkspace()
                    } label: {
                        Label("Close Workspace", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result)
        }
        .alert("Workspace Selection Error", isPresented: TestGuard.alertBinding($showError)) {
            Button("OK") {
                errorMessage = nil
                showError = false
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private func currentWorkspaceView(_ workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Workspace")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.name)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(workspace.path.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding(.horizontal, 40)
    }
    
    private var recentWorkspacesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Workspaces")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    workspaceManager.clearRecentWorkspaces()
                } label: {
                    Text("Clear")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(workspaceManager.recentWorkspaces) { workspace in
                        recentWorkspaceRow(workspace)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(.horizontal, 40)
    }
    
    private func recentWorkspaceRow(_ workspace: Workspace) -> some View {
        HStack {
            Image(systemName: "folder")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(workspace.name)
                    .font(.body)
                
                Text(workspace.path.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if workspace.path == workspaceManager.currentWorkspace?.path {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .accessibilityHidden(true)
            }
            
            Button {
                workspaceManager.removeFromRecentWorkspaces(workspace)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Remove from recent workspaces")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            do {
                try workspaceManager.openWorkspace(at: workspace.path)
            } catch let error as WorkspaceError {
                // Use the full error description with recovery suggestion
                var message = error.localizedDescription
                if let suggestion = error.recoverySuggestion {
                    message += "\n\n\(suggestion)"
                }
                errorMessage = message
                showError = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try workspaceManager.openWorkspace(at: url)
            } catch let error as WorkspaceError {
                // Use the full error description with recovery suggestion
                var message = error.localizedDescription
                if let suggestion = error.recoverySuggestion {
                    message += "\n\n\(suggestion)"
                }
                errorMessage = message
                showError = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    WorkspaceSelectionView(workspaceManager: WorkspaceManager())
        .frame(width: 600, height: 500)
}
