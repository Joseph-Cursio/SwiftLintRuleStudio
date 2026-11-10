//
//  ExportReportModel.swift
//  SwiftLintRuleStudio
//

import Foundation
import LintStudioUI
import Observation
import SwiftLintRuleStudioCore

/// The export form's choices and progress: format, what to include, where to write, the
/// violations loaded for it, and an error to report. `ExportReportView` owns one and hands it
/// to `ExportReportContent`.
@MainActor
@Observable
final class ExportReportModel {
    var selectedFormat: ExportFormat = .html
    var includeSummary = true
    var includeDetailedList = true
    var includeCodeSnippets = true
    var includeRuleConfig = false
    var includeHistoricalTrends = false
    var outputPath: String = ""
    var isExporting = false
    var exportComplete = false
    var showError = false
    var errorMessage = ""
    var violations: [Violation] = []
    var isLoading = false
}
