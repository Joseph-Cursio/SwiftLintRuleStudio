//
//  RuleDetailView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftLintRuleStudioCore
import SwiftUI

private struct RuleDetailEventHandlers: ViewModifier {
    let ruleId: String
    @Bindable var viewModel: RuleDetailViewModel
    @Binding var currentRule: Rule
    let colorScheme: ColorScheme
    let rules: [Rule]
    let saveAction: () -> Void
    let rebuildString: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .ruleConfigurationDidChange)) { notification in
                if let changedId = notification.userInfo?["ruleId"] as? String,
                   changedId == ruleId {
                    try? viewModel.loadConfiguration()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveConfigurationRequested)) { _ in
                guard viewModel.pendingChanges != nil else { return }
                saveAction()
            }
            .onChange(of: rules) { _, newRules in
                adoptRule(from: newRules)
            }
            .onChange(of: colorScheme) { rebuildString() }
    }

    /// Refresh the displayed rule from a new registry snapshot, keeping the current one when the
    /// snapshot does not mention it.
    ///
    /// The `rebuildString()` is unconditional and that is the point: the documentation string is
    /// rebuilt whether or not the rule changed, because a registry refresh can alter what the
    /// string renders from even when the rule's own fields are unchanged. Inside the closure that
    /// read as an oversight — the assignment is guarded and the call is not.
    private func adoptRule(from newRules: [Rule]) {
        if let updatedRule = newRules.first(where: { $0.id == ruleId }) {
            currentRule = updatedRule
        }
        rebuildString()
    }
}

private struct RuleDetailSheetsAndAlerts: ViewModifier {
    @Bindable var viewModel: RuleDetailViewModel
    @Binding var showSaveConfirmation: Bool
    @Binding var showError: Bool
    @Binding var impactResult: RuleImpactResult?
    let rule: Rule

