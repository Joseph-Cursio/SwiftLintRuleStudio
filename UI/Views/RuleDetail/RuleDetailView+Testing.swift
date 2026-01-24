import SwiftUI

#if DEBUG
extension RuleDetailView {
    @MainActor static func extractRationaleForTesting(_ markdown: String) -> String? {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: markdown
        )
        return RuleDetailView(rule: rule).extractRationale(from: markdown)
    }
    
    @MainActor static func extractSwiftEvolutionLinksForTesting(_ markdown: String) -> [URL] {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: markdown
        )
        return RuleDetailView(rule: rule).extractSwiftEvolutionLinks(from: markdown)
    }
    
    @MainActor static func processContentForDisplayForTesting(_ content: String) -> String {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: content
        )
        return RuleDetailView(rule: rule).processContentForDisplay(content: content)
    }
    
    @MainActor static func convertMarkdownToHTMLForTesting(_ content: String) -> String {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: content
        )
        return RuleDetailView(rule: rule).convertMarkdownToHTML(content: content)
    }
    
    @MainActor static func wrapHTMLInDocumentForTesting(body: String, colorScheme: ColorScheme) -> String {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
        return RuleDetailView(rule: rule).wrapHTMLInDocument(body: body, colorScheme: colorScheme)
    }
}
#endif
