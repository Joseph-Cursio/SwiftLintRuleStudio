//
//  RulePresetPicker.swift
//  SwiftLintRuleStudio
//
//  SwiftUI picker component for selecting and applying rule presets
//

import SwiftUI

/// A menu-based picker for selecting and applying rule presets
struct RulePresetPicker: View {
    let onPresetSelected: (RulePreset) -> Void

    var body: some View {
        Menu {
            ForEach(RulePreset.PresetCategory.allCases, id: \.self) { category in
                Section(header: Text(category.displayName)) {
                    ForEach(RulePresets.presets(in: category)) { preset in
                        Button {
                            onPresetSelected(preset)
                        } label: {
                            Label(preset.name, systemImage: preset.icon)
                        }
                    }
                }
            }
        } label: {
            Label("Presets", systemImage: "rectangle.stack")
        }
    }
}

/// A full-screen sheet view for browsing and selecting presets with details
struct RulePresetBrowserView: View {
    let onPresetSelected: (RulePreset) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: RulePreset.PresetCategory?
    @State private var hoveredPreset: RulePreset?

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Category sidebar
                List(selection: $selectedCategory) {
                    Section("Categories") {
                        ForEach(RulePreset.PresetCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.icon)
                                .tag(category as RulePreset.PresetCategory?)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 200)

                Divider()

                // Presets grid
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 250, maximum: 350))],
                        spacing: 16
                    ) {
                        ForEach(filteredPresets) { preset in
                            PresetCard(preset: preset, isHovered: hoveredPreset?.id == preset.id)
                                .onTapGesture {
                                    onPresetSelected(preset)
                                    dismiss()
                                }
                                .onHover { isHovered in
                                    hoveredPreset = isHovered ? preset : nil
                                }
                        }
                    }
                    .padding()
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .navigationTitle("Rule Presets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var filteredPresets: [RulePreset] {
        if let category = selectedCategory {
            return RulePresets.presets(in: category)
        }
        return RulePresets.allPresets
    }
}

/// Card view for displaying a single preset
struct PresetCard: View {
    let preset: RulePreset
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: preset.icon)
                    .font(.title2)
                    .foregroundStyle(categoryColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.headline)

                    Text(preset.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Description
            Text(preset.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Rule count
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("\(preset.ruleIds.count) rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Apply")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(categoryColor)
                    .opacity(isHovered ? 1 : 0)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 8 : 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? categoryColor : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }

    private var categoryColor: Color {
        switch preset.category {
        case .performance:
            return .orange
        case .swiftUI:
            return .blue
        case .concurrency:
            return .purple
        case .codeStyle:
            return .green
        case .documentation:
            return .cyan
        }
    }
}

/// Compact inline preset badge
struct PresetBadge: View {
    let preset: RulePreset

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: preset.icon)
                .font(.caption2)
            Text(preset.name)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(categoryColor.opacity(0.2))
        .foregroundStyle(categoryColor)
        .clipShape(.rect(cornerRadius: 6))
    }

    private var categoryColor: Color {
        switch preset.category {
        case .performance:
            return .orange
        case .swiftUI:
            return .blue
        case .concurrency:
            return .purple
        case .codeStyle:
            return .green
        case .documentation:
            return .cyan
        }
    }
}

#Preview("Preset Picker Menu") {
    RulePresetPicker { preset in
        print("Selected preset: \(preset.name)")
    }
}

#Preview("Preset Browser") {
    RulePresetBrowserView { preset in
        print("Selected preset: \(preset.name)")
    }
}

#Preview("Preset Card") {
    VStack(spacing: 16) {
        PresetCard(preset: RulePresets.performance, isHovered: false)
        PresetCard(preset: RulePresets.swiftUI, isHovered: true)
    }
    .padding()
    .frame(width: 600)
}
