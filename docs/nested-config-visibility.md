# Nested `.swiftlint.yml` configs are invisible — and the GUI diverges from reality

## The hypothesis (confirmed, and worse than expected)

> "Individual folders can contain different YAML files… SwiftLint actually uses
> the folder-specific rules, but this GUI totally hides that this is happening."

**Correct.** SwiftLint supports **nested configurations**: a `.swiftlint.yml` in a
subdirectory is merged with its ancestors, and applies to files under that
directory. The classic use case is relaxing rules for tests — e.g. *"all tests
should be able to `try!`/force-unwrap freely"* (the Jon Reid pattern): a
`Tests/.swiftlint.yml` that disables `force_try` / `force_unwrapping` so you never
think about it in test code.

But it's worse than "hidden." The GUI runs SwiftLint with **`--config <root>`**,
and **`--config` disables nested configuration**. So the GUI doesn't just fail to
show nested configs — it produces results that **don't match what the developer
actually gets**.

### Empirical proof

A project with a root config (force_unwrapping on) and a nested
`Tests/.swiftlint.yml` (force_unwrapping off), with a force-unwrap in both
`Sources/` and `Tests/`:

```
A) `swiftlint lint`                       (no --config → what the dev / CI sees)
   Sources/Prod.swift  → force_unwrapping ⚠️
   Tests/Test.swift    → (clean — nested config disabled it)

B) `swiftlint lint --config .swiftlint.yml`   (what the GUI runs)
   Sources/Prod.swift  → force_unwrapping ⚠️
   Tests/Test.swift    → force_unwrapping ⚠️   ← FALSE POSITIVE
```

The GUI over-reports: it shows violations in `Tests/` that the developer never
sees, because it ignored the nested config that relaxes them.

## Where this lives in the code

- `SwiftLintCLIActor+Environment.buildLintArguments` builds
  `["lint", "--reporter", "json"]` and, when a config path exists, appends
  `["--config", configPath.path]` — forcing the single root config.
- `WorkspaceManager+Config` resolves the config as
  `workspace.path/.swiftlint.yml` — **only the root**. Nothing walks the tree
  for nested `.swiftlint.yml` files.
- Consequently the **config editor**, **impact simulation / RuleAudit**, and
  **config health analysis** all operate on the root config alone.

## Why it matters

1. **Wrong answers.** Impact simulation ("N files would change per rule") and the
   violation/health views are computed against root-only, so for any folder with a
   relaxing nested config the GUI **over-reports**. The headline promise —
   *"see exactly what SwiftLint will do to your code"* — is broken precisely where
   nested configs are used.
2. **Silent overrides in the editor.** A developer edits the root config in the
   GUI, saves, and is unaware that `Tests/.swiftlint.yml` (or `Sources/Legacy/…`)
   silently overrides their change for those files. The GUI gives no hint the
   nested file exists.
3. **Trust.** A tool that disagrees with the CLI/CI it wraps loses credibility
   fast — especially for the exact users sophisticated enough to use nested
   configs.

---

## Ideas to surface it

Ordered roughly cheapest/most-correctness-critical first.

### 1. Fix the execution so results match reality (correctness, not just UI)

The most important fix. Options:

- **Stop forcing `--config` for whole-project analysis.** Run `swiftlint lint`
  rooted at the workspace so SwiftLint applies nested configs the way the dev/CI
  does. (Keep `--config` only for explicit single-config previews.)
- Or offer **two explicit modes**, clearly labeled:
  - **"Effective (nested)"** — what SwiftLint actually does, nested configs
    applied. *Default.*
  - **"This config only"** — root config in isolation (today's behavior), for
    reasoning about one file.

Without this, every UI improvement below still shows numbers that don't match the
CLI.

### 2. Discover the config tree

Walk the workspace for **all** `.swiftlint.yml` files (excluding build dirs).
Build a tree: root + each nested config, with the rules each one adds/disables.

### 3. "Config Tree" view

A panel/sidebar showing the hierarchy:

```
.swiftlint.yml                (root — 42 rules)
├─ Tests/.swiftlint.yml       (disables 2: force_try, force_unwrapping)
├─ Sources/Legacy/.swiftlint.yml (disables 1: line_length)
└─ Generated/.swiftlint.yml   (excluded)
```

Each nested node badges *what it changes relative to its parent* and is
**clickable to edit** — so nested configs are first-class, not invisible. The
config editor should let you choose *which* `.swiftlint.yml` you're editing, not
silently assume root.

### 4. Per-folder / per-file "resolved config" inspector

Pick a folder (or file) → see the **effective merged config** that applies there
(root → ancestors → this folder), with each rule annotated by *which layer set
it*. This answers "what rules actually apply to my test files?" directly — and is
the within-repo analogue of the resolved-config inspector.

### 5. Override / drift warnings

When a nested config disables rules the root enables, surface it:
*"`Tests/` relaxes 2 rules from the project standard."* For a single dev this is
informational; it becomes a governance signal at team scale (see freemium note).

### 6. First-run awareness hint

When nested configs are detected on opening a workspace, a one-time note:
*"This project uses nested SwiftLint configs — linting differs by folder. View the
config tree."* So the feature is discoverable rather than buried.

---

## Impact on the freemium tiers (this revises `freemium-paid-tier-features.md`)

The freemium doc listed a **"resolved-config inspector (layering)"** under the
**paid** governance tier. That conflated two different kinds of layering:

- **Within-repo nested configs** (folder-level `.swiftlint.yml` in *one* repo) —
  this is an **individual** concern. Jon Reid relaxing his own tests is a solo
  developer on a single project. **This must be FREE.** It's not a premium
  feature; it's *baseline correctness*: the free tool currently gives wrong
  answers, and items #1–#4 above fix that.
- **Cross-repo / org config standards** (an org base config layered into many
  repos via `--config` chains, central standard, locked rules) — this is the
  **team** concern that stays **paid**.

### Concrete revision

| Capability | Tier |
|---|---|
| Execution respects nested configs (correctness fix) | **Free** |
| Config Tree view + edit any nested `.swiftlint.yml` | **Free** |
| Per-folder resolved-config inspector | **Free** |
| Within-repo override/drift hints | **Free** |
| Org standard library + locked rules + cross-repo layering | Paid |
| **Fleet nested-config audit** — "which folders in which repos relax the standard?" | **Paid** (new) |

So nested configs both **subtract** from and **add** to the paid plan:

- *Subtract:* the within-repo resolved-config view moves to free (it's
  correctness, and it's a single-dev feature).
- *Add (new paid idea):* once teams have a standard, **auditing nested-config
  drift across the fleet** — surfacing every folder, in every repo, that quietly
  weakens the org standard — is a genuinely team/compliance feature worth paying
  for. "Show me everywhere our standard is being relaxed" is a security/lead
  question, not an individual one.

## Recommendation

Treat #1 (execution respects nested configs) as a **correctness bug to fix in the
free tier**, then build the Config Tree (#2–#3) and resolved-config inspector (#4)
as free features. Fold the fleet-wide nested-config audit into the paid plan as a
new governance capability, and update `freemium-paid-tier-features.md` to split
"within-repo nesting (free)" from "cross-repo org layering (paid)."
