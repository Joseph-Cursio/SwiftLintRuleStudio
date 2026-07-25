# Property-Based Test Candidates — SwiftLintRuleStudioCore

_An exploration of the property laws the Core kernels invite, grounded in the
actual code (not the seed manifest's guesses). Each entry gives the real
signature, the honest law(s), a generator sketch in the repo's toolchain, the
gotchas that make it interesting, and a testable-today verdict._

Toolchain: `swift-property-based` (`propertyCheck(input:)` + `Gen`/`Generator`)
and `PropertyLawKit`. Pipeline (pbt-book Appendix C): `SwiftProjectLint` →
`swift-infer discover` → `SwiftPropertyLaws` → `SwiftIdempotency`.

**Status: 5 of 8 closed.** §2, §3, §4, §5 and §8 are shipped; §1, §6 and §7
remain, each blocked on something specific and named below. The suite is
**29 property-law tests across 6 suites** (`swift test --filter PropertyLaw`).

---

## Already shipped

| § | Subject | Suite | Commit |
|---|---|---|---|
| — | `AnyCodable` / `RuleParameter` Hashable + Codable laws | `Models/RuleValueTypePropertyLawTests` | `582c0b9` |
| — | `deindent`, `mergedWith`, `levenshteinDistance`, `isVersion` | `Services/KernelPropertyLawTests` | `cf7036c` |
| 2 | `filterViolations` subset / membership / idempotence | `Services/FilterViolationsPropertyLawTests` | `aeb701a` |
| 4 | `layerChain` ancestry / from-tree / depth order | `Services/LayerChainPropertyLawTests` | `c739ae9` |
| 3 | `generateDiff` disjointness / set algebra / swap | `Services/DiffCharacterizationPropertyLawTests` | `3d58747` |
| 8 | the union under `mergedWith` — associativity + section | `Services/KernelPropertyLawTests` | `5e1e9b3` |
| 5 | `resolve` mutual exclusion / deeper-wins / root-only | `Services/ResolveInvariantPropertyLawTests` | `c6f70d0` |

**Two production bugs came out of writing these**, neither of which any
algebraic law over the function would have surfaced on its own:

- **§5 found a real defect.** A single `.swiftlint.yml` listing a rule in both
  `disabled_rules` and `opt_in_rules` landed it in *both* resolved sets. Fixed in
  `c6f70d0` to match SwiftLint (see §5).
- **§8 found doc-vs-code drift.** `mergedWith`'s docstring promised "a
  deduplicated list"; it is not one. Docs corrected in `601a703` (see §8).

### What the toolchain contributed, and what it didn't

Three of the shipped laws were **proposed by `swift-infer`** — `filter-subset`
on `filterViolations`, `selection-subset` on `layerChain`, `diff-disjointness`
on `generateDiff` — and all three templates were added upstream *because* this
package was pointed at. In every case the hand-written suite states something
**stronger** than the proposal: the tool named disjointness, §3 states the set
algebra.

Equally worth recording, from a full pipeline re-run (`swiftprojectlint`
`23c0133` / `swift-infer` `1ea657c`):

- The seed manifest measures **90 seeds** (67 pure-function, 23
  extractable-kernel). `serialize` is **not** among them — see §1.
- `.swiftinfer/vocabulary.json` registers a `Node` generator (`783f456`). It is
  **inert**: `discover` reports identical output with it present, absent, or
  passed via `--vocabulary`, because neither `YAMLConfig` nor `ConfigDiff` is
  ever scaffolded. Kept because it costs nothing and starts paying if that
  changes upstream.
- `filterViolations`, `layerChain` and `generateDiff` are seeded only as
  `extractable-kernel`, a kind the focus filter treats as unfocusable — they
  survive a seeded run solely because of `swift-infer`'s
  refutability-decides-visibility rule.
- Neither bug above was findable by template. The tools help where
  value-semantic structure is present and fall silent where it is not.

**Every shipped suite is mutation-verified**, not merely green. Each entry below
records the mutant that proves the law has teeth.

## Priority — what's left

| # | Candidate | Law shape | Testable today? | Value |
|---|---|---|---|---|
| 1 | Config **parse ↔ serialize** round-trip | round-trip | ❌ **needs `parse` extracted first** | ★★★ highest |
| 6 | `orderedTopLevelPairs/Keys` | permutation-stability + idempotence | ⚠️ subjects are `private` | ★ |
| 7 | `parseParameters` | metamorphic (comment/order insensitivity) + ordering | ✅ yes | ★ |
| — | `apply(diff(a,b), a) == b` | round-trip | ❌ **needs an inverse built first** | see §3 |

---

## 1. Config parse ↔ serialize round-trip — the real round-trip

**Status: OPEN, and blocked on a refactor rather than on effort.**

`YAMLConfigurationEngine.serialize(_ config: YAMLConfig) throws -> String` and
the load path (`load()` → `nodeToDictionary` → `parseDictionaryToConfig` →
`getConfig()`). This is the round-trip the seed manifest was pointing at — **not**
`generateDiff`.

**Law (semantic idempotence of a save/reload):**

```
parse(serialize(config)) ≈ config
```

where `≈` compares the *modeled* fields — `rules`, `included`, `excluded`,
`reporter`, `disabledRules`, `optInRules`, `analyzerRules`, `onlyRules` — and
ignores comments and `keyOrder` (which are layout, not semantics).

**The blocker, stated precisely.** There is no app-side
`parse(String) -> YAMLConfig`: `load()` reads from disk and mutates `self`. The
law as sketched below works around that with temp files, which is why it has not
been written — the honest move is to extract a pure `parse` first and let the
property drive that refactor.

The same absence is why the toolchain is silent here, and the diagnosis is
worth keeping because it was wrong twice before it was right. `serialize` is not
seeded by `swiftprojectlint` for **two independent reasons**: its throwing is
entirely propagated (`try orderedTopLevelPairs`, `try Yams.serialize`), and it
calls sibling methods on `self` that `SelfAccessAnalyzer` will not resolve — a
non-throwing probe of the same shape is refused identically. An earlier reading
blamed `throws` alone; removing that gate did not reach `serialize`. A refuter
that fires first hides the ones behind it.

**Sketch:**

```swift
@Test("a config survives serialize → load unchanged (modeled fields)")
func configRoundTrips() async {
    await propertyCheck(input: Self.configGenerator()) { config in
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)  // note: Date/UUID caveat, see below
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent(".swiftlint.yml")

        let engine = YAMLConfigurationEngine(configPath: path)
        engine.updateConfig(config)
        let yaml = try engine.serialize(config)
        try yaml.write(to: path, atomically: true, encoding: .utf8)

        let reload = YAMLConfigurationEngine(configPath: path)
        try reload.load()
        let back = reload.getConfig()

        #expect(Set(back.rules.keys) == Set(config.rules.keys))
        #expect((back.disabledRules ?? []).sorted() == (config.disabledRules ?? []).sorted())
        // …included/excluded/optInRules/analyzerRules/onlyRules/reporter…
    }
}
```

**Gotchas (each is a place a counterexample could hide — that's the point):**
- **Scalar shorthand.** `line_length: 120` parses into `rules` *and* records
  `scalarShorthandRules` so it re-emits as a scalar, not `{warning: 120}`. A
  config the generator builds with a shorthand rule must round-trip through the
  shorthand path (`warningOnlyInt`).
- **Disabled-rule folding.** A rule with `enabled == false` is emitted only via
  `disabled_rules`, never as a mapping (`disabledRulesNode`). So a generated
  config with a disabled rule that *also* has parameters should come back with
  the rule in `disabledRules` and dropped from `rules` mappings — the equality
  has to model that migration, not demand byte-identity.
- **Int vs String scalar resolution.** `parseScalarValue` re-resolves plain
  scalars so `120` returns `Int`, not `"120"` (or re-serialization quotes it and
  SwiftLint rejects it). A generator that emits numeric-looking string params is
  a good adversary here.
- **Block-sequence indentation** (`indentBlockSequences`) and comment
  reinsertion are layout-only; the `≈` must ignore them.
- **Empty config** is the identity element: `serialize(YAMLConfig())` then load
  yields an empty config.
- **`passthroughNodes`** carries unmodeled top-level keys as Yams `Node`s. A
  generator for them exists (`Tests/.../Utilities/Node+Generator.swift`).

**Verdict:** still the highest value — it exercises the parse and serialize
hotspots (the two densest seed clusters) at once and pins the save/reload path
the whole app depends on. Extract `parse` first.

> Toolchain caveat: `propertyCheck` bodies must avoid `Date()`/`UUID()` if the
> suite is ever replayed deterministically — thread a per-case counter from the
> generator instead of `UUID()` for the temp dir.

---

## 2. `filterViolations` — the easy win ✅ SHIPPED (`aeb701a`)

`WorkspaceAnalyzer.filterViolations(_ violations:[Violation], batch:[URL],
workspacePath:URL) -> [Violation]` keeps violations whose
`workspacePath + filePath` is in `Set(batch.map(\.path))`.

**Laws (all shipped):**
- **Subset:** `Set(result) ⊆ Set(violations)` — never invents a violation.
- **Idempotence under same batch:** `filter(filter(v)) == filter(v)`.
- **Membership characterization:** `v ∈ result ⇔ (workspacePath/v.filePath) ∈ batchPaths`.

Generators use a four-name filename alphabet where "in the batch" and "not in
the batch" nearly coincide — the counterexamples live in the collisions.

`swift-infer` proposes `filter-subset` here (score 35), the template it gained
from this package.

---

## 3. `generateDiff` / `diffBetween` — characterization, **not** round-trip ✅ SHIPPED (`3d58747`)

`YAMLConfigurationEngine.generateDiff(proposedConfig:) -> ConfigDiff` and
`ConfigVersionHistoryService.diffBetween(_:_:)` both compute the same thing:
set algebra over **rule keys**.

```
added    = keys(b) \ keys(a)
removed  = keys(a) \ keys(b)
modified = { r ∈ keys(a) ∩ keys(b) : a.rules[r] != b.rules[r] }
```

**Why the classic round-trip law does NOT apply here.** There is **no
`apply(ConfigDiff, YAMLConfig)` in the codebase**, and `ConfigDiff` is *lossy*:
it records rule-key membership and a `before`/`after` string, but not the new
rule *values*, and it ignores `included`/`excluded`/`reporter`/`disabledRules`
changes entirely. So `apply(diff(a,b), a) == b` is unsatisfiable as written —
you cannot reconstruct `b` from `a` + a `ConfigDiff`. `swift-infer`'s
`diff-disjointness` caveat reaches the same conclusion independently.

**Laws shipped (metamorphic / characterization):**
- **Disjointness:** all three of `added`, `removed`, `modified` pairwise disjoint
  — stronger than the proposed `added ∩ removed = ∅`.
- **Set-algebra:** the exact three-line characterization above.
- **Modified domain:** `Set(modified) ⊆ keys(a) ∩ keys(b)`.
- **Sortedness + no duplicates**, and `hasChanges` agreeing with its three lists.
- **Reflexivity:** `generateDiff(a, a).hasChanges == false`.
- **Swap symmetry:** added↔removed, `modified` swap-invariant.

**Mutant that proves it:** computing `removed` as `proposed \ current` — the
swift-collections `symmetricDifference` bug shape — fails with a shrunk one-key
counterexample. Note that *reflexivity survives that mutant* (with `a == b` both
subtractions are empty either way), so it is the weak law of the set.

**Still open — the round-trip as a design tool.** If we want
`apply(diff(a,b), a) == b` to become a real law, the property *specifies the
feature that doesn't exist yet*: enrich `ConfigDiff` to carry the new values (and
the non-rule-key changes) and add an `apply`. Write the property first, let it
fail to compile, build `apply` until it's green.

---

## 4. `layerChain` — nested-config selection ✅ SHIPPED (`c739ae9`)

`ResolvedConfigurationEngine.layerChain(for targetDirectory:URL, in
tree:ConfigTree) -> [DiscoveredConfig]`: keep configs whose directory is a path
**prefix** (ancestor) of `targetDirectory`, sorted by `depth` ascending.

**Laws shipped:** ancestry (every result's `directoryPath` is a path-component
prefix of the target), drawn-from-tree, and depth ordering. Generators draw
directories from a three-name alphabet so ancestry actually occurs — with a wide
alphabet the chain is almost always empty and the law passes vacuously.

`swift-infer` proposes `selection-subset` here (`result ⊆ ConfigTree.configs`),
the second template this package contributed upstream.

---

## 5. `resolve` merge fold — the invariant, not associativity ✅ SHIPPED (`c6f70d0`)

`ResolvedConfigurationEngine.resolve(...)` folds the layer chain via `merge`.
`mergeMembership` makes `disabled_rules`/`opt_in_rules` **symmetric** (opting a
rule in removes it from disabled and vice-versa); rule configs are deeper-wins;
`excluded`/`included`/`reporter` are **root-only**.

**Laws shipped:**
- **Mutual-exclusion invariant (strongest):** no rule appears in both the
  `disabledRules` and `optInRules` decisions. **Unconditional** — the generator
  emits self-contradicting layers, so this is not merely true of well-formed
  input.
- **Deepest mention wins**, and owns the attribution. (Subsumes mutual exclusion;
  both are stated because the invariant is the one that names the intent.)
- **Deeper-wins for rule configs**, with the next-deepest kept as
  `previousSetBy` history, output sorted by identifier.
- **Root-only keys:** `excluded`/`included`/`reporter` present exactly when the
  *root* sets them, always attributed to the root.
- **Attribution provenance:** every `setBy` names a layer actually in the chain.
- **Identity:** an empty tree, and a chain of empty configs, resolve to nothing.

**The bug this found.** `mergeMembership` performed both removals before either
insertion, so a single config listing a rule in *both* keys landed it in both
resolved sets — reachable by hand-editing a `.swiftlint.yml`, and the inspector
would have shown the rule as simultaneously disabled and opted in.

**SwiftLint was asked, not guessed.** Against the installed **0.65.0** (the
binary the app shells out to; the local source checkout is older and was not
trusted): a config naming `force_unwrapping` in both keys leaves the rule silent
on code that violates it, while `opt_in_rules` alone reports it. `todo`, a
*default* rule, behaves identically. **Disabled wins**, and **no warning is
emitted** — the contradiction is resolved silently rather than rejected, so the
app cannot lean on a diagnostic. The fix drops the opt-in side up front; the four
merge loops are unchanged. A second test pins that the tie-break is *within* a
layer only and does not make disabled sticky across layers.

**Mutants that prove it:** dropping the symmetric removal, dropping the `isRoot`
gate, nulling `previousConfiguration`, and reverting the tie-break — each caught
by its own law. The tie-break revert is the interesting one: before the generator
was widened to emit self-contradicting layers, that exact bug slipped through the
mutual-exclusion law.

**Associativity is NOT clean** — don't chase it. The fold is order-sensitive by
design (deeper-wins) and `mergeRootOnlyKeys` treats the root specially, so
`(a⊕b)⊕c` vs `a⊕(b⊕c)` isn't the right frame.

> The engine header warns that these merge rules drift across SwiftLint versions
> and must be reconciled against a real lint. That warning is now discharged for
> this one tie-break, **at 0.65.0 only**.

---

## 6. `orderedTopLevelPairs` / `orderedTopLevelKeys` — ordering stability

**Status: OPEN. Blocked on visibility, not on the laws.**

`YAMLConfigurationEngine.orderedTopLevelPairs(for:)` orders keys by: (1)
`config.keyOrder`, then (2) `defaultTopLevelKeyOrder` for reserved keys, then
(3) remaining keys sorted alphabetically.

**Laws:**
- **Permutation-stability:** the emitted order depends only on `keyOrder` and the
  key *set*, not on dictionary iteration order — building the same config twice
  (dictionaries are unordered) yields identical output order.
- **Key-set preservation:** `keys(output) == keys(intended emission)` (no key
  dropped or invented).
- **Idempotence via round-trip:** feeding a serialized config's recovered
  `keyOrder` back through produces the same order (ties into §1).

`RuleParameterParser.orderedTopLevelKeys(in:under:)` has a parallel law: it
returns the wrapper's child keys **in source order**, skipping list items and
deeper-nested keys.

**The blocker.** `orderedTopLevelKeys`, `keyName`, `buildParameter`, `isYAMLBool`,
`warningOnlyInt` and `topLevelRuleValue` are all `private` — not reachable from a
test even with `@testable import`. A seeded `discover` run flags **35 seeded
functions as unreachable**, 33 of them `private`/`fileprivate` (the other two are
`internal`, which `@testable import` does reach). §6 and §7 are where this
actually bites. Widen to `internal`, or lift the logic into a type of its own,
before writing these.

---

## 7. `parseParameters` — metamorphic, no inverse

**Status: OPEN. Out of catalog by design — hand-written only.**

`RuleParameterParser.parseParameters(from cliOutput:String, ruleId:) ->
[RuleParameter]?` parses the `Configuration (YAML):` block of `swiftlint rules
<id>` output. There is **no serializer** back to CLI output, so there's no
round-trip — the laws are metamorphic:

- **Comment/blank-line insensitivity:** inserting `#` comment lines or blank
  lines into the block doesn't change the parsed parameter set.
- **Order preservation:** parameters come back in source order
  (`orderedTopLevelKeys`); permuting the source lines permutes the output the
  same way.
- **Placeholder rejection:** any block with a `{Placeholder}:` line returns `nil`
  (`looksLikePlaceholderYAML`) — a good adversarial generator seam.
- **`severity` and nested mappings are dropped** (`buildParameter` returns nil).
- **Bool-before-Int classification:** `true`/`false` never classify as integer
  `0/1` (the `isYAMLBool` CFBoolean check) — a targeted generator of boolean
  params guards this subtle bridging bug.

`deindent` idempotence is already shipped; these build on the same parser.
`parseParameters` is seeded as `pure-function` but matches no template, so the
pipeline offers only the `f(x) == f(x)` tautology — this section is the whole
value here, and it partly overlaps §6's visibility blocker.

---

## 8. `mergedWith` — the union underneath it ✅ SHIPPED (`5e1e9b3`)

Idempotence + completeness + existing-as-prefix shipped earlier (`cf7036c`).

**The framing this section originally had was wrong.** `mergedWith(existing:)` is
**unary**, so it has no associativity of its own. The laws belong to the binary
operation it is a *section* of — order-preserving, left-biased union — which is
stated as a reference definition in the test (the app never needs the binary
form).

**Laws shipped:**
- **Associativity**, plus idempotence and two-sided identity on `[]`.
- **Section:** `mergedWith(existing: a) == merge(a ?? [], directories)` for every
  input *including* `nil` and empty — pinning the `guard existing.isEmpty` fast
  path as an optimisation rather than a second answer.
- **Commutativity on membership but not on order** — the left operand keeps its
  position, which is what makes this a union and not a set union.
- **Multiplicity:** each element keeps the count of whichever side supplied it.

**Note the shape.** Associativity is a law about the *reference definition* and
cannot fail on a production edit; its teeth come entirely from the section law,
which ties `mergedWith` to that reference. That is why this section was rated low
value, and the rating was right.

**Mutant that proves it:** reordering the appended tail
(`existing + missingDefaults.reversed()`) survives *all three* previously shipped
`mergedWith` laws and is caught only by the section law.

**Doc-vs-code drift found here (`601a703`).** The docstring promised "a
deduplicated list"; `existing` is copied verbatim, so
`["Custom","Custom",".build",".build"]` yields 11 elements, 9 distinct.
Deduplicating would contradict the prefix law, so the *docs* were corrected, not
the code. Worth noting for its own sake: this drift is invisible to every
algebraic law over the function — idempotence, completeness and the prefix
property all hold either way. It took reading the sentence and checking the code
against it.

---

## Suggested order of attack

1. **Extract `parse(String) -> YAMLConfig`** and write §1. Highest value left by
   a wide margin, and the property specifies the refactor rather than waiting on
   it.
2. **Widen the `private` parser helpers to `internal`**, then §6 and §7 together
   — they share the blocker and the parser.
3. **Decide on `apply(ConfigDiff, YAMLConfig)`** (§3) — PBT-driven feature work,
   or close the item as won't-do.

Then a `SwiftIdempotency` pass on the actor mutations — `storeViolations`'s
upsert (`9ea2e90`) is the natural `#assertIdempotent` target.

### Housekeeping surfaced by the toolchain re-run

- `.swiftinfer/` is gitignored, so `vocabulary.json` does not sync between
  machines. A vocabulary is project config, not a run artifact — worth a negative
  pattern if it should survive.
- `Tests/Generated/SwiftInfer/` sits **outside every target** (the test target
  defaults to `Tests/SwiftLintRuleStudioCoreTests`). The committed
  `indentBlockSequences` regression stub is never compiled or run, and anything
  `discover --interactive` accepts lands there inert.
