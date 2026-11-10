//
//  ExportReportContent.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore
import SwiftUI

/// The export form: format, contents, output path and the export action, drawn from and
/// writing to the model `ExportReportView` owns.
struct ExportReportContent: View {
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Bindable var model: ExportReportModel

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
        .alert("Export Error", isPresented: $model.showError) {
            Button("OK") { }
        } message: {
            Text(model.errorMessage)
        }
    }
}
