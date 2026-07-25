# Property-Based Test Candidates — SwiftLintRuleStudioCore

_An exploration of the property laws the Core kernels invite, grounded in the
actual code (not the seed manifest's guesses). Each entry gives the real
signature, the honest law(s), a generator sketch in the repo's toolchain, the
gotchas that make it interesting, and a testable-today verdict._

Toolchain: `swift-property-based` (`propertyCheck(input:)` + `Gen`/`Generator`)
and `PropertyLawKit`. Pipeline (pbt-book Appendix C): `SwiftProjectLint` →
`swift-infer discover` → `SwiftPropertyLaws` → `SwiftIdempotency`.

**Status: 8 of 8 closed.** Every candidate on this list is shipped. The suite is
**47 property-law tests across 9 suites** (`swift test --filter PropertyLaw`).
What remains is the one item that was never on the list as a law —
`apply(ConfigDiff, YAMLConfig)`, which needs a feature built first (§3).

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
| 1 | `serialize` ↔ `parse` round-trip + text fixed point | `Services/ConfigRoundTripPropertyLawTests` | `439cf79` (refactor `127351f`) |
| 6 | top-level key ordering — insertion-order independence | `Services/OrderingStabilityPropertyLawTests` | `958abba` |
| 7 | `parseParameters` metamorphic laws | `Services/ParseParametersPropertyLawTests` | `450832d` |

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

## What's left

| # | Candidate | Law shape | Testable today? | Value |
|---|---|---|---|---|
| — | `apply(diff(a,b), a) == b` | round-trip | ❌ **needs an inverse built first** | see §3 |

Plus two decisions rather than laws: `YAMLConfig.warningThreshold` / `.strict`
(dead on both paths — §1), and whether `apply` gets built at all.

---

## 1. Config parse ↔ serialize round-trip — the real round-trip ✅ SHIPPED (`439cf79`)

`YAMLConfigurationEngine.serialize(_ config: YAMLConfig) throws -> String` and
`parse(_ yaml: String) throws -> YAMLConfig`.

**This was the PBT-driven-development case, and it played out as advertised.**
The law was blocked on a refactor, not on effort: there was no app-side
`parse`, because `load()` read from disk and wrote its results into `self`. The
property specified the extraction — `parse(_:)` (`127351f`) now holds everything
past reading the file and is pure, so `parse(serialize(config))` needs no
filesystem. `load()` is two lines. `extractComments`/`extractKeyOrder` became
pure statics in the same change.

**Laws shipped — two, and the second is stronger:**

```
A.  parse(serialize(config)) ≈ config          — on the modeled fields
B.  serialize(parse(serialize(config))) == serialize(config)
```

B carries no field model, so nothing can be quietly dropped from the comparison,
and it covers the layout A's `≈` deliberately ignores.

**`≈` is not equality, and every gap is a real emission rule.** Two of the three
had to be derived by probing the engine; both were guessed wrong on the first
attempt, which is worth recording because they are exactly the kind of rule a
round-trip law is assumed to be able to skip:

- A rule with `enabled == false` is emitted only via `disabled_rules` (SwiftLint
  has no per-rule disable), so it returns in `disabledRules` and absent from
  `rules`.
- **A rule with neither a severity nor parameters emits nothing at all** — there
  is no YAML to write for it — so it does not survive a round-trip in any form.
- **The scalar shorthand survives only when the rule actually qualifies**: no
  severity, and a lone integer `warning`. A config that asks for the shorthand on
  any other shape degrades to a mapping, and the parser correctly does not mark
  it. The generator is allowed to ask for it anyway, so that degradation is
  exercised.

The last two are stated as reference definitions (`emitsScalarShorthand`,
`emittedRuleKeys`) rather than buried in expectations.

**The mutation run found a blind spot in law B itself.** Three mutants:

| Mutant | Caught by |
|---|---|
| Drop the `enabled == false → disabled_rules` migration | A |
| `parse` forgets scalar shorthands | **both** — B fails because `line_length: 120` re-emits as a mapping |
| Drop `indentBlockSequences` | **nothing** |

The third **survived**, and the reason generalises: law B ranges only over the
*image* of `serialize`, so a layout regression that changes every emission
equally still round-trips against itself. Closed by
`handWrittenConfigIsAFixedPoint`, which parses a conventionally formatted
`.swiftlint.yml` and asserts the re-emitted text is byte-identical — the
user-facing statement anyway ("open and save must not rewrite my file"), and it
catches that mutant. **A fixed-point law over a function's own output is weaker
than it looks; pin it against text a human wrote.**

**Also pinned:** the empty config is the identity element (`serialize` emits
`{}\n`, which parses back to empty); passthrough keys (`custom_rules`,
`warning_threshold`, `strict`) and their comments survive; and numeric-looking
string parameters stay quoted, since unquoting one makes SwiftLint reject the
file.

> **Finding, unaddressed by design.** `YAMLConfig.warningThreshold` and
> `.strict` are dead on *both* paths: `parse` never populates them (those keys
> route to `passthroughNodes`), and `serialize` never emits them — a config with
> `warningThreshold = 10` and nothing else serializes to `{}`. No user data is
> lost, because text-loaded configs carry the keys through passthrough, but any
> code setting the two properties programmatically is a silent no-op. Removing
> them is an API change and was left alone.

**The remaining gotchas from the original sketch all held**, and are now pinned
rather than merely hoped for: scalar shorthand, disabled-rule folding, int vs
string scalar resolution, block-sequence indentation, and the empty config.


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

## 6. `orderedTopLevelPairs` / `orderedTopLevelKeys` — ordering stability ✅ SHIPPED (`958abba`)

`YAMLConfigurationEngine.orderedTopLevelPairs(for:)` orders keys by: (1)
`config.keyOrder`, then (2) `defaultTopLevelKeyOrder` for reserved keys, then
(3) remaining keys sorted alphabetically.

The hazard it defends against is that `config.rules` is a **dictionary** —
unordered — so a naive emission reorders a user's `.swiftlint.yml` differently
on different runs and produces noisy diffs from an unchanged file.

**Laws shipped:**
- **Insertion-order independence:** the config is built twice with its rules
  inserted in opposite orders, and the two serializations must be *byte*-identical.
- **`keyOrder` honored** as a relative order, over the keys that survive emission
  — `keyOrder` may name keys the config no longer carries.
- **No key emitted twice.**
- **The unnamed tail is alphabetical** — the branch that makes output stable
  rather than hash-dependent.
- **The recovered order is a fixed point** under re-serialization.

> **The visibility blocker was a phantom, and this is the correction.** Earlier
> revisions of this doc listed §6 (and §7) as blocked on widening `private`
> helpers, on the strength of `swift-infer` emitting *"seeded function is not
> reachable from a test"* for 35 functions. That note is about **the tool wanting
> to call each seeded function directly** — which is not the same as a law needing
> to. The emitted order is observable as `parse(serialize(config)).keyOrder`,
> because `parse` recovers order from the text. **Nothing was widened**, and the
> laws bind at the public boundary. Taking a tool's reachability complaint as a
> design constraint would have cost real encapsulation for nothing.

**One law had to be corrected while writing it.** Permuting the source is only a
permutation when the names are distinct: with repeats, reversing changes which
entry wins dedup, so the surviving key set legitimately differs.

**Mutants caught:** reverse-sorting the unnamed tail, and ignoring
`config.keyOrder` entirely — each by its own law.

---

## 7. `parseParameters` — metamorphic, no inverse ✅ SHIPPED (`450832d`)

`RuleParameterParser.parseParameters(from cliOutput:String, ruleId:) ->
[RuleParameter]?` parses the `Configuration (YAML):` block of `swiftlint rules
<id>` output. There is **no serializer** back to CLI output, so there is no
round-trip and the laws are metamorphic: change the input in a way that should
not matter, and demand the output not move.

**Laws shipped:** comment-line insensitivity; source-order preservation with
`severity` and nested mappings dropped; permuting the source permutes the
output; boolean classification; placeholder rejection; the blank-line
terminator; and a missing `Configuration` block yielding nil.

Also stated at the public boundary — `parseParameters` is already `public`, so
`buildParameter` / `isYAMLBool` / `keyName` stayed private. See the note in §6.

**The law this doc stated was wrong, and writing it is what showed that.** The
claim was *"inserting `#` comment lines **or blank lines** doesn't change the
parsed parameter set."* The blank-line half is false: `extractYAMLBlock` treats
a blank line after content as the **end of the section**, because that is how
SwiftLint separates `Configuration (YAML):` from `Triggering Examples:`.
Everything after it is invisible. Now pinned as its own test, since a plausible
"skip blank lines" tidy-up would silently swallow the next section as
configuration.

> **A guard that is not doing work.** Reordering `buildParameter` to check `Int`
> before `Bool` — the exact bug `isYAMLBool`'s CFBoolean probe was written
> against — leaves the suite **green**. Probing directly: on Yams 6.2.1 with this
> toolchain `Yams.load` returns a genuine Swift `Bool`, for which `as? Int` is
> `nil`, so the Foundation number-bridging hazard the guard describes does not
> manifest here. The guard is correct and cheap and stays as insurance against a
> Yams change — but the test records that a green run is **not** evidence it is
> load-bearing. This is the failure mode the whole exercise exists to catch,
> found in our own defensive code rather than someone else's.

**Mutant caught:** dropping the `severity` skip in `buildParameter`.

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

## What this list produced

Eight candidates, all closed. The output that mattered was not the suggestion
count and not the test count:

- **Two production bugs**, neither reachable by any template in the catalog: the
  same-layer `disabled_rules`/`opt_in_rules` contradiction (§5) and the
  `mergedWith` docstring drift (§8). Both were found by reading a sentence — a
  merge semantic and a docstring — and checking the code against it.
- **Three laws in this doc were wrong**, and writing them is what showed it: §8
  asked for associativity of a unary function, §7 claimed blank lines were
  insignificant, and §6's permutation law was not a permutation.
- **Two guards that do not guard.** Law B in §1 could not see a layout
  regression, and `isYAMLBool` (§7) survives the mutation it exists to prevent.
  Both are now documented as such rather than trusted.
- **One phantom blocker.** §6 and §7 were listed as needing `private` helpers
  widened, on the strength of a tool's reachability note. They needed nothing;
  the laws bind at the public boundary.

## Next

1. **Decide on `apply(ConfigDiff, YAMLConfig)`** (§3) — PBT-driven feature work,
   or close the item as won't-do.
2. **Decide on `YAMLConfig.warningThreshold` / `.strict`** (§1) — dead on both
   the parse and serialize paths. Either delete them or route them through the
   modeled path; leaving them is a trap for the next caller.

Then a `SwiftIdempotency` pass on the actor mutations — `storeViolations`'s
upsert (`9ea2e90`) is the natural `#assertIdempotent` target.

Unrelated to this list, but found while running it: `RuleRegistryBackgroundLoadingTests`
asserts a wall-clock `elapsed < 1.0s` and fails intermittently under CPU load.
It will be flaky on a loaded CI runner.

### Housekeeping surfaced by the toolchain re-run

- `.swiftinfer/` is gitignored, so `vocabulary.json` does not sync between
  machines. A vocabulary is project config, not a run artifact — worth a negative
  pattern if it should survive.
- `Tests/Generated/SwiftInfer/` sits **outside every target** (the test target
  defaults to `Tests/SwiftLintRuleStudioCoreTests`). The committed
  `indentBlockSequences` regression stub is never compiled or run, and anything
  `discover --interactive` accepts lands there inert.
