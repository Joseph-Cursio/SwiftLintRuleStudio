//
//  WorkspaceSelectionRemoveButtonTests.swift
//  SwiftLintRuleStudioTests
//
//  Accessibility regression for P1.3: the recent-workspace "Remove" control was a
//  Button nested inside the row's outer open-Button label — a structure VoiceOver
//  can't reliably reach. The openable region must no longer be a Button (its action
//  is a tap gesture / accessibility action), leaving Remove as a sibling Button.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct WorkspaceSelectionRemoveButtonTests {
    private func makeView(recentName: String) -> WorkspaceSelectionView {
        let workspaceManager = WorkspaceManager.createForTesting(testName: recentName)
        workspaceManager.recentWorkspaces = [
            Workspace(path: URL(fileURLWithPath: "/tmp/\(recentName)"))
        ]
        return WorkspaceSelectionView(workspaceManager: workspaceManager)
    }

    @Test("The openable row content is not nested inside a Button")
    func openContentIsNotAButton() throws {
        let view = makeView(recentName: "MyProjectXYZ")
        let buttons = try view.inspect().findAll(ViewType.Button.self)
        let nameInsideAButton = buttons.contains { button in
            (try? button.find(text: "MyProjectXYZ")) != nil
        }
        #expect(!nameInsideAButton, "the openable content must not be nested inside a Button")
    }

    // Disabled on macOS 27 beta (build 26A5388g): ViewInspector 0.10.3 cannot read
    // accessibility modifiers on this SwiftUI, so `accessibilityLabel()` never
    // matches and `removeReachable` is always false. The label is correct in the
    // view; only test-time introspection is broken. See the fuller note in
    // RuleParameterEditorTests.swift. The sibling test above is unaffected — it
    // searches by button structure and text, not by accessibility.
    @Test("The Remove control remains present as its own button",
          .disabled("ViewInspector 0.10.3 cannot read accessibility modifiers on macOS 27"))
    func removeControlPresent() throws {
        let view = makeView(recentName: "MyProjectXYZ")
        let matchesRemoveLabel: (InspectableView<ViewType.ClassifiedView>) throws -> Bool = { element in
            (try? element.accessibilityLabel().string()) == "Remove from recent workspaces"
        }
        let removeReachable = (try? view.inspect().find(where: matchesRemoveLabel)) != nil
        #expect(removeReachable, "the Remove control must be present and labeled")
    }
}
