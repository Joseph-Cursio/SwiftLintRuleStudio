//
//  MirrorScope+Testing.swift
//  SwiftLintRuleStudioCoreTests
//
//  A scope as it would be for the same workspace outside /private, which a test's temp folder
//  never is.
//

import Foundation
@testable import SwiftLintRuleStudioCore

extension MirrorScope {
    /// This scope with ``isUnderPrivate`` set to `isUnderPrivate`.
    func underPrivate(_ isUnderPrivate: Bool) -> MirrorScope {
        MirrorScope(
            workspaceRoot: workspaceRoot,
            anchor: anchor,
            lintRoot: lintRoot,
            reach: reach,
            walkRoots: walkRoots,
            includedFiles: includedFiles,
            hostedFolders: hostedFolders,
            hostedLinks: hostedLinks,
            referencedConfigs: referencedConfigs,
            configGraph: configGraph,
            exclusions: exclusions,
            isUnderPrivate: isUnderPrivate
        )
    }
}
