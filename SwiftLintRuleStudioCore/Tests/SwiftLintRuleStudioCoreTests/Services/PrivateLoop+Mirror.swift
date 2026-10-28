//
//  PrivateLoop+Mirror.swift
//  SwiftLintRuleStudioCoreTests
//
//  The layouts where what decides a loop is what the mirror reproduces.
//

import Foundation

nonisolated extension PrivateLoop {
    /// What the mirror reproduces: it copies the config as written, so an exclusion keeps
    /// SwiftLint out there only when written relative and inside the folder the container
    /// stands for; and an `included` entry needs every link on the way to it.
    static let mirror: [Case] = [
        // SwiftLint skips G in the workspace, and the mirror's copy of the config names the
        // original G. No crash in the workspace; the mirror would go round for ever.
        Case(
            testDescription: "loop behind an absolute exclusion",
            config: "excluded:\n  - <base>/ws/Core/G\n",
            links: [link("ws/App/L4", to: "../Core"), link("ws/Core/G/L1", to: "../../App")],
            outcome: .refused(saying: nil)
        ),
        Case(
            testDescription: "loop behind an exclusion climbing past what the container stands for",
            workspace: "top/ws",
            config: "excluded:\n  - Generated\n  - ../../kit/G\n",
            links: [
                link("top/ws/App/L4", to: "../../../kit"),
                link("top/ws/Generated/L2", to: "../../../kit"),
                link("kit/G/L1", to: "../../top/ws/App")
            ],
            outcome: .refused(saying: nil)
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
