//
//  AppSectionTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Every section is offered, and every section is named.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

/// A destination that exists must be reachable and must have a name.
///
/// The title menu used to be eleven hand-written buttons against an enum of twelve cases, so
/// Config Map was a section the app could show and the menu never offered — reachable from the
/// sidebar and from nowhere else. Nothing failed, because a transcribed list cannot disagree with
/// itself; it can only disagree with the enum, and nothing was comparing them.
///
/// The menu is derived from `allCases` now, which makes the omission unrepresentable rather than
/// merely fixed. These pin the two properties that derivation relies on.
@Suite("Every AppSection is offered and named")
struct AppSectionTests {

    @Test("every case has a non-empty title")
    func everyCaseIsNamed() {
        for section in AppSection.allCases {
            #expect(section.title.isEmpty == false, "\(section) has no title")
        }
    }

    /// Two sections sharing a name would be two menu entries a user cannot tell apart — the same
    /// class of fault as a missing one, and equally invisible without a check.
    @Test("no two cases share a title")
    func titlesAreDistinct() {
        let titles = AppSection.allCases.map(\.title)
        #expect(Set(titles).count == titles.count, "duplicate titles in \(titles)")
    }

    /// The regression itself. `allCases` is what the menu iterates, so a case added to the enum
    /// and forgotten in the menu is now impossible — but only while the menu keeps deriving from
    /// this, and only while `configMap` is actually in it.
    @Test("configMap is among the cases the menu is built from")
    func configMapIsOffered() {
        #expect(AppSection.allCases.contains(.configMap))
    }
}
