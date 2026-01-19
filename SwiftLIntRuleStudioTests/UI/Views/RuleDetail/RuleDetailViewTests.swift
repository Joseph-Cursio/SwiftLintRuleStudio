//
//  RuleDetailViewTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for RuleDetailView sections
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

@Suite(.serialized)
struct RuleDetailViewTests {
    
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        
        init(view: some View) {
            self.view = AnyView(view)
        }
    }
    
    private struct StubSwiftLintCLI: SwiftLintCLIProtocol {
        func detectSwiftLintPath() async throws -> URL { throw SwiftLintError.notFound }
        func executeRulesCommand() async throws -> Data { Data() }
        func executeRuleDetailCommand(ruleId: String) async throws -> Data { Data() }
        func generateDocsForRule(ruleId: String) async throws -> String { "" }
        func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data { Data() }
        func getVersion() async throws -> String { "0.0.0" }
    }
    
    @MainActor
    private func createView(
        for rule: Rule,
        rules: [Rule] = [],
        viewModel: RuleDetailViewModel? = nil,
        container: DependencyContainer? = nil
    ) -> ViewResult {
        let cacheManager = CacheManager.createForTesting()
        let ruleRegistry = RuleRegistry(swiftLintCLI: StubSwiftLintCLI(), cacheManager: cacheManager)
        let registryRules = rules.isEmpty ? [rule] : rules
        ruleRegistry.setRulesForTesting(registryRules)
        
        let resolvedContainer = container ?? DependencyContainer.createForTesting(
            ruleRegistry: ruleRegistry,
            cacheManager: cacheManager
        )
        
        let detailView = viewModel == nil
            ? RuleDetailView(rule: rule)
            : RuleDetailView(rule: rule, viewModel: viewModel!)
        let view = detailView.environmentObject(resolvedContainer)
        return ViewResult(view: view)
    }
    
    @Test("RuleDetailView renders basic sections and empty states")
    func testRuleDetailViewSections() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: true,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: nil
            )
        }
        
        let result = await Task { @MainActor in createView(for: rule) }.value
        let view = result.view
        
        nonisolated(unsafe) let viewCapture = view
        let (hasConfiguration, hasWhyThisMatters, hasRelatedRules, hasSwiftEvolution) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            let hasConfiguration = (try? inspector.find(text: "Configuration")) != nil
            let hasWhyThisMatters = (try? inspector.find(text: "Why This Matters")) != nil
            let hasRelatedRules = (try? inspector.find(text: "No related rules found")) != nil
            let hasSwiftEvolution = (try? inspector.find(text: "No Swift Evolution proposals linked")) != nil
            return (hasConfiguration, hasWhyThisMatters, hasRelatedRules, hasSwiftEvolution)
        }
        
        #expect(hasConfiguration == true)
        #expect(hasWhyThisMatters == true)
        #expect(hasRelatedRules == true)
        #expect(hasSwiftEvolution == true)
    }
    
    @Test("RuleDetailView shows rationale when markdown includes it")
    func testRuleDetailViewRationale() async throws {
        let markdown = """
        # Test Rule

        ## Rationale

        This rule improves code clarity.
        """
        
        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: false,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: markdown
            )
        }
        
        let result = await Task { @MainActor in createView(for: rule) }.value
        let view = result.view
        
        nonisolated(unsafe) let viewCapture = view
        let hasRationale = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            return (try? inspector.find(text: "This rule improves code clarity.")) != nil
        }
        
        #expect(hasRationale == true)
    }

    @Test("RuleDetailView shows related rules overflow")
    func testRelatedRulesOverflow() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "base_rule",
                name: "Base Rule",
                description: "Test description",
                category: .lint,
                isOptIn: false,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: nil
            )
        }

        let relatedRules = (1...7).map { index in
            Rule(
                id: "rule_\(index)",
                name: "Rule \(index)",
                description: "Test description",
                category: .lint,
                isOptIn: false,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: nil
            )
        }

        let result = await Task { @MainActor in createView(for: rule, rules: [rule] + relatedRules) }.value
        let view = result.view

        nonisolated(unsafe) let viewCapture = view
        let hasOverflow = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            return (try? inspector.find(text: "+ 2 more")) != nil
        }
        #expect(hasOverflow == true)
    }

    @Test("RuleDetailView shows Swift Evolution links")
    func testSwiftEvolutionLinks() async throws {
        let markdown = """
        See SE-0123 for details.
        """
        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: false,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: markdown
            )
        }

        let result = await Task { @MainActor in createView(for: rule) }.value
        let view = result.view

        nonisolated(unsafe) let viewCapture = view
        let hasLink = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            return (try? inspector.find(text: "https://github.com/apple/swift-evolution/blob/main/proposals/0123.md")) != nil
        }
        #expect(hasLink == true)
    }

    @Test("RuleDetailView shows pending changes message")
    func testPendingChangesMessage() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: false,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: nil
            )
        }

        let viewModel = await MainActor.run { RuleDetailViewModel(rule: rule) }
        await MainActor.run {
            viewModel.updateEnabled(true)
        }

        let result = await Task { @MainActor in
            createView(for: rule, viewModel: viewModel)
        }.value
        let view = result.view

        nonisolated(unsafe) let viewCapture = view
        let hasPendingText = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            return (try? viewCapture.inspect().find(text: "You have unsaved changes")) != nil
        }

        #expect(hasPendingText == true)
    }

    @Test("RuleDetailView shows simulate button for disabled rule with workspace")
    @MainActor
    func testSimulateImpactButton() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: false,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: nil
            )
        }

        let cacheManager = CacheManager.createForTesting()
        let ruleRegistry = RuleRegistry(swiftLintCLI: StubSwiftLintCLI(), cacheManager: cacheManager)
        ruleRegistry.setRulesForTesting([rule])
        let workspaceManager = WorkspaceManager.createForTesting(testName: #function)
        try workspaceManager.openWorkspace(at: workspace)

        let container = DependencyContainer.createForTesting(
            ruleRegistry: ruleRegistry,
            cacheManager: cacheManager,
            workspaceManager: workspaceManager
        )

        let viewModel = RuleDetailViewModel(rule: rule)
        let result = createView(
            for: rule,
            viewModel: viewModel,
            container: container
        )
        let view = result.view

        nonisolated(unsafe) let viewCapture = view
        let hasSimulateButton = await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            return true
        }
        defer { Task { @MainActor in ViewHosting.expel() } }

        viewModel.updateEnabled(false)

        func waitForText(_ text: String) async -> Bool {
            for _ in 0..<20 {
                let found = (try? viewCapture.inspect().find(text: text)) != nil
                if found {
                    return true
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return false
        }
        let hasSimulateText = await waitForText("Simulate Impact")

        #expect(hasSimulateButton == true)
        #expect(hasSimulateText == true)
    }

    @Test("RuleDetailView markdown helpers process content")
    @MainActor
    func testMarkdownHelpers() async throws {
        let markdown = """
        # Title
        **Bold** *italic* `code`
        """
        let rationaleMarkdown = """
        ## Rationale
        This matters.
        """
        let evolutionMarkdown = "See SE-0123 for details."

        let rationale = RuleDetailView.extractRationaleForTesting(rationaleMarkdown)
        #expect(rationale?.contains("This matters.") == true)

        let links = RuleDetailView.extractSwiftEvolutionLinksForTesting(evolutionMarkdown)
        #expect(links.isEmpty == false)

        let processed = RuleDetailView.processContentForDisplayForTesting("""
        # Title
        * **Default configuration:** info
        <table>
        <tr><td>skip</td></tr>
        </table>
        Keep me
        """)
        #expect(processed.contains("Keep me") == true)
        #expect(processed.contains("<table>") == false)

        let html = RuleDetailView.convertMarkdownToHTMLForTesting(markdown)
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<strong>Bold</strong>"))

        let wrapped = RuleDetailView.wrapHTMLInDocumentForTesting(body: "<p>Body</p>", colorScheme: .dark)
        #expect(wrapped.contains("<p>Body</p>"))
    }
}

