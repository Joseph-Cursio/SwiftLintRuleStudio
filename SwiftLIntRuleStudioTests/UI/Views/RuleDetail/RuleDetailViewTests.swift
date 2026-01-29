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

// swiftlint:disable file_length function_body_length vertical_whitespace

@Suite(.serialized)
// swiftlint:disable:next type_body_length
struct RuleDetailViewTests {
    
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        
        init(view: some View) {
            self.view = AnyView(view)
        }
    }

    
    
    private struct StubSwiftLintCLI: SwiftLintCLIProtocol {
        func detectSwiftLintPath() throws -> URL { throw SwiftLintError.notFound }
        func executeRulesCommand() throws -> Data { Data() }
        func executeRuleDetailCommand(ruleId: String) throws -> Data { Data() }
        func generateDocsForRule(ruleId: String) throws -> String { "" }
        func executeLintCommand(configPath: URL?, workspacePath: URL) throws -> Data { Data() }
        func getVersion() throws -> String { "0.0.0" }
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
        
        let detailView = viewModel.map { RuleDetailView(rule: rule, viewModel: $0) }
            ?? RuleDetailView(rule: rule)
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

    @Test("RuleDetailView processes markdown content for display")
    func testProcessContentForDisplay() async throws {
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

        let content = """
        # Title
        * **Enabled by default:** Yes
        * **Default configuration:** warning
        <table>
        <tr><td>ignore</td></tr>
        </table>
        Body text
        """
        let processed = await MainActor.run {
            RuleDetailView(rule: rule).processContentForDisplay(content: content)
        }

        #expect(processed.contains("Title") == false)
        #expect(processed.contains("Enabled by default") == false)
        #expect(processed.contains("<table>") == false)
        #expect(processed.contains("Body text") == true)
    }

    @Test("RuleDetailView converts markdown to HTML")
    func testConvertMarkdownToHTML() async throws {
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

        let content = """
        # Heading
        ```swift
        let value = 1
        ```
        """
        let html = await MainActor.run {
            RuleDetailView(rule: rule).convertMarkdownToHTML(content: content)
        }

        #expect(html.contains("<h1>Heading</h1>") == true)
        #expect(html.contains("language-swift") == true)
        #expect(html.contains("let value = 1") == true)
    }

    @Test("RuleDetailView wraps HTML with dark mode styles")
    func testWrapHTMLInDocumentDarkMode() async throws {
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

        let html = await MainActor.run {
            RuleDetailView(rule: rule).wrapHTMLInDocument(body: "<p>Body</p>", colorScheme: .dark)
        }

        #expect(html.contains("#FFFFFF") == true)
        #expect(html.contains("<p>Body</p>") == true)
    }

    @Test("RuleDetailView hides short description when markdown contains it")
    func testDescriptionHiddenWhenInMarkdown() async throws {
        let markdown = """
        # Rule

        This is the description.
        """
        let rule = await MainActor.run {
            Rule(
                id: "desc_rule",
                name: "Desc Rule",
                description: "This is the description.",
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
        let hasDescription = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            return (try? viewCapture.inspect().find(text: rule.description)) != nil
        }

        #expect(hasDescription == false)
    }

    @Test("RuleDetailView shows fallback when description missing")
    func testDescriptionFallbackWhenMissing() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "empty_desc",
                name: "Empty Desc",
                description: "No description available",
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

        let result = await Task { @MainActor in createView(for: rule) }.value
        let view = result.view

        nonisolated(unsafe) let viewCapture = view
        let hasFallback = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            return (try? viewCapture.inspect().find(text: "No description available")) != nil
        }

        #expect(hasFallback == true)
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

        let hasSimulateText = await UIAsyncTestHelpers.waitForText(
            in: viewCapture,
            text: "Simulate Impact",
            timeout: 1.0
        )

        #expect(hasSimulateButton == true)
        #expect(hasSimulateText == true)
    }

    @Test("RuleDetailView markdown helpers process content")
    @MainActor
    func testMarkdownHelpers() throws {
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
// swiftlint:enable file_length function_body_length vertical_whitespace