//
//  PrivateLoop+Mirror.swift
//  SwiftLintRuleStudioCoreTests
//
//  The layouts where what decides a loop is what the mirror reproduces.
//

import Foundation

nonisolated extension PrivateLoop {
    /// What the mirror reproduces: it writes each `excluded` entry to name its place in the
    /// container, so one written absolute, or climbing past the folder the container stands for,
    /// keeps SwiftLint out there as in the workspace; and an `included` entry needs every link on
    /// the way to it.
    static let mirror: [Case] = [
        // SwiftLint skips G in the workspace, and the mirror writes the entry to name its copy of
        // G, so it skips that too. No crash in either.
        Case(
            testDescription: "loop behind an absolute exclusion",
            config: "excluded:\n  - <base>/ws/Core/G\n",
            links: [link("ws/App/L4", to: "../Core"), link("ws/Core/G/L1", to: "../../App")],
            outcome: .keeps("ws/App/L4")
        ),
        // The same in kit, beside the folder the container stands for: the mirror writes the entry
        // to name G in its outside copy of kit.
        Case(
            testDescription: "loop behind an exclusion climbing past what the container stands for",
            workspace: "top/ws",
            config: "excluded:\n  - Generated\n  - ../../kit/G\n",
            links: [
                link("top/ws/App/L4", to: "../../../kit"),
                link("top/ws/Generated/L2", to: "../../../kit"),
                link("kit/G/L1", to: "../../top/ws/App")
            ],
            outcome: .keeps(".swiftlint-rule-studio-outside/0/tree/G/L1")
        ),
        // SwiftLint lints through M for T/Sub/M/Z, and only the absolute entry keeps it from
        // coming back round through M on its walk of A. The mirror keeps M, and with the entry
        // written to name its copy, skips it there too.
        Case(
            testDescription: "followed link looping where only an absolute exclusion stops it, outside /private",
            config: "included:\n  - A\n  - T/Sub/M/Z\nexcluded:\n  - <base>/ws/T/Sub/M\n",
            files: ["ws/A/a2.swift", "ws/A/Z/a1.swift", "ws/T/Sub/t1.swift"],
            links: [link("ws/A/L", to: "../T"), link("ws/T/Sub/M", to: "../../A")],
            underPrivate: false,
            outcome: .keeps("ws/T/Sub/M")
        ),
        Case(
            testDescription: "followed link looping where only a climbing exclusion stops it, outside /private",
            workspace: "top/ws",
            config: "included:\n  - A/Lnk/Sub\n  - C/toA/Z\nexcluded:\n  - ../../top/ws/T\n",
            files: ["top/ws/A/a2.swift", "top/ws/A/Z/a1.swift", "top/ws/T/Sub/t1.swift"],
            links: [
                link("top/ws/A/Lnk", to: "../T"), link("top/ws/T/Sub/toA", to: "../../A"), link("top/ws/C", to: "T/Sub")
            ],
            underPrivate: false,
            outcome: .keeps("ws/T/Sub/toA")
        ),
        // Packages/Kit is on the way to an `included` entry, so the mirror keeps it; the Modules
        // walk reaches it again through Siblings, and only the absolute entry stops SwiftLint
        // there, in the mirror as in the workspace.
        Case(
            testDescription: "link toward an `included` entry looping behind an absolute exclusion, outside /private",
            config: "included:\n  - Packages/Kit/Sources\n  - Modules\nexcluded:\n  - <base>/ws/Packages/Kit\n",
            files: ["ws/Modules/Kit/Sources/Kit.swift"],
            links: [
                link("ws/Packages/Kit", to: "../Modules/Kit"),
                link("ws/Modules/Kit/Siblings", to: "../../Packages")
            ],
            underPrivate: false,
            outcome: .keeps("ws/Packages/Kit")
        ),
        Case(
            testDescription: "the same behind an exclusion climbing past the anchor, outside /private",
            workspace: "top/ws",
            config: "included:\n  - Packages/Kit/Sources\n  - Modules\nexcluded:\n  - ../../top/ws/Packages/Kit\n",
            files: ["top/ws/Modules/Kit/Sources/Kit.swift"],
            links: [
                link("top/ws/Packages/Kit", to: "../Modules/Kit"),
                link("top/ws/Modules/Kit/Siblings", to: "../../Packages")
            ],
            underPrivate: false,
            outcome: .keeps("ws/Packages/Kit")
        ),
        // APFS lists Packages before Modules, and Vendor after: there the loop is seen before
        // the link is followed.
        Case(
            testDescription: "the same with the looping folder listed last, outside /private",
            config: "included:\n  - Vendor/Kit/Sources\n  - Modules\nexcluded:\n  - <base>/ws/Vendor/Kit\n",
            files: ["ws/Modules/Kit/Sources/Kit.swift"],
            links: [
                link("ws/Vendor/Kit", to: "../Modules/Kit"),
                link("ws/Modules/Kit/Siblings", to: "../../Vendor")
            ],
            underPrivate: false,
            outcome: .keeps("ws/Vendor/Kit")
        ),
        // The same written relative.
        Case(
            testDescription: "followed link looping where a relative exclusion stops it, outside /private",
            config: "included:\n  - A/Lnk/Sub\n  - C/toA/Z\nexcluded:\n  - T\n",
            files: ["ws/A/a2.swift", "ws/A/Z/a1.swift", "ws/T/Sub/t1.swift"],
            links: [link("ws/A/Lnk", to: "../T"), link("ws/T/Sub/toA", to: "../../A"), link("ws/C", to: "T/Sub")],
            underPrivate: false,
            outcome: .keeps("ws/T/Sub/toA")
        ),
        // Only the absolute entry keeps SwiftLint out, and nothing else follows the link: the
        // mirror leaving it out lints what SwiftLint does.
        Case(
            testDescription: "loop only an absolute exclusion stops, outside /private",
            config: "excluded:\n  - <base>/ws/Sources/loop\n",
            links: [link("ws/Sources/loop", to: "..")],
            underPrivate: false,
            outcome: .leftOut
        ),
        // SwiftLint starts the walk in the folder the link points at, and comes round. Crashes.
        Case(
            testDescription: "`included` entry running through a loop",
            config: "included:\n  - Lib/X/L0/X\nexcluded:\n  - Nope\n",
            files: ["ws/Lib/X/X.swift"],
            links: [link("ws/Lib/X/L0", to: "..")],
            outcome: .refused(saying: nil)
        ),
        Case(
            testDescription: "loop below a walk start, outside /private",
            config: "included:\n  - Docs/Sub\n  - Gen/Sub\nexcluded:\n  - Nope\n",
            files: ["ws/Docs/Sub/S.swift"],
            links: [link("ws/Docs/L", to: "../Gen"), link("ws/Gen/Sub/loop", to: "..")],
            underPrivate: false,
            outcome: .refused(saying: nil)
        ),
        // A link on the way to an `included` entry, looping only on a route SwiftLint never
        // walks: it lints Kit.swift through it. No crash.
        Case(
            testDescription: "link on the way to an `included` entry",
            config: "included:\n  - Sources\n  - Packages/Kit/Sources\nexcluded:\n  - Nope\n",
            files: ["ws/Modules/Kit/Sources/Kit.swift"],
            links: [
                link("ws/Packages/Kit", to: "../Modules/Kit"),
                link("ws/Modules/Kit/Siblings", to: "../../Packages")
            ],
            outcome: .keeps("ws/Packages/Kit")
        ),
        Case(
            testDescription: "link on the way to an `included` entry, outside /private",
            config: "included:\n  - Sources\n  - Packages/Kit/Sources\nexcluded:\n  - Nope\n",
            files: ["ws/Modules/Kit/Sources/Kit.swift"],
            links: [
                link("ws/Packages/Kit", to: "../Modules/Kit"),
                link("ws/Modules/Kit/Siblings", to: "../../Packages")
            ],
            underPrivate: false,
            outcome: .keeps("ws/Packages/Kit")
        ),
        // A link SwiftLint follows on a walked route, and that loops only on one it doesn't
        // walk: it lints Z.swift through it. No crash.
        Case(
            testDescription: "link followed on a walked route, outside /private",
            config: "included:\n  - App\n  - Docs/Sub\n  - Gen/Sub\nexcluded:\n  - Gen/LZ\n",
            files: [
                "ws/App/A2.swift", "ws/Docs/D.swift", "ws/Docs/Sub/S.swift", "ws/Gen/Z.swift", "ws/Gen/Sub/Q.swift"
            ],
            links: [
                link("ws/App/LD", to: "../Docs"),
                link("ws/Docs/L", to: "../Gen"),
                link("ws/Gen/LZ", to: "../Docs")
            ],
            underPrivate: false,
            outcome: .keeps("ws/Docs/L")
        )
    ]
}
