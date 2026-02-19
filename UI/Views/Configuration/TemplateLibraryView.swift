//
//  TemplateLibraryView.swift
//  SwiftLintRuleStudio
//
//  View for browsing and selecting configuration templates
//

import SwiftUI

/// Main view for browsing the template library
struct TemplateLibraryView: View {
    @State private var selectedProjectType: ConfigurationTemplate.ProjectType?
    @State private var selectedCodingStyle: ConfigurationTemplate.CodingStyle?
    @State private var searchText = ""
    @State private var selectedTemplate: ConfigurationTemplate?

    let onTemplateSelected: ((ConfigurationTemplate) -> Void)?
    let templateManager: ConfigurationTemplateManager

    init(
        templateManager: ConfigurationTemplateManager = ConfigurationTemplateManager(),
        onTemplateSelected: ((ConfigurationTemplate) -> Void)? = nil
    ) {
        self.templateManager = templateManager
        self.onTemplateSelected = onTemplateSelected
    }

    var body: some View {
        NavigationSplitView {
            sidebarView
        } content: {
            templateListView
        } detail: {
            detailView
        }
        .navigationTitle("Template Library")
    }

    @ViewBuilder
    private var sidebarView: some View {
        List(selection: $selectedProjectType) {
            projectTypeSection
            codingStyleSection
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }

    @ViewBuilder
    private var projectTypeSection: some View {
        Section("Project Type") {
            Text("All Projects")
                .tag(nil as ConfigurationTemplate.ProjectType?)

            ForEach(ConfigurationTemplate.ProjectType.allCases, id: \.self) { projectType in
                Label(projectType.rawValue, systemImage: projectType.icon)
                    .tag(projectType as ConfigurationTemplate.ProjectType?)
            }
        }
    }

    @ViewBuilder
    private var codingStyleSection: some View {
        Section("Coding Style") {
            ForEach(ConfigurationTemplate.CodingStyle.allCases, id: \.self) { style in
                codingStyleButton(for: style)
            }
        }
    }

    @ViewBuilder
    private func codingStyleButton(for style: ConfigurationTemplate.CodingStyle) -> some View {
        Button {
            if selectedCodingStyle == style {
                selectedCodingStyle = nil
            } else {
                selectedCodingStyle = style
            }
        } label: {
            HStack {
                Text(style.rawValue)
                Spacer()
                if selectedCodingStyle == style {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var templateListView: some View {
        List(selection: $selectedTemplate) {
            if !filteredBuiltInTemplates.isEmpty {
                Section("Built-in Templates") {
                    ForEach(filteredBuiltInTemplates) { template in
                        TemplateListRow(template: template)
                            .tag(template)
                    }
                }
            }

            if !filteredUserTemplates.isEmpty {
                Section("Your Templates") {
                    ForEach(filteredUserTemplates) { template in
                        TemplateListRow(template: template)
                            .tag(template)
                    }
                }
            }
        }
        .listStyle(.inset)
        .searchable(text: $searchText, prompt: "Search templates")
        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        .overlay {
            if filteredBuiltInTemplates.isEmpty && filteredUserTemplates.isEmpty {
                ContentUnavailableView(
                    "No Templates",
                    systemImage: "doc.text",
                    description: Text("No templates match your filters")
                )
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let template = selectedTemplate {
            TemplateDetailView(
                template: template,
                onApply: onTemplateSelected
            )
        } else {
            ContentUnavailableView(
                "Select a Template",
                systemImage: "doc.text",
                description: Text("Choose a template to see its details")
            )
        }
    }

    private var filteredBuiltInTemplates: [ConfigurationTemplate] {
        filterTemplates(templateManager.builtInTemplates)
    }

    private var filteredUserTemplates: [ConfigurationTemplate] {
        filterTemplates(templateManager.userTemplates)
    }

    private func filterTemplates(_ templates: [ConfigurationTemplate]) -> [ConfigurationTemplate] {
        templates.filter { template in
            // Project type filter
            if let projectType = selectedProjectType, template.projectType != projectType {
                return false
            }

            // Coding style filter
            if let codingStyle = selectedCodingStyle, template.codingStyle != codingStyle {
                return false
            }

            // Search filter
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return template.name.lowercased().contains(searchLower) ||
                    template.description.lowercased().contains(searchLower)
            }

            return true
        }
    }
}

/// Row view for a single template in the list
struct TemplateListRow: View {
    let template: ConfigurationTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: template.projectType.icon)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(template.name)
                    .font(.headline)
                    .lineLimit(1)

                if template.isBuiltIn {
                    Text("Built-in")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundStyle(.blue)
                        .clipShape(.rect(cornerRadius: 4))
                }
            }

            Text(template.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                CodingStyleBadge(style: template.codingStyle)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Badge showing the coding style
struct CodingStyleBadge: View {
    let style: ConfigurationTemplate.CodingStyle

    var body: some View {
        Text(style.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(styleColor.opacity(0.2))
            .foregroundStyle(styleColor)
            .clipShape(.rect(cornerRadius: 4))
    }

    private var styleColor: Color {
        switch style {
        case .strict: return .red
        case .balanced: return .blue
        case .lenient: return .green
        }
    }
}

/// Detail view for a selected template
struct TemplateDetailView: View {
    let template: ConfigurationTemplate
    let onApply: ((ConfigurationTemplate) -> Void)?

    @State private var showYAML = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                codingStyleSection
                Divider()
                yamlPreviewSection
                applyButtonSection
            }
            .padding()
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: template.projectType.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        Text(template.projectType.rawValue)
                            .foregroundStyle(.secondary)
                        CodingStyleBadge(style: template.codingStyle)
                    }
                }
            }

            Text(template.description)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var codingStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About \(template.codingStyle.rawValue) Style")
                .font(.headline)

            Text(template.codingStyle.description)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var yamlPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Configuration Preview")
                    .font(.headline)

                Spacer()

                Button {
                    showYAML.toggle()
                } label: {
                    Label(
                        showYAML ? "Hide YAML" : "Show YAML",
                        systemImage: showYAML ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if showYAML {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(template.yamlContent)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
                .frame(maxHeight: 300)
            }
        }
    }

    @ViewBuilder
    private var applyButtonSection: some View {
        if let onApply = onApply {
            Divider()

            Button {
                onApply(template)
            } label: {
                Label("Apply This Template", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

#Preview("Template Library") {
    TemplateLibraryView { template in
        print("Selected: \(template.name)")
    }
    .frame(width: 900, height: 600)
}

#Preview("Template Detail") {
    TemplateDetailView(
        template: BuiltInTemplates.iOSStrict,
        onApply: { _ in }
    )
    .frame(width: 500, height: 600)
}
