# Property-Based Test Candidates — SwiftLintRuleStudioCore

_An exploration of the property laws the Core kernels invite, grounded in the
actual code (not the seed manifest's guesses). Each entry gives the real
signature, the honest law(s), a generator sketch in the repo's toolchain, the
gotchas that make it interesting, and a testable-today verdict._

Toolchain: `swift-property-based` (`propertyCheck(input:)` + `Gen`/`Generator`)
and `PropertyLawKit`, already used in
`Tests/.../Services/KernelPropertyLawTests.swift` and
`Tests/.../Models/RuleValueTypePropertyLawTests.swift`. Pipeline (pbt-book
Appendix C): `SwiftProjectLint` → `swift-infer discover` → `SwiftPropertyLaws`
→ `SwiftIdempotency`. Steps 1–2 are done; everything below is the
`SwiftPropertyLaws` work.

## Already shipped (for reference)

`KernelPropertyLawTests` (`cf7036c`): `deindent` idempotence; `mergedWith`
idempotence + completeness + existing-as-prefix; `levenshteinDistance` metric
axioms; `isVersion` strict-weak-ordering. Plus three `SwiftInferProperties`
toolchain fixes (`628b3ae`, `687ffd7`, `4853341`) that let `discover` recognize
`(T?) -> T` idempotence and emit a runnable generator for String-collection
carriers.

## Priority

| # | Candidate | Law shape | Testable today? | Value |
|---|---|---|---|---|
| 1 | Config **parse ↔ serialize** round-trip | round-trip | ✅ yes | ★★★ highest |
| 2 | `filterViolations` | subset + idempotence + membership | ✅ yes | ★★ easy win |
| 3 | `generateDiff` / `diffBetween` | characterization (self-diff, set algebra, swap) | ✅ yes | ★★ |
| 4 | `layerChain` | ancestor/subsequence/monotonicity | ✅ yes (synthetic tree) | ★★ |
| 5 | `resolve` merge fold | mutual-exclusion invariant + deeper-wins + identity | ✅ yes | ★★ |
| 6 | `orderedTopLevelPairs/Keys` | permutation-stability + idempotence | ✅ yes | ★ |
| 7 | `parseParameters` | metamorphic (comment/order insensitivity) + ordering | ✅ yes | ★ |
| 8 | `mergedWith` **associativity** | associativity | ✅ yes | ★ (idempotence already done) |
| — | `apply(diff(a,b), a) == b` | round-trip | ❌ **needs an inverse built first** | see §3 |

---

## 1. Config parse ↔ serialize round-trip — the real round-trip

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

**Verdict:** highest value — it exercises the parse and serialize hotspots (the
two densest seed clusters) at once and pins the save/reload path the whole app
depends on. The `updateConfig`/`serialize`/`load` dance and the temp-file I/O
make it heavier than a pure-function law, but it's fully deterministic.

> Toolchain caveat: `propertyCheck` bodies must avoid `Date()`/`UUID()` if the
> suite is ever replayed deterministically — thread a per-case counter from the
> generator instead of `UUID()` for the temp dir.

---

## 2. `filterViolations` — the easy win

`WorkspaceAnalyzer.filterViolations(_ violations:[Violation], batch:[URL],
workspacePath:URL) -> [Violation]` keeps violations whose
`workspacePath + filePath` is in `Set(batch.map(\.path))`.

**Laws:**
- **Subset:** `Set(result) ⊆ Set(violations)` — never invents a violation.
- **Idempotence under same batch:** `filter(filter(v)) == filter(v)`.
- **Membership characterization:** `v ∈ result ⇔ (workspacePath/v.filePath) ∈ batchPaths`.
- **Empty batch ⇒ empty result.**

Pure, no I/O, trivial generators (`Violation` with a small filename alphabet, a
batch of URLs some of which match). Best first law to write — cheapest, and it
guards the incremental-analysis path.

---

## 3. `generateDiff` / `diffBetween` — characterization, **not** round-trip

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
you cannot reconstruct `b` from `a` + a `ConfigDiff`.

**Laws that DO hold (metamorphic / characterization):**
- **Reflexivity:** `generateDiff(a, a).hasChanges == false`.
- **Disjointness:** `Set(added) ∩ Set(removed) == ∅`.
- **Set-algebra:** `added == keys(b)\keys(a)`, `removed == keys(a)\keys(b)`.
- **Modified domain:** `Set(modified) ⊆ keys(a) ∩ keys(b)`.
- **Swap symmetry:** `generateDiff(a,b).added == generateDiff(b,a).removed` and
  vice-versa; `modified` is swap-invariant as a set.
- **Sortedness:** all three arrays are sorted (the impl sorts them).

**The round-trip is a PBT-driven-development opportunity, flagged honestly.** If
we want `apply(diff(a,b), a) == b` to become a real law, the property *specifies
the feature that doesn't exist yet*: enrich `ConfigDiff` to carry the new values
(and the non-rule-key changes) and add an `apply`. Write the property first, let
it fail to compile, build `apply` until it's green. That's the strongest
argument for keeping this section — the law is a design tool, not just a test.

---

## 4. `layerChain` — nested-config selection

`ResolvedConfigurationEngine.layerChain(for targetDirectory:URL, in
tree:ConfigTree) -> [DiscoveredConfig]`: keep configs whose directory is a path
**prefix** (ancestor) of `targetDirectory`, sorted by `depth` ascending.

**Laws:**
- **Ancestry:** every returned config's `directoryPath` is a prefix of
  `targetDirectory` (by path components).
- **Subsequence of depth-sort:** result is exactly the applicable set ordered by
  `depth` — sorted and stable.
- **Monotonicity under descent:** if `t2` is a descendant of `t1`, then
  `layerChain(t1) ⊆ layerChain(t2)` (going deeper only *adds* layers).
- **Root always present / empty tree ⇒ empty chain** (identity edges).

Generator builds a synthetic `ConfigTree` from small path-component alphabets
(e.g. dirs drawn from `["a","b","c"]` joined into paths) so ancestry actually
occurs. No file I/O — `layerChain` is `nonisolated static` and pure over the
tree.

---

## 5. `resolve` merge fold — the invariant, not associativity

`ResolvedConfigurationEngine.resolve(...)` folds the layer chain via `merge`.
`mergeMembership` makes `disabled_rules`/`opt_in_rules` **symmetric** (opting a
rule in removes it from disabled and vice-versa); rule configs are deeper-wins;
`excluded`/`included`/`reporter` are **root-only**.

**Laws:**
- **Mutual-exclusion invariant (strongest):** in the resolved output no rule
  appears in both `disabledRules` decisions and `optInRules` decisions — a
  metamorphic law that directly encodes the symmetric-removal logic and would
  catch any regression in `mergeMembership`.
- **Deeper-wins:** for a rule configured in multiple layers, the resolved
  `setBy` is the deepest layer that set it (and `previousConfiguration` is the
  next-deepest).
- **Identity:** resolving an empty tree (or a single empty root) yields an empty
  `ResolvedConfiguration`.

**Associativity is NOT clean** — don't chase it. The fold is order-sensitive by
design (deeper-wins) and `mergeRootOnlyKeys` treats the root specially, so
`(a⊕b)⊕c` vs `a⊕(b⊕c)` isn't the right frame. The mutual-exclusion invariant is
the law that actually captures the intent.

---

## 6. `orderedTopLevelPairs` / `orderedTopLevelKeys` — ordering stability

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

---

## 7. `parseParameters` — metamorphic, no inverse

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

---

## 8. `mergedWith` — associativity (the remaining piece)

Idempotence + completeness + existing-as-prefix are shipped. What's left:

- **Associativity/absorption:** `mergedWith(mergedWith(a) ++ b) ` relationships —
  concretely, merging is order-preserving union with the fixed `directories`
  suffix, so `mergedWith(existing:)` composed with more defaults is stable. Lower
  value than the shipped laws; include only if rounding out the kernel.

---

## Suggested order of attack

1. **`filterViolations`** (§2) — cheapest, pure, guards incremental analysis.
2. **Config round-trip** (§1) — highest value; exercises both dense hotspots.
3. **`generateDiff` characterization** (§3) — and decide whether to build `apply`
   to unlock the true round-trip (PBT-driven feature work).
4. **`layerChain` + resolve invariant** (§4, §5) — the nested-config engine.
5. Ordering/parse metamorphic laws (§6, §7) as time allows.

Then a `SwiftIdempotency` pass on the actor mutations — `storeViolations`'s
upsert (`9ea2e90`) is the natural `#assertIdempotent` target.
