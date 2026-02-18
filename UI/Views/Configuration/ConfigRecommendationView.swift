//
//  ConfigRecommendationView.swift
//  SwiftLintRuleStudio
//
//  View component that recommends creating a SwiftLint configuration file
//

import SwiftUI

struct ConfigRecommendationView: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    @State private var isCreatingConfig: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        if workspaceManager.configFileMissing {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)
                        .accessibilityLabel("Information")
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SwiftLint Configuration File Missing")
                            .font(.headline)
                        
                        Text("""
                        Your workspace doesn't have a `.swiftlint.yml` configuration file.
                        Creating one will help you:
                        """)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ConfigBenefitRow(
                        icon: "checkmark.circle.fill",
                        text: "Exclude third-party code from analysis"
                    )
                    ConfigBenefitRow(
                        icon: "checkmark.circle.fill",
                        text: "Customize rule severity and behavior"
                    )
                    ConfigBenefitRow(
                        icon: "checkmark.circle.fill",
                        text: "Follow SwiftLint best practices"
                    )
                }
                .padding(.leading, 32)
                
                HStack {
                    Button(action: createConfigFile) {
                        HStack {
                            if isCreatingConfig {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .accessibilityHidden(true)
                            }
                            Text(isCreatingConfig ? "Creating..." : "Create Default Configuration")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreatingConfig)
                    
                    Button("Learn More") {
                        // Open documentation or help
                        if let url = URL(string: "https://github.com/realm/SwiftLint#configuration") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
            .alert("Error Creating Config File", isPresented: TestGuard.alertBinding($showError)) {
                Button("OK") {
                    errorMessage = nil
                    showError = false
                }
            } message: {
                Text(errorMessage ?? "Unknown error occurred while creating the configuration file.")
            }
        }
    }
    
    private func createConfigFile() {
        isCreatingConfig = true
        
        Task { @MainActor in
            do {
                _ = try workspaceManager.createDefaultConfigFile()
                // Config file created successfully
                // The published property will update automatically
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            
            isCreatingConfig = false
        }
    }
}

struct ConfigBenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.caption)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    struct Preview: View {
        @StateObject private var workspaceManager = WorkspaceManager()
        
        var body: some View {
            ConfigRecommendationView(workspaceManager: workspaceManager)
                .padding()
                .frame(width: 600)
                .task {
                    // Simulate missing config by opening a workspace without a config file
                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent("PreviewTest", isDirectory: true)
                    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    try? workspaceManager.openWorkspace(at: tempDir)
                }
        }
    }
    
    return Preview()
}
