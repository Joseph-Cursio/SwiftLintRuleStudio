# SwiftLint Rule Studio

A native macOS application that puts a friendly graphical interface on top of the wonderful [SwiftLint](https://github.com/realm/SwiftLint) project. SwiftLint Rule Studio does **not** replace SwiftLint — it is simply a GUI front end that makes SwiftLint easier to explore, configure, and manage for individuals and teams.

**Platform:** macOS 13.0 (Ventura) or later
**License:** MIT
**Swift:** 6.0 with strict concurrency checking

---

## What It Does

SwiftLint's power comes with a learning curve: hundreds of rules, a hand-edited YAML config file, and no easy way to preview impact before enabling a rule. SwiftLint Rule Studio solves that by wrapping the CLI in a native SwiftUI application that lets you:

- **Browse rules** — Search and filter the full SwiftLint rule catalog with descriptions, examples, and rationale
- **Simulate impact** — See exactly how many violations a rule would add to your codebase *before* enabling it
- **Edit config safely** — Preview a YAML diff of every change, with automatic backups before any write
- **Inspect violations** — Browse violations grouped by file, rule, or severity, with one-click "Open in Xcode" navigation
- **Manage your workspace** — Persistent workspace bookmarks and incremental background analysis

### Key Features

| Feature | Description |
|---|---|
| Rule Browser | Searchable, filterable catalog of all SwiftLint rules with rich metadata |
| Rule Detail Panel | Full documentation, triggering/non-triggering examples, rationale, related rules, and Swift Evolution links |
| YAML Configuration Engine | Comment-preserving YAML editor with before/after diff preview and atomic writes |
| Impact Simulation | Run a dry-run to see violation counts before enabling any rule |
| Violation Inspector | Filter, group, and bulk-manage violations; export to CSV or JSON |
| Xcode Integration | Open any violation at the exact line in Xcode with a single click |
| Onboarding | Detects your SwiftLint installation and guides you through workspace setup |

---

## Requirements

- **macOS 13.0 (Ventura)** or later
- **SwiftLint** installed and available on your `$PATH` (see [SwiftLint installation](https://github.com/realm/SwiftLint#installation))
- Xcode 15 or later (to build from source)

SwiftLint Rule Studio calls the SwiftLint CLI under the hood. It works with any SwiftLint version that supports `swiftlint rules --format json`.

---

## Installation

### Build from Source

```bash
git clone https://github.com/yourusername/SwiftLintRuleStudio.git
cd SwiftLintRuleStudio
open SwiftLIntRuleStudio.xcodeproj
```

Build and run with **⌘R** in Xcode, or from the command line:

```bash
xcodebuild -scheme SwiftLIntRuleStudio -configuration Release build
```

---

## Running Tests

```bash
xcodebuild test -scheme SwiftLIntRuleStudio -destination 'platform=macOS'
```

The test suite uses the [Swift Testing](https://developer.apple.com/xcode/swift-testing/) framework (500+ tests).

---

## Project Structure

```
SwiftLintRuleStudio/
├── App/                     # Application entry point
├── Core/
│   ├── Models/              # Rule, Violation, Configuration models
│   ├── Services/            # RuleRegistry, WorkspaceAnalyzer, ViolationStorage, etc.
│   └── Utilities/
└── UI/
    ├── Components/          # Reusable SwiftUI components
    ├── ViewModels/          # MVVM view models
    └── Views/               # Feature views (RuleBrowser, ViolationInspector, etc.)
```

For a full architectural overview, see [CLAUDE.md](CLAUDE.md).

---

## Acknowledgements

### SwiftLint

This application is, at its core, a graphical wrapper around [SwiftLint](https://github.com/realm/SwiftLint) — one of the most valuable tools in the Swift ecosystem. All credit for the linting engine, rule definitions, and rule documentation belongs to the SwiftLint maintainers and contributors. Without SwiftLint, this application would not exist.

- **SwiftLint** — [realm/SwiftLint](https://github.com/realm/SwiftLint) — MIT License
  Created by JP Simard and the Realm team, maintained by the SwiftLint community

### Open Source Dependencies

**Runtime:**

- **[Yams](https://github.com/jpsim/Yams)** (v6.2.1) — A Swift YAML parser and serializer used for reading and writing `.swiftlint.yml` configuration files. MIT License.

**Testing:**

- **[ViewInspector](https://github.com/nalexn/ViewInspector)** (v0.10.3) — Runtime inspection of SwiftUI views in unit tests. MIT License.

---

## License

SwiftLint Rule Studio is released under the MIT License.

```
MIT License

Copyright (c) 2026 SwiftLint Rule Studio Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

*SwiftLint Rule Studio is not affiliated with or endorsed by the SwiftLint project, Realm, or MongoDB.*
