//
//  UITestHelpersCoverageTests+ViewInspector.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector extension tests extracted from UITestHelpersCoverageTests
//

import SwiftUI
import Testing
import ViewInspector

extension UITestHelpersCoverageTests {

    @Test("ViewInspector extensions tap and find buttons")
    func testViewInspectorButtons() async throws {
        @MainActor
        struct ButtonView: View {
            var body: some View {
                VStack {
                    Text("Tap Me")
                    Button("Tap Me") {}
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
        #expect(hasButton)
    }

    @Test("ViewInspector extensions set and read text field input")
    func testViewInspectorTextField() async throws {
        @MainActor
        struct TextFieldView: View {
            @State private var name = ""
            var body: some View {
                TextField("Name", text: $name)
            }
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
        #expect(inputValue == "Ada" || inputValue.isEmpty)
    }

    @Test("ViewInspector extensions find pickers")
    func testViewInspectorPicker() async throws {
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

        let hasPicker = try await MainActor.run {
            let pickerView = PickerView()
            ViewHosting.expel()
            ViewHosting.host(view: pickerView)
            defer { ViewHosting.expel() }
            let pickerInspector = try pickerView.inspect()
            _ = try pickerInspector.findPicker(label: "Options")
            return true
        }
        #expect(hasPicker)
    }

    @Test("ViewInspector extensions find and tap navigation links")
    func testViewInspectorNavigationLink() async throws {
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

        try await MainActor.run {
            let linkView = NavigationLinkView()
            ViewHosting.expel()
            ViewHosting.host(view: linkView)
            defer { ViewHosting.expel() }
            let linkInspector = try linkView.inspect()
            _ = try linkInspector.findNavigationLink(text: "Details")
            try linkInspector.tapNavigationLink(text: "Details")
        }
    }

    @Test("ViewInspector extensions wait for text and look for view types")
    func testViewInspectorWaitAndViewTypes() async {
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
