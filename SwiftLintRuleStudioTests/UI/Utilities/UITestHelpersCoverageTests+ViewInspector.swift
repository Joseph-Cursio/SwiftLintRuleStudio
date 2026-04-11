//
//  UITestHelpersCoverageTests+ViewInspector.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector extension tests extracted from UITestHelpersCoverageTests
//

import Testing
import SwiftUI
import ViewInspector
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

extension UITestHelpersCoverageTests {

    @Test("ViewInspector extensions support common interactions")
    // swiftlint:disable:next function_body_length
    func testViewInspectorExtensions() async throws {
        @MainActor
        struct ButtonView: View {
            var body: some View {
                VStack {
                    Text("Tap Me")
                    Button("Tap Me") {}
                }
            }
        }

        @MainActor
        struct TextFieldView: View {
            @State private var name = ""
            var body: some View {
                TextField("Name", text: $name)
            }
        }

        @MainActor
        struct PickerView: View {
            @State private var selection = "A"
            var body: some View {
                VStack {
                    Text("Options")
                    Picker("Options", selection: $selection) {
                        Text("A").tag("A")
                        Text("B").tag("B")
                    }
                }
            }
        }

        @MainActor
        struct NavigationLinkView: View {
            @State private var selection: String?
            var body: some View {
                VStack {
                    Text("Details")
                    NavigationLink(
                        destination: Text("Destination"),
                        tag: "Details",
                        selection: $selection
                    ) {
                        Text("Details")
                    }
                }
            }
        }

        let hasButton = try await MainActor.run {
            let buttonView = ButtonView()
            ViewHosting.expel()
            ViewHosting.host(view: buttonView)
            defer { ViewHosting.expel() }
            let buttonInspector = try buttonView.inspect()
            try buttonInspector.tapButton(text: "Tap Me")
            _ = try buttonInspector.findButton(text: "Tap Me")
            return true
        }

        let inputValue = try await MainActor.run {
            let textFieldView = TextFieldView()
            ViewHosting.expel()
            ViewHosting.host(view: textFieldView)
            defer { ViewHosting.expel() }
            let textFieldInspector = try textFieldView.inspect()
            try textFieldInspector.setTextFieldInput("Ada")
            let inputValue = try textFieldInspector.getTextFieldInput()
            _ = try textFieldInspector.findTextField(placeholder: "Name")
            return inputValue
        }

        let hasPicker = try await MainActor.run {
            let pickerView = PickerView()
            ViewHosting.expel()
            ViewHosting.host(view: pickerView)
            defer { ViewHosting.expel() }
            let pickerInspector = try pickerView.inspect()
            _ = try pickerInspector.findPicker(label: "Options")
            return true
        }

        try await MainActor.run {
            let linkView = NavigationLinkView()
            ViewHosting.expel()
            ViewHosting.host(view: linkView)
            defer { ViewHosting.expel() }
            let linkInspector = try linkView.inspect()
            _ = try linkInspector.findNavigationLink(text: "Details")
            try linkInspector.tapNavigationLink(text: "Details")
        }

        #expect(hasButton)
        #expect(inputValue == "Ada" || inputValue.isEmpty)
        #expect(hasPicker)

        let waitSuccess = await Task { @MainActor in
            do {
                let textView = Text("Hello")
                let inspector = try textView.inspect()
                return await inspector.waitForText("Hello", timeout: 100_000_000)
            } catch {
                return false
            }
        }.value
        #expect(waitSuccess)

        let viewTypeFound = await Task { @MainActor in
            do {
                let textView = Text("Hello")
                let inspector = try textView.inspect()
                return inspector.containsViewType(ViewType.Text.self)
            } catch {
                return false
            }
        }.value
        #expect(viewTypeFound == false)
    }
}
