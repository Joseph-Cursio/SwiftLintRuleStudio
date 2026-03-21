//
//  WorkspaceSelectionView.swift
//  SwiftLintRuleStudio
//
//  View for selecting and opening workspaces
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct WorkspaceSelectionView: View {
    var workspaceManager: WorkspaceManager
    @State private var isShowingFilePicker = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 24) {
            headerSection

            if let current = workspaceManager.currentWorkspace {
                currentWorkspaceView(current)
            }

            if !workspaceManager.recentWorkspaces.isEmpty {
                recentWorkspacesView
            }

            actionButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .openWorkspaceRequested)) { _ in
            isShowingFilePicker = true
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop)
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

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text("Select a Workspace")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Choose a directory containing your Swift project")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var actionButtons: some View {
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let nsURL = item as? NSURL {
                url = nsURL as URL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let dropURL = url else { return }
            Task { @MainActor in
                try? workspaceManager.openWorkspace(at: dropURL)
            }
        }
        return true
    }

    private func currentWorkspaceView(_ workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Workspace")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.name)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(workspace.path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
        }
        .padding(.horizontal, 40)
    }

    private var recentWorkspacesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Workspaces")
                    .font(.headline)
                    .foregroundStyle(.secondary)

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
        Button {
            do {
                try workspaceManager.openWorkspace(at: workspace.path)
            } catch let error as WorkspaceError {
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
        } label: {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(workspace.name)
                    .font(.body)

                Text(workspace.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if workspace.path == workspaceManager.currentWorkspace?.path {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }

            Button {
                workspaceManager.removeFromRecentWorkspaces(workspace)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove from recent workspaces")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
