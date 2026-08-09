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

    @Test("Integer parameter Slider is labeled with the parameter name")
    func testSliderLabeled() throws {
        let param = RuleParameter(name: "line_length", type: .integer, defaultValue: AnyCodable(100))
        let host = HostView(parameters: [param])
        let slider = try host.inspect().find(ViewType.Slider.self)
        #expect(try slider.accessibilityLabel().string() == "line_length")
    }

    @Test("Integer parameter Stepper is labeled with the parameter name")
    func testStepperLabeled() throws {
        let param = RuleParameter(name: "line_length", type: .integer, defaultValue: AnyCodable(100))
        let host = HostView(parameters: [param])
        let stepper = try host.inspect().find(ViewType.Stepper.self)
        #expect(try stepper.accessibilityLabel().string() == "line_length")
    }

    @Test("Boolean parameter Toggle is labeled with the parameter name")
    func testToggleLabeled() throws {
        let param = RuleParameter(name: "validates_start", type: .boolean, defaultValue: AnyCodable(false))
        let host = HostView(parameters: [param])
        let toggle = try host.inspect().find(ViewType.Toggle.self)
        #expect(try toggle.accessibilityLabel().string() == "validates_start")
    }
}
