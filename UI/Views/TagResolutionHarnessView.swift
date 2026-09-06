//
//  TagResolutionHarnessView.swift
//  SwiftLintRuleStudio
//
//  Does `.tag()` still reach its `List` from inside an extracted `View` struct?
//
//  `Computed Property View` proposes turning a computed `some View` property into its own struct.
//  Several properties in this app are `Section`s of tagged rows inside a `List(selection:)` —
//  `SidebarView` is four of them — and the open question is whether SwiftUI still resolves a tag
//  that sits one `View` struct further down. If it does not, following the rule there would break
//  navigation rather than merely change how it redraws, and the rule should stay quiet about that
//  shape the way it already does for a dialog's buttons.
//
//  The question is not answerable by reading the view tree: a tag is *declared* in both shapes, so
//  an inspector finds it either way. Only SwiftUI's own resolution decides, and only a click
//  observes it. Hence a harness screen and a UI test that clicks.
//
//  Shown only under `-uiTesting` with `UI_TEST_TAG_HARNESS=1`.
//

import SwiftUI

/// A row whose `.tag()` is applied inside this struct rather than at the call site.
///
/// This is what extracting a tagged row into its own `View` produces, and the shape under test.
private struct ExtractedTaggedRow: View {
    let title: String
    let value: Int

    var body: some View {
        Text(title).tag(value)
    }
}

struct TagResolutionHarnessView: View {
    /// Tag values deliberately unrelated to row position.
    ///
    /// With tags of 1 and 2 on rows 1 and 2, a SwiftUI that ignored the tag and fell back to
    /// positional identity would write the same number the tag would have, and the measurement
    /// would pass without proving anything. 101 and 202 cannot be produced by counting rows.
    private static let firstTag = 101
    private static let secondTag = 202

    @State private var inlineSelection: Int?
    @State private var extractedSelection: Int?
    @State private var untaggedSelection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inline")
            List(selection: $inlineSelection) {
                Text("inline-one").tag(Self.firstTag)
                Text("inline-two").tag(Self.secondTag)
            }
            .frame(height: 90)
            .accessibilityIdentifier("InlineList")

            Text(label(for: inlineSelection))
                .accessibilityIdentifier("InlineSelection")

            Text("Extracted")
            List(selection: $extractedSelection) {
                ExtractedTaggedRow(title: "extracted-one", value: Self.firstTag)
                ExtractedTaggedRow(title: "extracted-two", value: Self.secondTag)
            }
            .frame(height: 90)
            .accessibilityIdentifier("ExtractedList")

            Text(label(for: extractedSelection))
                .accessibilityIdentifier("ExtractedSelection")

            // The negative control. No tags at all, so there is nothing for the selection to
            // resolve to and the readout must stay "selected-none". Without this the suite could
            // not demonstrate that it is able to observe a failure.
            Text("Untagged")
            List(selection: $untaggedSelection) {
                Text("untagged-one")
                Text("untagged-two")
            }
            .frame(height: 90)
            .accessibilityIdentifier("UntaggedList")

            Text(label(for: untaggedSelection))
                .accessibilityIdentifier("UntaggedSelection")
        }
        .padding()
        .frame(width: 360)
    }

    /// Rendered rather than asserted on the binding, because the binding is not reachable from a
    /// UI test. "none" is spelled out so the assertion cannot pass on an empty string.
    private func label(for selection: Int?) -> String {
        selection.map { "selected-\($0)" } ?? "selected-none"
    }
}
