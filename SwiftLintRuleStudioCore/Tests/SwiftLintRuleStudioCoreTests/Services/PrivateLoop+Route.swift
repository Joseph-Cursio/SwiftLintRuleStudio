//
//  PrivateLoop+Route.swift
//  SwiftLintRuleStudioCoreTests
//
//  Outside /private, the exclusions on the way to a loop that keep SwiftLint out of it.
//

import Foundation

nonisolated extension PrivateLoop {
    /// Outside /private SwiftLint matches every entry it lists by its real path: a folder, a link,
    /// and where a link leads. So an excluded folder or link on the way keeps it out of a loop
    /// beyond, as the link and its target do; and a link it reaches below a walk start spelled
    /// through another it matches by its real path, not where it sees it.
    static let routeOutsidePrivate: [Case] = [
        // The Core walk skips G; the App walk comes through L4 into Core again, and skips G.
        Case(
            testDescription: "excluded folder on the way to a loop, outside /private",
            config: "excluded:\n  - Core/G\n",
            files: ["ws/Core/C.swift", "ws/Core/G/G.swift"],
            links: [link("ws/App/L4", to: "../Core"), link("ws/Core/G/L1", to: "../../App")],
            underPrivate: false,
            outcome: .keeps("ws/App/L4")
        ),
        // kit is reached only through L4, which SwiftLint skips.
        Case(
            testDescription: "excluded link on the only way to a loop beside the workspace, outside /private",
            config: "excluded:\n  - App/L4\n",
            files: ["kit/G/G.swift"],
            links: [link("ws/App/L4", to: "../../kit"), link("kit/G/L1", to: "../../ws/App")],
            underPrivate: false,
            outcome: .keeps("ws/App/L4")
        ),
        Case(
            testDescription: "the same with nothing excluded on the way, outside /private",
            config: "excluded:\n  - Nope\n",
            files: ["kit/G/G.swift"],
            links: [link("ws/App/L4", to: "../../kit"), link("kit/G/L1", to: "../../ws/App")],
            underPrivate: false,
            outcome: .refused(saying: "Add ../kit/G/L1, the link's real path, to `excluded`")
        ),
        // The App walk reaches Lib only through Gen, which it skips; the entry goes through L0.
        Case(
            testDescription: "`.swift` entry through a link reached only behind an excluded folder, outside /private",
            config: "included:\n  - Sources\n  - App\n  - Lib/X/L0/X/F.swift\nexcluded:\n  - App/Gen\n",
            files: ["ws/Lib/X/F.swift", "ws/App/P.swift"],
            links: [link("ws/Lib/X/L0", to: ".."), link("ws/App/Gen/LL", to: "../../Lib")],
            underPrivate: false,
            outcome: .keeps("ws/Lib/X/L0")
        ),
        // SwiftLint may not match a path holding a character that takes two UTF-16 units.
        Case(
            testDescription: "excluded folder on the way to a loop, named with an emoji, outside /private",
            config: "excluded:\n  - \"Core/G😀\"\n",
            files: ["ws/Core/C.swift", "ws/Core/G😀/G.swift"],
            links: [link("ws/App/L4", to: "../Core"), link("ws/Core/G😀/L1", to: "../../App")],
            underPrivate: false,
            outcome: .refused(saying: nil)
        ),
        // The walk starts at A/Lnk/Sub, which SwiftLint reads by its real path, T/Sub. Crashes.
        Case(
            testDescription: "loop below a walk start spelled through a link, excluded as spelled, outside /private",
            config: "included:\n  - Sources\n  - A/Lnk/Sub\nexcluded:\n  - A/Lnk/Sub/loop\n",
            files: ["ws/T/Sub/S.swift"],
            links: [link("ws/A/Lnk", to: "../T"), link("ws/T/Sub/loop", to: "..")],
            underPrivate: false,
            outcome: .refused(saying: "Add T/Sub/loop, the link's real path, to `excluded`")
        ),
        Case(
            testDescription: "folder below a walk start spelled through a link, excluded as spelled, outside /private",
            config: "included:\n  - Sources\n  - A/Lnk/Sub\nexcluded:\n  - A/Lnk/Sub/G\n",
            files: ["ws/T/Sub/G/S.swift"],
            links: [link("ws/A/Lnk", to: "../T"), link("ws/T/Sub/G/loop", to: "../..")],
            underPrivate: false,
            outcome: .refused(saying: nil)
        ),
        Case(
            testDescription: "folder below a walk start through a link, excluded by its real path, outside /private",
            config: "included:\n  - Sources\n  - A/Lnk/Sub\nexcluded:\n  - T/Sub/G\n",
            files: ["ws/T/Sub/G/S.swift"],
            links: [link("ws/A/Lnk", to: "../T"), link("ws/T/Sub/G/loop", to: "../..")],
            underPrivate: false,
            outcome: .leftOut
        )
    ]
}
