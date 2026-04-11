//
//  ExportReportView.swift
//  SwiftLintRuleStudio
//
//  View for exporting violation reports in HTML, JSON, or CSV format
//

import SwiftUI
import SwiftLintRuleStudioCore

struct ExportReportView: View {
    @Environment(\.dependencies) var dependencies: DependencyContainer

    @State var selectedFormat: ExportFormat = .html
    @State var includeSummary = true
    @State var includeDetailedList = true
    @State var includeCodeSnippets = true
    @State var includeRuleConfig = false
    @State var includeHistoricalTrends = false
    @State var outputPath: String = ""
    @State var isExporting = false
    @State var exportComplete = false
    @State var showError = false
    @State var errorMessage = ""
    @State var violations: [Violation] = []
    @State var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                formatSection
                contentSection
                outputSection
                actionSection
            }
            .padding(24)
        }
        .navigationTitle("Export Report")
        .onAppear(perform: loadViolations)
        .alert("Export Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case html = "HTML"
    case json = "JSON"
    case csv = "CSV"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .html: "Interactive report"
        case .json: "Machine-readable"
        case .csv: "Spreadsheet"
        }
    }

    var iconName: String {
        switch self {
        case .html: "doc.richtext"
        case .json: "curlybraces"
        case .csv: "tablecells"
        }
    }

    var fileExtension: String {
        rawValue.lowercased()
    }
}
