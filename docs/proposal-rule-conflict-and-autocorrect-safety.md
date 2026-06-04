# Proposal: rule-conflict detection & autocorrect-safety advisories

Two complementary features that surface config problems SwiftLint itself stays
silent about. Both are motivated by concrete pain hit while bringing
SwiftFormatRuleStudio onto a strict (~130-rule) config — see that repo's
`docs/swiftlint-autofix-*.md` and `swiftlint-rules-that-cannot-be-satisfied.md`.

The design goal is to **fit the existing architecture** rather than add new
plumbing: both features slot into surfaces the app already has and already
renders.

## What already exists (and why it's a clean fit)

| Surface | Type | Renders in | Today |
|---|---|---|---|
| `ConfigurationValidator` | `ValidationResult` (errors + warnings, keyed by `ConfigField`) | validation views | Detects structural problems, incl. *the same rule in both `disabled_rules` and `opt_in_rules`* |
| `ConfigurationHealthAnalyzer` | `ConfigHealthReport` (score, grade, prioritized `HealthRecommendation`s) | `ConfigHealthScoreView` | Scores config quality; `generateRecommendations` appends advisory items |

The `Rule` model already carries `supportsAutocorrection: Bool`, so "is this rule
correctable" is derivable. Both features therefore add **Core logic + a curated
table + tests**, with **near-zero new UI** (the views already render warnings and
recommendations).

---

## Feature 1 — Contradictory-rule-pair detection → `ConfigurationValidator`

### Problem

Some SwiftLint rules are **mutually exclusive**: no source file can satisfy both,
so enabling the pair guarantees perpetual violations no matter how the code is
written. SwiftLint reports the violations but never says *why* — that the two
rules fundamentally fight. We hit exactly this with
`extension_access_modifier` ⇄ `no_extension_access_modifier`.

### Design

A curated `RuleConflicts` table of known mutually-exclusive pairs. Extend the
validator's existing conflict check (currently same-rule-in-both-lists) to also
flag enabled pairs, emitting a `ValidationWarning`:

> *"`extension_access_modifier` and `no_extension_access_modifier` contradict each
> other — no code can satisfy both. Disable one."*

Keyed by `ConfigField.rule(...)` so the UI can point at the offending entries,
and ideally offering a "disable one" affordance (mirrors the existing
`ActionType.disableRule`).

### Seed table (defensible, well-established pairs)

| Rule A | Rule B | Why they conflict |
|---|---|---|
| `extension_access_modifier` | `no_extension_access_modifier` | One wants the modifier *on* the extension; the other wants it *off* (on each member). |
| `explicit_type_interface` | `redundant_type_annotation` | One mandates explicit type annotations; the other removes them when redundant. |
| `prefer_nimble` | `xct_specific_matcher` | One pushes Nimble matchers; the other pushes XCTest matchers. |

Start conservative — every entry must be a *true* contradiction (not a stylistic
preference), so the warning is always trustworthy.

---

## Feature 2 — Autocorrect-safety advisory → `ConfigurationHealthAnalyzer`

### Problem

`swiftlint --fix` is not guaranteed to be semantics-preserving. Some correctable
rules' autocorrect can **break the build or silently change behavior**:

- `async_without_await` / `unneeded_throws_rethrows` strip `async`/`throws` from a
  function based on its body alone — breaking protocol-witness / override
  conformance.
- `trailing_closure` drops an argument label, which under SE-0286 forward-scan
  matching **rebinds the closure to a different parameter** (a compile error in
  the lucky case, a silent behavior change otherwise).

A user who enables these and runs `--fix` in CI can get a broken or
subtly-wrong tree. The config is still *valid*, so this is advisory, not an error.

### Design

A curated `AutocorrectSafety` table of correctable rules whose autocorrect is
known-risky. When `analyze()` sees any enabled, `generateRecommendations` appends
a low/medium `HealthRecommendation`:

> *"3 enabled rules have unsafe autocorrect (`async_without_await`,
> `unneeded_throws_rethrows`, `trailing_closure`). Review changes before running
> `swiftlint --fix` — these can change semantics."*

`ActionType.general` (or a new `.reviewAutocorrect`), priority `.low`/`.medium`.
Purely informational — it never suggests disabling a useful rule.

### Seed list (from the autofix analysis docs)

- `async_without_await`
- `unneeded_throws_rethrows`
- `trailing_closure`

---

## Why the split (validator vs. analyzer)

A **contradiction is a real misconfiguration** → it belongs with errors/warnings
(`ConfigurationValidator`). **Unsafe autocorrect leaves a valid config** → it's
advice (`ConfigurationHealthAnalyzer`). This mirrors how the app already
separates "your config is wrong" from "your config could be better."

## Maintainability

Both tables are **curated** and will drift across SwiftLint versions (rules get
renamed, removed, or change behavior). To keep them honest:

- **Validate every table entry against the app's known-rules catalog in a unit
  test.** A renamed/removed rule then fails the test loudly instead of the table
  rotting into silent no-ops.
- Keep entries **conservative**: only true contradictions in Feature 1, only
  demonstrably-unsafe autocorrects in Feature 2. A false warning erodes trust in
  every warning.

## Scope & sequencing

| Step | Where | Test |
|---|---|---|
| `RuleConflicts` table + catalog-validation test | Core | ✅ pure |
| Validator: flag enabled conflicting pairs → `ValidationWarning` | Core | ✅ |
| `AutocorrectSafety` table + catalog-validation test | Core | ✅ pure |
| Analyzer: append "review before --fix" recommendation | Core | ✅ |
| UI polish (read-well copy; optional "disable one" action) | UI | ViewInspector |

~4 focused Core commits + a small UI pass. The UI is largely free because
`ConfigHealthScoreView` and the validation views already render these types.

## Recommendation

Build **both** — they share the "curated table validated against the catalog"
pattern and together productize the SwiftFormatRuleStudio lessons. If starting
smaller, **Feature 1 (contradictions)** is higher-value and lower-subjectivity:
a contradiction is objective, whereas "unsafe autocorrect" is a curated judgment.
