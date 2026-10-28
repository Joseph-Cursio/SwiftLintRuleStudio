//
//  PrivateLoop.swift
//  SwiftLintRuleStudioCoreTests
//
//  The layouts SimulationWorkspacePrivateLoopTests checks, each with what `swiftlint lint`
//  0.65.1 makes of it.
//

import Foundation
import Testing

/// The layouts ``SimulationWorkspacePrivateLoopTests`` checks.
nonisolated enum PrivateLoop {
    enum Outcome: Sendable {
        /// SwiftLint never gets into the loop: the mirror leaves the link out.
        case leftOut
        /// SwiftLint crashes on it, or goes round once and lints what the mirror wouldn't: the
        /// simulation refuses it, and the reason says `saying` when given.
        case refused(saying: String?)
        /// SwiftLint follows this link, from the container, without coming back round: the
        /// mirror keeps it.
        case keeps(String)
    }

    /// A link, by its path from the base folder, and where it points.
    struct Link: Sendable {
        let path: String
        let destination: String
    }

    /// A layout and what `swiftlint lint` 0.65.1 makes of it in /tmp. Where the order folders
    /// are listed in matters, a layout comes in both orders.
    struct Case: Sendable, CustomTestStringConvertible {
        let testDescription: String
        var workspace = "ws"
        /// `<base>` stands for the base folder's path.
        let config: String
        var files: [String] = []
        let links: [Link]
        /// Planned as for a workspace outside /private when false.
        var underPrivate = true
        let outcome: Outcome
    }

    static func link(_ path: String, to destination: String) -> Link {
        Link(path: path, destination: destination)
    }

    /// SwiftLint matches each entry of a folder it lists by its real path, which keeps /private
    /// as the patterns do: an excluded folder on the way keeps it from a loop. No crash.
    static let keptOut: [Case] = [
        Case(
            testDescription: "folder that holds it",
            config: "excluded:\n  - Sources\n",
            links: [link("ws/Sources/loop", to: "..")],
            outcome: .leftOut
        ),
        Case(
            testDescription: "folder a glob names",
            config: "excluded:\n  - \"Sour*\"\n",
            links: [link("ws/Sources/loop", to: "..")],
            outcome: .leftOut
        ),
        Case(
            testDescription: "deeper folder that holds it",
            config: "excluded:\n  - Sources/Deep\n",
            links: [link("ws/Sources/Deep/loop", to: "../..")],
            outcome: .leftOut
        ),
        Case(
            testDescription: "folder below where an `included` walk starts",
            config: "included:\n  - Sources\nexcluded:\n  - Sources/Gen\n",
            links: [link("ws/Sources/Gen/loop", to: "../..")],
            outcome: .leftOut
        ),
        Case(
            testDescription: "folder before the link that leads to it",
            config: "excluded:\n  - Sources\n",
            links: [link("ws/Sources/Libs", to: "../../kit"), link("kit/loop", to: ".")],
            outcome: .leftOut
        ),
        Case(
            testDescription: "folder inside a link's target, by its real path",
            config: "excluded:\n  - ../kit/Vendor\n",
            links: [link("ws/Libs", to: "../kit"), link("kit/Vendor/loop", to: "..")],
            outcome: .leftOut
        )
    ]

    /// What no exclusion keeps SwiftLint out of: the link itself, and the folder a link leads
    /// into, it matches with /private dropped; the folder a walk starts from, never. It crashes,
    /// except on the last, where it goes round once linting what the mirror, leaving the link
    /// out, wouldn't.
    static let notKeptOut: [Case] = [
        Case(
            testDescription: "link at the top",
            config: "excluded:\n  - loop\n",
            links: [link("ws/loop", to: ".")],
            outcome: .refused(saying: "doesn't skip a symlink `excluded` names: remove the link.")
        ),
        Case(
            testDescription: "excluded folder a link leads into, listed before the link",
            config: "excluded:\n  - Abc\n",
            links: [link("ws/Abc/loop", to: ".."), link("ws/Zlnk", to: "Abc")],
            outcome: .refused(saying: ": remove the link.")
        ),
        Case(
            testDescription: "excluded folder a link leads into, listed after the link",
            config: "excluded:\n  - Shared\n",
            links: [link("ws/Shared/loop", to: ".."), link("ws/Libs", to: "Shared")],
            outcome: .refused(saying: ": remove the link.")
        ),
        Case(
            testDescription: "excluded folder an `included` walk starts from",
            config: "included:\n  - Sources\nexcluded:\n  - Sources\n",
            links: [link("ws/Sources/loop", to: "..")],
            outcome: .refused(saying: ": remove the link.")
        )
    ]

    /// Which folder the reason says to exclude: the deepest on the way that, named in
    /// `excluded` as SwiftLint sees it from the workspace, it would skip. No exclusion; crashes.
    static let advice: [Case] = [
        Case(
            testDescription: "the folder that holds it",
            config: "excluded:\n  - Nope\n",
            links: [link("ws/Sources/Deep/loop", to: "../..")],
            outcome: .refused(saying: "exclude Sources/Deep, the folder that holds it, or remove the link.")
        ),
        Case(
            testDescription: "a folder before the link that leads to it",
            config: "excluded:\n  - Nope\n",
            links: [link("ws/Sources/Libs", to: "../../kit"), link("kit/loop", to: ".")],
            outcome: .refused(saying: "exclude Sources, a folder on the way to it, or remove the link.")
        ),
        Case(
            testDescription: "none behind a link, listed by its real path",
            config: "excluded:\n  - Nope\n",
            links: [link("ws/Libs", to: "../kit"), link("kit/Vendor/loop", to: "..")],
            outcome: .refused(saying: ": remove the link.")
        ),
        Case(
            testDescription: "none a glob would name",
            config: "excluded:\n  - \"Gen[1]\"\n",
            links: [link("ws/Gen[1]/loop", to: "..")],
            outcome: .refused(saying: ": remove the link.")
        )
    ]

    /// Beyond the folders on one route: where `included` walks start, every route SwiftLint
    /// takes to a folder, and the real paths it lists.
    static let routes: [Case] = [
        // A walk that starts inside an excluded folder isn't kept out by it, whichever way to
        // that folder is walked first. Crashes.
        Case(
            testDescription: "walk start inside an excluded folder, other way in listed first",
            config: "included:\n  - Sources\n  - Sources/Gen/Deep\nexcluded:\n  - Sources/Gen\n",
            links: [link("ws/Sources/Gen/Deep/loop", to: "."), link("ws/Docs/Sources", to: "../Sources")],
            outcome: .refused(saying: nil)
        ),
        Case(
            testDescription: "walk start inside an excluded folder, other way in listed last",
            config: "included:\n  - Sources\n  - Sources/Gen/Deep\nexcluded:\n  - Sources/Gen\n",
            links: [link("ws/Sources/Gen/Deep/loop", to: "."), link("ws/Zzz/Sources", to: "../Sources")],
            outcome: .refused(saying: nil)
        ),
        Case(
            testDescription: "walk start at an excluded folder's other way in",
            config: "included:\n  - Sources\n  - Vendor\n  - Vendor/Src/Gen\nexcluded:\n  - Sources/Gen\n",
            links: [link("ws/Sources/Gen/loop", to: "."), link("ws/Vendor/Src", to: "../Sources")],
            outcome: .refused(saying: nil)
        ),
        Case(
            testDescription: "walk start below a folder first reached through an excluded one",
            config: "included:\n  - Core\n  - Plugins/Sub\nexcluded:\n  - Core/Gen\n",
            links: [link("ws/Core/Gen/up", to: "../../Plugins"), link("ws/Plugins/Sub/gen", to: "../../Core/Gen")],
            outcome: .refused(saying: nil)
        ),
        Case(
            testDescription: "walk start below a folder first reached directly",
            config: "included:\n  - App2\n  - Tools/Sub\nexcluded:\n  - App2/Gen\n",
            links: [link("ws/App2/Gen/up", to: "../../Tools"), link("ws/Tools/Sub/gen", to: "../../App2/Gen")],
            outcome: .refused(saying: nil)
        ),
        // SwiftLint lists an `included` folder beside the workspace by its real path. Crashes.
        Case(
            testDescription: "exclusion written through a link to a folder beside the workspace",
            config: "included:\n  - Sources\n  - ../link/Shared\nexcluded:\n  - ../link/Shared/Gen\n",
            links: [link("real/Shared/Gen/loop", to: "."), link("link", to: "real")],
            outcome: .refused(saying: nil)
        ),
        // Its matcher measures the path in characters against UTF-16: an emoji cuts it short.
        // Crashes.
        Case(
            testDescription: "excluded folder in a workspace named with an emoji",
            workspace: "ws😀",
            config: "excluded:\n  - Sources\n",
            links: [link("ws😀/Sources/loop", to: "..")],
            outcome: .refused(saying: nil)
        ),
        // A link that loops only on a route SwiftLint doesn't walk or is kept off, and leads
        // on elsewhere, is one it follows there: no crash, and it lints what lies behind.
        Case(
            testDescription: "link looping only behind an excluded folder listed first",
            config: "excluded:\n  - Generated\n  - ../kit/G\n",
            links: [
                link("ws/App/L4", to: "../../kit"),
                link("ws/Generated/L2", to: "../../kit"),
                link("kit/G/L1", to: "../../ws/App")
            ],
            outcome: .keeps("ws/App/L4")
        ),
        Case(
            testDescription: "link looping only behind an excluded folder listed last",
            config: "excluded:\n  - Gen\n  - ../kit/G\n",
            links: [
                link("ws/App/L4", to: "../../kit"),
                link("ws/Gen/L2", to: "../../kit"),
                link("kit/G/L1", to: "../../ws/App")
            ],
            outcome: .keeps("ws/App/L4")
        ),
        Case(
            testDescription: "link looping only on a route SwiftLint never walks",
            config: "included:\n  - Sources\nexcluded:\n  - ../kit/Sub\n",
            links: [
                link("ws/Sources/F/L", to: "../../../kit"),
                link("kit/Sub/M", to: "../../ws/Sources/F"),
                link("ws/Other/H", to: "../../kit/Sub")
            ],
            outcome: .keeps("ws/Sources/F/L")
        )
    ]
}
