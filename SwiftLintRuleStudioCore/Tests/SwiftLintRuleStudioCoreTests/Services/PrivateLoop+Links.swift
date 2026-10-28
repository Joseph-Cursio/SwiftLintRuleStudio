//
//  PrivateLoop+Links.swift
//  SwiftLintRuleStudioCoreTests
//
//  The layouts where SwiftLint goes through a link only on the way to what an `included` entry
//  names, and where an `included` entry beside the workspace is spelled through a link.
//

import Foundation

nonisolated extension PrivateLoop {
    /// Links SwiftLint goes through once, on the way to an entry it lints without walking what
    /// lies behind the link, the mirror keeps however they loop where SwiftLint doesn't go; and
    /// with `excluded` set, SwiftLint lists a folder spelled through a link by its real path, so the
    /// mirror recreates the link rather than copy the folder where the entry spells it.
    static let throughLinks: [Case] = [
        // SwiftLint lints F.swift where the entry names it, through L0 once. No crash.
        Case(
            testDescription: "`.swift` entry through a looping link",
            config: "included:\n  - Sources\n  - Lib/X/L0/X/F.swift\nexcluded:\n  - Nope\n",
            files: ["ws/Lib/X/F.swift"],
            links: [link("ws/Lib/X/L0", to: "..")],
            outcome: .keeps("ws/Lib/X/L0")
        ),
        Case(
            testDescription: "glob over `.swift` files through a looping link, outside /private",
            config: "included:\n  - Sources\n  - Lib/*/L0/X/F.swift\nexcluded:\n  - Nope\n",
            files: ["ws/Lib/X/F.swift"],
            links: [link("ws/Lib/X/L0", to: "..")],
            underPrivate: false,
            outcome: .keeps("ws/Lib/X/L0")
        ),
        // With nothing excluded SwiftLint lists X with `subpaths`, which goes into no link.
        Case(
            testDescription: "folder entry through a looping link, nothing excluded",
            config: "included:\n  - Sources\n  - Lib/X/L0/X\n",
            files: ["ws/Lib/X/F.swift"],
            links: [link("ws/Lib/X/L0", to: "..")],
            outcome: .keeps("ws/Lib/X/L0")
        ),
        // The App walk reaches Lib only through Gen, which it skips; the entry goes through L0.
        Case(
            testDescription: "`.swift` entry through a link a walk reaches only behind an excluded folder",
            config: "included:\n  - Sources\n  - App\n  - Lib/X/L0/X/F.swift\nexcluded:\n  - App/Gen\n",
            files: ["ws/Lib/X/F.swift", "ws/App/P.swift"],
            links: [link("ws/Lib/X/L0", to: ".."), link("ws/App/Gen/LL", to: "../../Lib")],
            outcome: .keeps("ws/Lib/X/L0")
        ),
        // The Lib walk goes round L0. Crashes.
        Case(
            testDescription: "`.swift` entry through a link a walk goes round",
            config: "included:\n  - Lib\n  - Lib/X/L0/X/F.swift\nexcluded:\n  - Nope\n",
            files: ["ws/Lib/X/F.swift"],
            links: [link("ws/Lib/X/L0", to: "..")],
            outcome: .refused(saying: nil)
        ),
        // SwiftLint lints h1.swift once, by its real path, whichever way it gets there.
        Case(
            testDescription: "`included` folder beside the workspace spelled through a link",
            config: "included:\n  - Sources\n  - ../link/Shared\nexcluded:\n  - Nope\n",
            files: ["real/Shared/h1.swift"],
            links: [link("link", to: "real"), link("ws/Sources/N", to: "../../real/Shared")],
            outcome: .keeps("link")
        ),
        Case(
            testDescription: "`included` folder beside the workspace spelled through a link, outside /private",
            config: "included:\n  - Sources\n  - ../link/Shared\nexcluded:\n  - Nope\n",
            files: ["real/Shared/h1.swift"],
            links: [link("link", to: "real"), link("ws/Sources/N", to: "../../real/Shared")],
            underPrivate: false,
            outcome: .keeps("link")
        ),
        // Listed by its real path, ws/Sub, which `excluded` names: SwiftLint lints nothing.
        Case(
            testDescription: "`included` folder spelled through a link back into the workspace",
            config: "included:\n  - ../kit/L/Sub\nexcluded:\n  - Sub\n",
            files: ["ws/Sub/S.swift"],
            links: [link("kit/L", to: "../ws")],
            outcome: .keeps("kit/L")
        ),
        // The exclusion, written through the link, never matches the real path: SwiftLint lints h2.
        Case(
            testDescription: "`included` folder spelled through a link to a folder further out, outside /private",
            workspace: "top/ws",
            config: "included:\n  - ../link/Shared\nexcluded:\n  - ../link/Shared/Sub\n",
            files: ["kit/Shared/h1.swift", "kit/Shared/Sub/h2.swift"],
            links: [link("top/link", to: "../kit")],
            underPrivate: false,
            outcome: .keeps("link")
        ),
        Case(
            testDescription: "`included` folder spelled through a link to a folder holding the workspace",
            config: "included:\n  - ../kit/Up/ws/Sources\nexcluded:\n  - Nope\n",
            links: [link("kit/Up", to: "..")],
            outcome: .refused(saying: "which holds the workspace")
        )
    ]
}
