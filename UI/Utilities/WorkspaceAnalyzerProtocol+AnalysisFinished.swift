//
//  WorkspaceAnalyzerProtocol+AnalysisFinished.swift
//  SwiftLintRuleStudio
//

import Combine
import SwiftLintRuleStudioCore

extension WorkspaceAnalyzerProtocol {
    /// Fires when an analysis finishes, wherever it was started from, so a view showing stored
    /// violations can reload them. Each subscription is first handed the current state, which
    /// `dropFirst()` skips.
    var analysisFinishedPublisher: AnyPublisher<Void, Never> {
        isAnalyzingPublisher
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .map { _ in }
            .eraseToAnyPublisher()
    }
}
