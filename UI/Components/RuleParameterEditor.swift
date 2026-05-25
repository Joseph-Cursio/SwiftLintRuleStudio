//
//  RuleParameterEditor.swift
//  SwiftLintRuleStudio
//
//  Visual editor for rule parameters with typed controls
//

import SwiftLintRuleStudioCore
import SwiftUI

private struct IntegerParameterRow: View {
    let param: RuleParameter
    @Binding var value: Int
    let hasOverride: Bool
    let reset: () -> Void

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
            }

            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = Int($0) }
                    ),
                    in: 1...500
                )
                .frame(maxWidth: 200)

                TextField(
                    "Value",
                    value: $value,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)

                Stepper("", value: $value, in: 1...10_000)
                    .labelsHidden()

                Spacer()

                defaultIndicator
            }
        }
    }

    @ViewBuilder
    private var defaultIndicator: some View {
        if let defaultInt = param.defaultValue.value as? Int {
            DefaultIndicator(
                label: "Default: \(defaultInt)",
                isOverridden: hasOverride && value != defaultInt,
                reset: reset
            )
        }
    }
}

private struct BooleanParameterRow: View {
    let param: RuleParameter
    @Binding var value: Bool
    let hasOverride: Bool
    let reset: () -> Void

    var body: some View {
        HStack {
            Text(param.name)
                .font(.body)
                .fontWeight(.medium)

            if let desc = param.description {
                HelpPopover(text: desc)
            }

            Toggle("", isOn: $value)
                .labelsHidden()

            Spacer()

            defaultIndicator
        }
    }

    @ViewBuilder
    private var defaultIndicator: some View {
        if let defaultBool = param.defaultValue.value as? Bool {
            DefaultIndicator(
                label: "Default: \(defaultBool ? "On" : "Off")",
                isOverridden: hasOverride && value != defaultBool,
                reset: reset
            )
        }
    }
}

private struct StringParameterRow: View {
    let param: RuleParameter
    @Binding var value: String
    let hasOverride: Bool
    let reset: () -> Void

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
            }

            HStack(spacing: 12) {
                TextField("Value", text: $value)
                    .textFieldStyle(.roundedBorder)

                defaultIndicator
            }
        }
    }

    @ViewBuilder
    private var defaultIndicator: some View {
        if let defaultStr = param.defaultValue.value as? String {
            DefaultIndicator(
                label: "Default: \(defaultStr)",
                isOverridden: hasOverride && value != defaultStr,
                reset: reset
            )
        }
    }
}

private struct ArrayParameterRow: View {
    let param: RuleParameter
    @Binding var values: [String]
    let hasOverride: Bool
    let reset: () -> Void
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

                if hasOverride {
                    let defaultCount = (param.defaultValue.value as? [Any])?.count ?? 0
                    Button("Reset", action: reset)
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .controlSize(.small)
                        .font(.caption)
                        .help("Reset to default (\(defaultCount) items)")
                }

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

/// Default-value indicator that doubles as a "reset to default" button when
/// the parameter currently holds an override. Tapping it removes the entry
/// from the parameter dictionary, causing the editor to fall back to the
/// schema's default at display time.
private struct DefaultIndicator: View {
    let label: String
    let isOverridden: Bool
    let reset: () -> Void

    var body: some View {
        Button(action: reset) {
            Text(label)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(isOverridden ? .orange : .secondary)
        .help(isOverridden ? "Click to reset to default" : "Already at default")
        .disabled(!isOverridden)
    }
}

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

struct RuleParameterEditor: View {
    let parameters: [RuleParameter]
    @Binding var values: [String: AnyCodable]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parameters, id: \.name) { param in
                parameterRow(for: param)
                if param.name != parameters.last?.name {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func parameterRow(for param: RuleParameter) -> some View {
        let hasOverride = values[param.name] != nil
        let reset: () -> Void = { values.removeValue(forKey: param.name) }
        switch param.type {
        case .integer:
            IntegerParameterRow(
                param: param,
                value: intBinding(for: param),
                hasOverride: hasOverride,
                reset: reset
            )
        case .boolean:
            BooleanParameterRow(
                param: param,
                value: boolBinding(for: param),
                hasOverride: hasOverride,
                reset: reset
            )
        case .string:
            StringParameterRow(
                param: param,
                value: stringBinding(for: param),
                hasOverride: hasOverride,
                reset: reset
            )
        case .array:
            ArrayParameterRow(
                param: param,
                values: arrayBinding(for: param),
                hasOverride: hasOverride,
                reset: reset
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
