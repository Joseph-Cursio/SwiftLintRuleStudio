//
//  ExportReportView.swift
//  SwiftLintRuleStudio
//
//  View for exporting violation reports in HTML, JSON, or CSV format
//

import SwiftUI

struct ExportReportView: View {
    @State private var model = ExportReportModel()

    var body: some View {
        ExportReportContent(model: model)
    }
}
