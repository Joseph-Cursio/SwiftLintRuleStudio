//
//  RuleParameterEditorTests.swift
//  SwiftLintRuleStudioTests
//
//  Accessibility regression for P1.4: the Slider / Stepper / Toggle that edit a
//  rule parameter had no accessible name, so VoiceOver announced a bare
//  "Slider"/"Stepper"/"Switch" with no indication of which parameter they control.
//

@testable import SwiftLintRuleStudio
import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct RuleParameterEditorTests {
    private struct HostView: View {
        let parameters: [RuleParameter]
        @State var values: [String: AnyCodable] = [:]

        var body: some View {
            RuleParameterEditor(parameters: parameters, values: $values)
        }
    }

    // The three label tests below are disabled on macOS 27 beta (build 26A5388g).
    // ViewInspector 0.10.3 cannot read accessibility modifiers on this SwiftUI: its
    // `accessibilityLabel()` takes the `#available(macOS 26.0, *)` branch, which
    // reads a fixed keypath off an `AccessibilityAttachmentModifier` that this OS
    // lays out differently, so every lookup throws. Not specific to these views — a
    // bare `Button("Hi") {}.accessibilityLabel("x")` fails identically, while
    // non-accessibility traversal still works. The labels are correct and present in
    // RuleParameterEditor; only test-time introspection is broken, and the XCUITest
    // target still reads the real accessibility tree. Re-enable when upstream ships
    // the fix (nalexn/ViewInspector PR #421, unmerged as of 2026-08-07).
    @Test("Integer parameter Slider is labeled with the parameter name",
          .disabled("ViewInspector 0.10.3 cannot read accessibility modifiers on macOS 27"))
    func testSliderLabeled() throws {
        let param = RuleParameter(name: "line_length", type: .integer, defaultValue: AnyCodable(100))
        let host = HostView(parameters: [param])
        let slider = try host.inspect().find(ViewType.Slider.self)
        #expect(try slider.accessibilityLabel().string() == "line_length")
    }

    @Test("Integer parameter Stepper is labeled with the parameter name",
          .disabled("ViewInspector 0.10.3 cannot read accessibility modifiers on macOS 27"))
    func testStepperLabeled() throws {
        let param = RuleParameter(name: "line_length", type: .integer, defaultValue: AnyCodable(100))
        let host = HostView(parameters: [param])
        let stepper = try host.inspect().find(ViewType.Stepper.self)
        #expect(try stepper.accessibilityLabel().string() == "line_length")
    }

    @Test("Boolean parameter Toggle is labeled with the parameter name",
          .disabled("ViewInspector 0.10.3 cannot read accessibility modifiers on macOS 27"))
    func testToggleLabeled() throws {
        let param = RuleParameter(name: "validates_start", type: .boolean, defaultValue: AnyCodable(false))
        let host = HostView(parameters: [param])
        let toggle = try host.inspect().find(ViewType.Toggle.self)
        #expect(try toggle.accessibilityLabel().string() == "validates_start")
    }
}
