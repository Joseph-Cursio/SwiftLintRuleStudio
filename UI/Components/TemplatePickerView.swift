//
//  TemplatePickerView.swift
//  SwiftLintRuleStudio
//
//  Compact template picker for quick template selection
//

import SwiftUI

/// Compact modal picker for selecting a template
struct TemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let onTemplateSelected: (ConfigurationTemplate) -> Void
    let templateManager: ConfigurationTemplateManager

    @State private var selectedProjectType: ConfigurationTemplate.ProjectType = .iOSApp
    @State private var selectedCodingStyle: ConfigurationTemplate.CodingStyle = .balanced
    @State private var hoveredTemplate: ConfigurationTemplate?

    init(
        templateManager: ConfigurationTemplateManager = ConfigurationTemplateManager(),
        onTemplateSelected: @escaping (ConfigurationTemplate) -> Void
    ) {
        self.templateManager = templateManager
        self.onTemplateSelected = onTemplateSelected
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose a Template")
                    .font(.headline)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Filters
            HStack(spacing: 16) {
                Picker("Project", selection: $selectedProjectType) {
                    ForEach(ConfigurationTemplate.ProjectType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                Picker("Style", selection: $selectedCodingStyle) {
                    ForEach(ConfigurationTemplate.CodingStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()

            Divider()

            // Template grid
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 300))],
                    spacing: 12
                ) {
                    ForEach(filteredTemplates) { template in
                        TemplatePickerCard(
                            template: template,
                            isHovered: hoveredTemplate?.id == template.id,
                            onSelect: {
                                onTemplateSelected(template)
                                dismiss()
                            }
                        )
                        .onHover { isHovered in
                            hoveredTemplate = isHovered ? template : nil
                        }
                    }
                }
                .padding()
            }

            if filteredTemplates.isEmpty {
                Spacer()
                Text("No templates available for this selection")
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Text("\(filteredTemplates.count) templates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
    }

    private var filteredTemplates: [ConfigurationTemplate] {
        templateManager.allTemplates.filter { template in
            template.projectType == selectedProjectType &&
            template.codingStyle == selectedCodingStyle
        }
    }
}

/// Card view for a template in the picker
struct TemplatePickerCard: View {
    let template: ConfigurationTemplate
    let isHovered: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: template.projectType.icon)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text(template.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()
                }

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack {
                    CodingStyleBadge(style: template.codingStyle)

                    Spacer()

                    if isHovered {
                        Text("Select")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHovered ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

/// Menu button for quick template selection
struct TemplateMenuButton: View {
    let templateManager: ConfigurationTemplateManager
    let onTemplateSelected: (ConfigurationTemplate) -> Void

    init(
        templateManager: ConfigurationTemplateManager = ConfigurationTemplateManager(),
        onTemplateSelected: @escaping (ConfigurationTemplate) -> Void
    ) {
        self.templateManager = templateManager
        self.onTemplateSelected = onTemplateSelected
    }

    var body: some View {
        Menu {
            ForEach(ConfigurationTemplate.ProjectType.allCases, id: \.self) { projectType in
                Menu(projectType.rawValue) {
                    ForEach(templateManager.templates(for: projectType)) { template in
                        Button {
                            onTemplateSelected(template)
                        } label: {
                            HStack {
                                Text(template.name)
                                Spacer()
                                CodingStyleText(style: template.codingStyle)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Templates", systemImage: "doc.text")
        }
    }
}

/// Simple text view for coding style (used in menus)
struct CodingStyleText: View {
    let style: ConfigurationTemplate.CodingStyle

    var body: some View {
        Text(style.rawValue)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview("Template Picker") {
    TemplatePickerView { template in
        print("Selected: \(template.name)")
    }
}

#Preview("Template Picker Card") {
    VStack(spacing: 12) {
        TemplatePickerCard(
            template: BuiltInTemplates.iOSStrict,
            isHovered: false,
            onSelect: {}
        )
        TemplatePickerCard(
            template: BuiltInTemplates.iOSBalanced,
            isHovered: true,
            onSelect: {}
        )
    }
    .padding()
    .frame(width: 300)
}

#Preview("Template Menu Button") {
    TemplateMenuButton { template in
        print("Selected: \(template.name)")
    }
    .padding()
}
