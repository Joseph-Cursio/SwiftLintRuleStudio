//
//  RuleDetailView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

struct RuleDetailView: View {
    @State var viewModel: RuleDetailViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @State private var showSaveConfirmation = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var impactResult: RuleImpactResult?
    // These four properties are read by RuleDetailView+Sections.swift (a separate file),
    // so they cannot be private. internal is the minimum viable access level here.
    @State var isSimulating = false
    @State var violationCount: Int = 0
    @State var isLoadingViolationCount = false
    @State var cachedAttributedString: AttributedString?
    // currentRule is only used within this file — private is correct
    @State private var currentRule: Rule

    let ruleId: String

    // Get the latest rule from registry (may have updated documentation)
    // Made internal for testing
    var rule: Rule {
        dependencies.ruleRegistry.getRule(id: ruleId) ?? currentRule
    }

    init(rule: Rule) {
        self.ruleId = rule.id
        _currentRule = State(initialValue: rule)
        // Create ViewModel - will be updated with workspace config in onAppear
        _viewModel = State(initialValue: RuleDetailViewModel(rule: rule))
    }

    init(rule: Rule, viewModel: RuleDetailViewModel) {
        self.ruleId = rule.id
        _currentRule = State(initialValue: rule)
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        scrollContent
            .navigationTitle(rule.name)
            .toolbar { toolbarContent }
            .onAppear { loadWorkspaceConfiguration() }
            .task { await fetchRuleDetailsAndBuildString() }
            .onReceive(NotificationCenter.default.publisher(for: .ruleConfigurationDidChange)) { notification in
                if let ruleId = notification.userInfo?["ruleId"] as? String,
                   ruleId == rule.id {
                    try? viewModel.loadConfiguration()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveConfigurationRequested)) { _ in
                guard viewModel.pendingChanges != nil else { return }
                saveConfigurationAction()
            }
            .id(rule.id)
            .onChange(of: dependencies.ruleRegistry.rules) { _, newRules in
                if let updatedRule = newRules.first(where: { $0.id == ruleId }) {
                    currentRule = updatedRule
                }
                rebuildAttributedString()
            }
            .onChange(of: colorScheme) { rebuildAttributedString() }
            .sheet(item: Bindable(viewModel).pendingDiff) { diff in
                diffPreviewSheet(diff: diff)
            }
            .alert("Configuration Saved", isPresented: $showSaveConfirmation) {
                Button("OK") { }
            } message: {
                Text("Rule configuration has been saved to your workspace's .swiftlint.yml file.")
            }
            .alert("Error", isPresented: TestGuard.alertBinding($showError)) {
                Button("OK") { viewModel.saveError = nil }
            } message: {
                Text(viewModel.saveError?.localizedDescription ?? "An error occurred while saving the configuration.")
            }
            .sheet(item: $impactResult) { result in
                ImpactSimulationView(
                    ruleId: rule.id,
                    ruleName: rule.name,
                    result: result,
                    onEnable: viewModel.isEnabled ? nil : { viewModel.updateEnabled(true) }
                )
            }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerView
                Divider()
                configurationView
                Divider()
                descriptionView
                Divider()
                whyThisMattersView
                Divider()
                violationsCountView
                Divider()
                relatedRulesView
                Divider()
                swiftEvolutionView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .padding(.horizontal, 20)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if viewModel.pendingChanges != nil {
                Button {
                    viewModel.showPreview()
                } label: {
                    Label("Preview Changes", systemImage: "eye")
                }
                .accessibilityIdentifier("RuleDetailPreviewChangesButton")

                Button(action: saveConfigurationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Save", systemImage: "checkmark")
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
    }

    private func loadWorkspaceConfiguration() {
        if let workspace = dependencies.workspaceManager.currentWorkspace,
           let configPath = workspace.configPath {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            viewModel.yamlEngine = yamlEngine
            do {
                try viewModel.loadConfiguration()
            } catch {
            }
        }
    }

    private func fetchRuleDetailsAndBuildString() async {
        if rule.markdownDocumentation == nil || rule.markdownDocumentation?.isEmpty == true {
            await dependencies.ruleRegistry.fetchRuleDetailsIfNeeded(id: ruleId)
            if let updatedRule = dependencies.ruleRegistry.getRule(id: ruleId) {
                currentRule = updatedRule
            }
        }
        rebuildAttributedString()
    }

    private func diffPreviewSheet(diff: YAMLConfigurationEngine.ConfigDiff) -> some View {
        ConfigDiffPreviewView(diff: diff, ruleName: rule.name) {
            Task {
                do {
                    try viewModel.saveConfiguration()
                    viewModel.pendingDiff = nil
                    viewModel.showDiffPreview = false
                    showSaveConfirmation = true
                } catch {
                    showError = true
                }
            }
        } onCancel: {
            viewModel.pendingDiff = nil
            viewModel.showDiffPreview = false
        }
    }

    /// Builds the HTML attributed string for the description section on the main thread.
    /// NSAttributedString(data:options:) with .html document type MUST be called on the
    /// main thread only. Calling it inside a SwiftUI body can hit non-main threads during
    /// layout passes and causes "SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION".
    @MainActor
    func rebuildAttributedString() {
        guard let markdownDoc = rule.markdownDocumentation, !markdownDoc.isEmpty else {
            cachedAttributedString = nil
            return
        }
        let processedContent = processContentForDisplay(content: markdownDoc)
        let htmlContent = convertMarkdownToHTML(content: processedContent)
        let fullHTML = wrapHTMLInDocument(body: htmlContent, colorScheme: colorScheme)
        guard let htmlData = fullHTML.data(using: .utf8),
              let nsAttr = try? NSAttributedString(
                  data: htmlData,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                      NSAttributedString.DocumentReadingOptionKey.defaultAttributes: [
                          NSAttributedString.Key.font: NSFont.systemFont(ofSize: 14)
                      ]
                  ],
                  documentAttributes: nil
              ) else {
            cachedAttributedString = nil
            return
        }
        // Convert to SwiftUI AttributedString so we can use pure Text() rendering
        // instead of NSViewRepresentable, avoiding AppKit layout cycle crashes
        cachedAttributedString = try? AttributedString(nsAttr, including: \.appKit)
    }

    func simulateRule() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            return
        }

        isSimulating = true

        Task {
            do {
                let result = try await dependencies.impactSimulator.simulateRule(
                    ruleId: rule.id,
                    workspace: workspace,
                    baseConfigPath: workspace.configPath,
                    isOptIn: rule.isOptIn
                )

                impactResult = result
                isSimulating = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isSimulating = false
            }
        }
    }

    private func saveConfigurationAction() {
        Task {
            do {
                try viewModel.saveConfiguration()
                showSaveConfirmation = true
            } catch {
                showError = true
            }
        }
    }

    private func loadViolationCount() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            violationCount = 0
            return
        }

        isLoadingViolationCount = true

        Task {
            do {
                let filter = ViolationFilter(ruleIDs: [rule.id], suppressedOnly: false)
                let count = try await dependencies.violationStorage.getViolationCount(
                    filter: filter,
                    workspaceId: workspace.id
                )

                violationCount = count
                isLoadingViolationCount = false
            } catch {
                violationCount = 0
                isLoadingViolationCount = false
            }
        }
    }
}
