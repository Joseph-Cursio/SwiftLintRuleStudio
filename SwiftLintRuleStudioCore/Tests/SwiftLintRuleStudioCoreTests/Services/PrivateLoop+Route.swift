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
        // SwiftLint's first star stops at Pkg/, and **/ takes all it can, past the second Sources:
        // it doesn't match Generated, and goes round E for ever.
        Case(
            testDescription: "folder on the way a glob seems to exclude but SwiftLint doesn't, outside /private",
            config: "excluded:\n  - \"*/**/Sources/*/Generated\"\n",
            files: ["ws/Pkg/a.swift", "ws/Pkg/Sources/App/Sources/Generated/g.swift", "E/e.swift"],
            links: [
                link("ws/Pkg/Sources/App/Sources/Generated/Shared", to: "../../../../../../E"),
                link("E/back", to: "../E")
            ],
            underPrivate: false,
            outcome: .refused(saying: nil)
        ),
        // SwiftLint walks Mocks, follows M into F, and K back into Other/T, whose P it skips.
        Case(
            testDescription: "link reached past a folder only a looser glob would exclude, outside /private",
            config: "included:\n  - Src\nexcluded:\n  - \"*/**/Gen/*/Mocks\"\n  - Other/T/P\n",
            files: ["ws/Src/s.swift", "ws/Src/Gen/B/Gen/Mocks/m.swift", "ws/Other/T/t.swift", "F/f.swift"],
            links: [
                link("ws/Src/Gen/B/Gen/Mocks/M", to: "../../../../../../F"),
                link("ws/Other/T/P", to: "../../../F"),
                link("F/K", to: "../ws/Other/T")
            ],
            underPrivate: false,
            outcome: .keeps("F/K")
        ),
        // SwiftLint skips n, so walks lk only from the `included` entry through it, once.
        Case(
            testDescription: "link to its own folder an `included` entry runs through, behind an excluded link",
            config: "included:\n  - src\n  - ../out/N/lk/S\nexcluded:\n  - src/n\n",
            files: ["ws/src/Src.swift", "out/N/N.swift", "out/N/S/Kit.swift"],
            links: [link("ws/src/n", to: "../../out/N"), link("out/N/lk", to: ".")],
            underPrivate: false,
            outcome: .keeps("out/N/lk")
        ),
        // SwiftLint ignores case: its [^m] doesn't take the M of Mocks, so it follows Mocks into kit.
        Case(
            testDescription: "link on the way only a case-minding match would exclude, outside /private",
            config: "excluded:\n  - \"App/[!m]ocks\"\n",
            files: ["ws/App/a.swift", "kit/G/k.swift"],
            links: [link("ws/App/Mocks", to: "../../kit"), link("kit/G/L1", to: "../../ws/App")],
            underPrivate: false,
            outcome: .refused(saying: nil)
        ),
        // A CJK compatibility ideograph takes two UTF-16 units however it is spelled to SwiftLint.
        Case(
            testDescription: "excluded link on the way, under CJK compatibility ideographs, outside /private",
            workspace: "\u{2F800}\u{2F800}/ws",
            config: "excluded:\n  - App/L4\n",
            files: ["\u{2F800}\u{2F800}/kit/G/G.swift"],
            links: [
                link("\u{2F800}\u{2F800}/ws/App/L4", to: "../../kit"),
                link("\u{2F800}\u{2F800}/kit/G/L1", to: "../../ws/App")
            ],
            underPrivate: false,
            outcome: .refused(saying: "remove the link")
        ),
        // SwiftLint matches the link by a path whose accent it spells decomposed, and cuts it short.
        Case(
            testDescription: "loop excluded by its real path in a folder with an accented name, outside /private",
            workspace: "Développement/ws",
            config: "included:\n  - Sources\n  - A/Lnk/Sub\nexcluded:\n  - T/Sub/loop\n",
            files: ["Développement/ws/T/Sub/S.swift"],
            links: [link("Développement/ws/A/Lnk", to: "../T"), link("Développement/ws/T/Sub/loop", to: "..")],
            underPrivate: false,
            outcome: .refused(saying: "remove the link")
        ),
        Case(
            testDescription: "loop whose real path SwiftLint would read as a glob, outside /private",
            config: "included:\n  - Sources\n  - A/Lnk/Sub\nexcluded:\n  - Nope\n",
            files: ["ws/Vendor [old]/Sub/S.swift"],
            links: [link("ws/A/Lnk", to: "../Vendor [old]"), link("ws/Vendor [old]/Sub/loop", to: "..")],
            underPrivate: false,
            outcome: .refused(saying: "Add Vendor [[]old]/Sub/loop, the link's real path, to `excluded`")
        ),
        Case(
            testDescription: "the same, excluded as the reason says, outside /private",
            config: "included:\n  - Sources\n  - A/Lnk/Sub\nexcluded:\n  - \"Vendor [[]old]/Sub/loop\"\n",
            files: ["ws/Vendor [old]/Sub/S.swift"],
            links: [link("ws/A/Lnk", to: "../Vendor [old]"), link("ws/Vendor [old]/Sub/loop", to: "..")],
            underPrivate: false,
            outcome: .leftOut
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