    func body(content: Content) -> some View {
        content
            .alert("Configuration Saved", isPresented: $showSaveConfirmation) {
                Button("OK") { }
            } message: {
                Text("Rule configuration has been saved to your workspace's .swiftlint.yml file.")
            }
            .alert("Error", isPresented: TestGuard.alertBinding($showError)) {
                Button("OK") { viewModel.saveError = nil }
            } message: {
                Text(viewModel.saveError?.localizedDescription
                     ?? "An error occurred while saving the configuration.")
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
}

struct RuleDetailView: View {
    @State private var viewModel: RuleDetailViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Environment(\.appCapabilities) var capabilities: Set<AppCapability>
    @State private var showSaveConfirmation = false
    @State private var showError = false
    @State private var impactResult: RuleImpactResult?
    // The sections in RuleDetailView+Header and +Sections are handed these values; they don't
    // read the state themselves.
    @State private var isSimulating = false
    @State private var violationCount = RuleViolationCount()
    /// Analyses finished while the view is shown. Part of the violation count's task key, so a
    /// finished analysis reloads the count.
    @State private var analysesFinished = 0
    @State private var cachedDocSegments: [RuleDocSegment.Rendered]?
    @State private var currentRule: Rule

    private let ruleId: String

    /// What the violation count is loaded for: a change to any of these reloads it.
    private struct ViolationCountKey: Equatable {
        let ruleID: String
        let workspaceID: UUID?
        let analysesFinished: Int
    }

    private var violationCountKey: ViolationCountKey {
        ViolationCountKey(
            ruleID: rule.id,
            workspaceID: dependencies.workspaceManager.currentWorkspace?.id,
            analysesFinished: analysesFinished
        )
    }

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

    /// Takes the models from the caller, so a test can watch what the view loads into them.
    init(
        rule: Rule,
        viewModel: RuleDetailViewModel,
        violationCount: RuleViolationCount = RuleViolationCount()
    ) {
        self.ruleId = rule.id
        _currentRule = State(initialValue: rule)
        _viewModel = State(initialValue: viewModel)
        _violationCount = State(initialValue: violationCount)
    }

    var body: some View {
        scrollContent
            .navigationTitle(rule.name)
            .onAppear { loadWorkspaceConfiguration() }
            .task { await fetchRuleDetailsAndBuildString() }
            .task(id: violationCountKey) { await loadViolationCount() }
            .onReceive(dependencies.workspaceAnalyzer.analysisFinishedPublisher) { analysesFinished += 1 }
            .id(rule.id)
            .modifier(ruleDetailEventHandlers)
            .modifier(RuleDetailSheetsAndAlerts(
                viewModel: viewModel,
                showSaveConfirmation: $showSaveConfirmation,
                showError: $showError,
                impactResult: $impactResult,
                rule: rule
            ))
    }

    private var ruleDetailEventHandlers: some ViewModifier {
        RuleDetailEventHandlers(
            ruleId: ruleId,
            viewModel: viewModel,
            currentRule: $currentRule,
            colorScheme: colorScheme,
            rules: dependencies.ruleRegistry.rules,
            saveAction: saveConfigurationAction,
            rebuildString: rebuildAttributedString
        )
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerView(isEnabled: viewModel.isEnabled)
                Divider()
                configurationView(model: viewModel, isSimulating: isSimulating)
                Divider()
                descriptionView(segments: cachedDocSegments)
                Divider()
                whyThisMattersView
                Divider()
                violationsCountView(state: violationCount.state)
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

    private func loadWorkspaceConfiguration() {
        if let workspace = dependencies.workspaceManager.currentWorkspace,
           let configPath = workspace.configPath {
            // The seam exists and is in use: `RuleDetailViewModel.yamlEngine` is typed
            // `(any YAMLConfigurationEngineProtocol)?` and its tests set a stub. This is the
            // view choosing the production implementation for the model it owns — the one
            // place that has to name a concrete type for the injection everywhere else to work.
            // swiftprojectlint:disable:next direct-instantiation
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            viewModel.yamlEngine = yamlEngine
            try? viewModel.loadConfiguration()
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

    /// Builds the documentation segments for the description section on the main thread.
    /// Prose goes through HTML: NSAttributedString(data:options:) with .html document type
    /// MUST be called on the main thread only. Calling it inside a SwiftUI body can hit
    /// non-main threads during layout passes and causes
    /// "SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION". Code blocks skip HTML and are
    /// highlighted directly, so each can be drawn as its own block.
    @MainActor
    private func rebuildAttributedString() {
        guard let markdownDoc = rule.markdownDocumentation, !markdownDoc.isEmpty else {
            cachedDocSegments = nil
            return
        }
        let processedContent = processContentForDisplay(content: markdownDoc)
        cachedDocSegments = RuleDocSegment.split(processedContent).enumerated().map { index, segment in
            switch segment {
            case .prose(let markdown):
                // If HTML parsing fails, show this piece as plain text rather than dropping it.
                let text = renderProse(markdown) ?? AttributedString(markdown)
                return RuleDocSegment.Rendered(id: index, isCode: false, text: text)

            case .code(let code):
                return RuleDocSegment.Rendered(id: index, isCode: true, text: SwiftCodeHighlighter.highlight(code))
            }
        }
    }

    @MainActor
    private func renderProse(_ markdown: String) -> AttributedString? {
        let htmlContent = convertMarkdownToHTML(content: markdown)
        let fullHTML = wrapHTMLInDocument(body: htmlContent, colorScheme: colorScheme)
        guard let htmlData = fullHTML.data(using: .utf8),
              let nsAttr = try? NSAttributedString(
                  data: htmlData,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                      NSAttributedString.DocumentReadingOptionKey.defaultAttributes: [
                          NSAttributedString.Key.font: NSFont.systemFont(ofSize: 14)
                      ],
                  ],
                  documentAttributes: nil
              ) else {
            return nil
        }
        // Convert to SwiftUI AttributedString so we can use pure Text() rendering
        // instead of NSViewRepresentable, avoiding AppKit layout cycle crashes
        guard var text = try? AttributedString(nsAttr, including: \.appKit) else { return nil }
        // The HTML import ends each piece with newlines; trim them so the gap before the
        // next code block comes from the layout, not from blank lines.
        while let last = text.characters.last, last.isNewline {
            text.removeSubrange(text.characters.index(before: text.endIndex)..<text.endIndex)
        }
        return text
    }

    func simulateRule() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            return
        }

        isSimulating = true

        let simulator = dependencies.impactSimulator
        let simulatedRuleId = rule.id
        let options = Self.simulationOptions(
            for: rule,
            capabilities: capabilities,
            parameterValues: viewModel.parameterValues
        )
        let simulate = {
            try await simulator.simulateRule(
                ruleId: simulatedRuleId,
                workspace: workspace,
                baseConfigPath: workspace.configPath,
                options: options
            )
        }
        Task {
            impactResult = await Self.simulationResult(ruleId: simulatedRuleId, simulate: simulate)
            isSimulating = false
        }
    }

    /// The options for simulating `rule` from the editor. Built from the edition's
    /// capabilities, so a SourceKit rule where SourceKit can't load comes back unmeasurable
    /// rather than as a "safe" 0; and carrying the editor's in-memory parameter values, so the
    /// simulation reflects edits not yet saved rather than the workspace YAML.
    static func simulationOptions(
        for rule: Rule,
        capabilities: Set<AppCapability>,
        parameterValues: [String: AnyCodable]
    ) -> RuleSimulationOptions {
        RuleSimulationOptions(
            rule: rule,
            capabilities: capabilities,
            parameterOverrides: parameterValues.isEmpty ? nil : parameterValues
        )
    }

    /// What the Impact Simulation sheet shows: the simulator's result, or — when it threw — a
    /// failure carrying why, which the sheet shows as "The simulation failed".
    ///
    /// A throw used to raise the save-error alert, which said saving the configuration had
    /// failed and dropped the real error.
    static func simulationResult(
        ruleId: String,
        simulate: () async throws -> RuleImpactResult
    ) async -> RuleImpactResult {
        do {
            return try await simulate()
        } catch {
            return .failed(ruleId: ruleId, reason: error.localizedDescription)
        }
    }

    // Read by RuleDetailView+Sections.swift's inline Save button — internal
    // (default) is the minimum access level that allows a cross-file extension
    // on the same type to call it.
    func saveConfigurationAction() {
        Task {
            do {
                try viewModel.saveConfiguration()
                showSaveConfirmation = true
            } catch {
                showError = true
            }
        }
    }

    private func loadViolationCount() async {
        await violationCount.load(
            ruleID: rule.id,
            workspaceID: dependencies.workspaceManager.currentWorkspace?.id,
            storage: dependencies.violationStorage
        )
    }
}
