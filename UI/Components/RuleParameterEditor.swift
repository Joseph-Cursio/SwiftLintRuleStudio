//
//  RuleParameterEditor.swift
//  SwiftLintRuleStudio
//
//  Visual editor for rule parameters with typed controls
//

import SwiftUI
import SwiftLintRuleStudioCore

struct RuleParameterEditor: View {
    let parameters: [RuleParameter]
    @Binding var values: [String: AnyCodable]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parameters")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(parameters, id: \.name) { param in
                parameterRow(for: param)
                if param.name != parameters.last?.name {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(.rect(cornerRadius: 6))
    }

    @ViewBuilder
    private func parameterRow(for param: RuleParameter) -> some View {
        switch param.type {
        case .integer:
            IntegerParameterRow(
                param: param,
                value: intBinding(for: param)
            )
        case .boolean:
            BooleanParameterRow(
                param: param,
                value: boolBinding(for: param)
            )
        case .string:
            StringParameterRow(
                param: param,
                value: stringBinding(for: param)
            )
        case .array:
            ArrayParameterRow(
                param: param,
                values: arrayBinding(for: param)
            )
        }
    }

    // MARK: - Bindings

    private func intBinding(for param: RuleParameter) -> Binding<Int> {
        Binding(
            get: { RuleParameterValues(values: values).intValue(for: param) },
            set: { newValue in
                var resolver = RuleParameterValues(values: values)
                resolver.setValue(newValue, for: param)
                values = resolver.values
            }
        )
    }

    private func boolBinding(for param: RuleParameter) -> Binding<Bool> {
        Binding(
            get: { RuleParameterValues(values: values).boolValue(for: param) },
            set: { newValue in
                var resolver = RuleParameterValues(values: values)
                resolver.setValue(newValue, for: param)
                values = resolver.values
            }
        )
    }

    private func stringBinding(for param: RuleParameter) -> Binding<String> {
        Binding(
            get: { RuleParameterValues(values: values).stringValue(for: param) },
            set: { newValue in
                var resolver = RuleParameterValues(values: values)
                resolver.setValue(newValue, for: param)
                values = resolver.values
            }
        )
    }

    private func arrayBinding(for param: RuleParameter) -> Binding<[String]> {
        Binding(
            get: { RuleParameterValues(values: values).arrayValue(for: param) },
            set: { newValue in
                var resolver = RuleParameterValues(values: values)
                resolver.setValue(newValue, for: param)
                values = resolver.values
            }
        )
    }
}

// MARK: - Parameter Row Views

private struct IntegerParameterRow: View {
    let param: RuleParameter
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(param.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let desc = param.description {
                    HelpPopover(text: desc)
                }

                Spacer()

                defaultIndicator
            }

            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = Int($0) }
                    ),
                    in: 1...500,
                    step: 1
                )
                .frame(maxWidth: 200)

                TextField(
                    "Value",
                    value: $value,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)

                Stepper("", value: $value, in: 1...10000)
                    .labelsHidden()
            }
        }
    }

    private var defaultIndicator: some View {
        Group {
            if let defaultInt = param.defaultValue.value as? Int {
                Text("Default: \(defaultInt)")
                    .font(.caption)
                    .foregroundStyle(value != defaultInt ? .orange : .secondary)
            }
        }
    }
}

private struct BooleanParameterRow: View {
    let param: RuleParameter
    @Binding var value: Bool

    var body: some View {
        HStack {
            Text(param.name)
                .font(.body)
                .fontWeight(.medium)

            if let desc = param.description {
                HelpPopover(text: desc)
            }

            Spacer()

            defaultIndicator

            Toggle("", isOn: $value)
                .labelsHidden()
        }
    }

    private var defaultIndicator: some View {
        Group {
            if let defaultBool = param.defaultValue.value as? Bool {
                Text("Default: \(defaultBool ? "On" : "Off")")
                    .font(.caption)
                    .foregroundStyle(value != defaultBool ? .orange : .secondary)
            }
        }
    }
}

private struct StringParameterRow: View {
    let param: RuleParameter
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(param.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let desc = param.description {
                    HelpPopover(text: desc)
                }

                Spacer()

                defaultIndicator
            }

            TextField("Value", text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var defaultIndicator: some View {
        Group {
            if let defaultStr = param.defaultValue.value as? String {
                Text("Default: \(defaultStr)")
                    .font(.caption)
                    .foregroundStyle(value != defaultStr ? .orange : .secondary)
            }
        }
    }
}

private struct ArrayParameterRow: View {
    let param: RuleParameter
    @Binding var values: [String]
    @State private var newItem: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(param.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let desc = param.description {
                    HelpPopover(text: desc)
                }

                Spacer()

                Text("\(values.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        values.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Remove item")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }

            HStack {
                TextField("Add item...", text: $newItem)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addItem()
                    }

                Button {
                    addItem()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Add item")
                }
                .buttonStyle(.plain)
                .disabled(RuleParameterValues.sanitizedArrayItem(newItem) == nil)
            }
        }
    }

    private func addItem() {
        guard let trimmed = RuleParameterValues.sanitizedArrayItem(newItem) else { return }
        values.append(trimmed)
        newItem = ""
    }
}

// MARK: - Help Popover

private struct HelpPopover: View {
    let text: String
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Help")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowing) {
            Text(text)
                .font(.caption)
                .padding(8)
                .frame(maxWidth: 250)
        }
    }
}
