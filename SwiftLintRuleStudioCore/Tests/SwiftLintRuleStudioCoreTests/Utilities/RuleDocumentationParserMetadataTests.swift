//
//  RuleDocumentationParserMetadataTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The metadata a rule's generated docs carry: default severity, minimum
//  Swift version, and the description shown in the rule list. The fixtures
//  follow `swiftlint generate-docs` (0.65.1), which writes each table cell over
//  three lines. The severity reader used to accept only a one-line cell, so it
//  found no default severity in any real doc.
//

@testable import SwiftLintRuleStudioCore
import Testing

struct RuleDocumentationParserMetadataTests {

    /// `force_cast.md` as SwiftLint 0.65.1 generates it, with the severity given.
    private static func generatedDoc(severity: String, extraKeys: String = "") -> String {
        """
        # Force Cast

        Force casts should be avoided

        * **Identifier:** `force_cast`
        * **Enabled by default:** Yes
        * **Supports autocorrection:** No
        * **Kind:** idiomatic
        * **Analyzer rule:** No
        * **Minimum Swift compiler version:** 5.0.0
        * **Default configuration:**
          <table>
          <thead>
          <tr><th>Key</th><th>Value</th></tr>
          </thead>
          <tbody>
          \(extraKeys)<tr>
          <td>
          severity
          </td>
          <td>
          \(severity)
          </td>
          </tr>
          </tbody>
          </table>
        """
    }

    @Test("the default severity is read from a generated doc's three-line cells", arguments: [
        ("error", Severity.error), ("warning", Severity.warning)
    ])
    func severityFromGeneratedDoc(written: String, expected: Severity) {
        let parsed = RuleDocumentationParser.parse(markdown: Self.generatedDoc(severity: written))
        #expect(parsed.defaultSeverity == expected)
    }

    @Test("a one-line cell is read too")
    func severityFromOneLineCell() {
        let markdown = """
            # Rule

            * **Default configuration:**
              <table>
              <tr>
              <td>severity</td>
              <td>warning</td>
              </tr>
              </table>
            """
        #expect(RuleDocumentationParser.parse(markdown: markdown).defaultSeverity == .warning)
    }

    @Test("only the key named exactly `severity` is read, not other keys ending in it")
    func otherSeverityKeysAreNotTheDefault() {
        let markdown = """
            # Expiring Todo

            * **Default configuration:**
              <table>
              <tbody>
              <tr>
              <td>
              expired_severity
              </td>
              <td>
              error
              </td>
              </tr>
              </tbody>
              </table>
            """
        #expect(RuleDocumentationParser.parse(markdown: markdown).defaultSeverity == nil)
    }

    @Test("a value that is not a severity is not one")
    func unknownSeverityValue() {
        #expect(RuleDocumentationParser.parse(markdown: Self.generatedDoc(severity: "off")).defaultSeverity == nil)
    }

    @Test("a table cell with no severity key yields none, even beside a severity-like value")
    func valueWithoutKey() {
        let markdown = """
            # Rule

            * **Default configuration:**
              <table>
              <tr>
              <td>reporter</td>
              <td>error</td>
              </tr>
              </table>
            """
        #expect(RuleDocumentationParser.parse(markdown: markdown).defaultSeverity == nil)
    }

    @Test("backticks are stripped only from a value that is wholly quoted")
    func backtickStripping() {
        let quoted = RuleDocumentationParser.parse(markdown: "# R\n\n* **Minimum Swift compiler version:** `5.9.0`")
        #expect(quoted.minimumSwiftVersion == "5.9.0")
        let partly = RuleDocumentationParser.parse(
            markdown: "# R\n\n* **Minimum Swift compiler version:** `5.9.0` or later"
        )
        #expect(partly.minimumSwiftVersion == "`5.9.0` or later")
    }

    @Test("a short description is kept as written, with or without a closing period")
    func shortDescriptionIsUntouched() {
        let parsed = RuleDocumentationParser.parse(markdown: Self.generatedDoc(severity: "error"))
        #expect(parsed.description == "Force casts should be avoided")
        #expect(RuleDocumentationParser.parse(markdown: "# R\n\n* **Identifier:** `r`").description.isEmpty)
    }
}
