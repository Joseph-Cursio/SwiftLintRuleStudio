//
//  ViolationInspectorView.swift
//  SwiftLintRuleStudio
//
//  Main view for inspecting violations
//

import SwiftUI
import UniformTypeIdentifiers

struct ViolationInspectorView: View {
    @EnvironmentObject var dependencies: DependencyContainer
    @StateObject var viewModel: ViolationInspectorViewModel
    
    init() {
        // Create temporary storage for initialization
        // Will be updated in onAppear with actual storage from dependencies
        // Use do-catch to handle initialization errors gracefully
        let tempStorage: ViolationStorage
        do {
            tempStorage = try ViolationStorage(useInMemory: true)
        } catch {
            // If initialization fails, log the error and create a fallback
            // This prevents crashes and allows the view to still render
            print("⚠️ Failed to initialize ViolationStorage: \(error)")
            // Try to create a file-based storage as fallback
            if let fallbackStorage = try? ViolationStorage(useInMemory: false) {
                tempStorage = fallbackStorage
            } else {
                // Last resort: create in-memory storage again (should work after fix)
                // This will crash if there's a fundamental issue, but that's better than silent failure
                fatalError(
                    "Failed to initialize ViolationStorage: \(error). " +
                        "This indicates a critical database configuration issue."
                )
            }
        }
        _viewModel = StateObject(wrappedValue: ViolationInspectorViewModel(violationStorage: tempStorage))
    }

#if DEBUG
    init(viewModel: ViolationInspectorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
#endif
    
    var body: some View {
        HStack(spacing: 0) {
            // Left panel: Violation List
            violationListView
                .frame(width: 300)
            
            Divider()
            
            // Right panel: Violation Detail or Empty State
            Group {
                if let selectedViolationId = viewModel.selectedViolationId,
                   let violation = viewModel.filteredViolations.first(where: { $0.id == selectedViolationId }) {
                    ViolationDetailView(
                        violation: violation,
                        onSuppress: { reason in
                            Task {
                                try? await viewModel.suppressSelectedViolations(reason: reason)
                            }
                        },
                        onResolve: {
                            Task {
                                try? await viewModel.resolveSelectedViolations()
                            }
                        }
                    )
                } else {
                    emptyDetailView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Violations")
        .onAppear {
            // Update viewModel with actual storage and analyzer from dependencies
            viewModel.violationStorage = dependencies.violationStorage
            viewModel.workspaceAnalyzer = dependencies.workspaceAnalyzer
            
            // Load violations for current workspace if available
            if let workspace = dependencies.workspaceManager.currentWorkspace {
                Task {
                    do {
                        try await viewModel.loadViolations(for: workspace.id, workspace: workspace)
                    } catch {
                        print("Error loading violations: \(error)")
                    }
                }
            }
        }
        .onChange(of: dependencies.workspaceManager.currentWorkspace) { _, newWorkspace in
            // Reload violations when workspace changes
            if let workspace = newWorkspace {
                Task {
                    do {
                        try await viewModel.loadViolations(for: workspace.id, workspace: workspace)
                    } catch {
                        print("Error loading violations: \(error)")
                    }
                }
            } else {
                // Clear violations when workspace is closed
                Task {
                    viewModel.clearViolations()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        try? await viewModel.refreshViolations()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                Menu {
                    Section("Filtered") {
                        Button("Export Filtered as JSON") {
                            exportViolations(scope: .filtered, format: .json)
                        }
                        Button("Export Filtered as CSV") {
                            exportViolations(scope: .filtered, format: .csv)
                        }
                    }

                    Section("Selected") {
                        Button("Export Selected as JSON") {
                            exportViolations(scope: .selected, format: .json)
                        }
                        .disabled(viewModel.selectedViolationIds.isEmpty)
                        Button("Export Selected as CSV") {
                            exportViolations(scope: .selected, format: .csv)
                        }
                        .disabled(viewModel.selectedViolationIds.isEmpty)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                
                Button {
                    viewModel.selectNextViolation()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                
                Button {
                    viewModel.selectPreviousViolation()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Menu {
                    Button("Select All") {
                        viewModel.selectAll()
                    }
                    .keyboardShortcut("a", modifiers: .command)
                    Button("Clear Selection") {
                        viewModel.deselectAll()
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                } label: {
                    Label("Selection", systemImage: "checkmark.circle")
                }
                .disabled(viewModel.filteredViolations.isEmpty)
                
                if !viewModel.selectedViolationIds.isEmpty {
                    Menu {
                        Button {
                            let suppressReason = "Suppressed via Violation Inspector"
                            Task {
                                try? await viewModel.suppressSelectedViolations(reason: suppressReason)
                            }
                        } label: {
                            Label("Suppress Selected", systemImage: "eye.slash")
                        }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        
                        Button {
                            Task {
                                try? await viewModel.resolveSelectedViolations()
                            }
                        } label: {
                            Label("Mark as Resolved", systemImage: "checkmark.circle")
                        }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
}

enum ViolationExportScope: String {
    case filtered = "Filtered"
    case selected = "Selected"
}

enum ViolationExportFormat {
    case json
    case csv
}

// MARK: - Supporting Views

struct StatisticBadge: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
