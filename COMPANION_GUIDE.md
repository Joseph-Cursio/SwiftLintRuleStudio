# SwiftLint Rule Studio — A Conversational Guide

*For developers who want to understand their linting setup, not just survive it.*

---

## Table of Contents

1. [Introduction: The SwiftLint Configuration Problem](#1-introduction-the-swiftlint-configuration-problem)
2. [Getting Started](#2-getting-started)
3. [Meeting Your Rules: The Rule Browser](#3-meeting-your-rules-the-rule-browser)
4. [Reading a Rule's Detail: Understanding Before You Commit](#4-reading-a-rules-detail-understanding-before-you-commit)
5. [The Most Important Habit: Simulate Before You Enable](#5-the-most-important-habit-simulate-before-you-enable)
6. [Actually Making Changes: The Preview-Then-Save Flow](#6-actually-making-changes-the-preview-then-save-flow)
7. [The Easy Wins: Safe Rules Discovery](#7-the-easy-wins-safe-rules-discovery)
8. [Living with Violations: The Violation Inspector](#8-living-with-violations-the-violation-inspector)
9. [When Rules Disagree with You: Suppression](#9-when-rules-disagree-with-you-suppression)
10. [Never Lose Your Config: Version History](#10-never-lose-your-config-version-history)
11. [Moving Faster with Bulk Operations](#11-moving-faster-with-bulk-operations)
12. [How Healthy is Your Config? The Health Score](#12-how-healthy-is-your-config-the-health-score)
13. [Importing, Comparing, and Templating](#13-importing-comparing-and-templating)
14. [Keeping Up with SwiftLint: The Migration Assistant](#14-keeping-up-with-swiftlint-the-migration-assistant)
15. [Closing Thoughts: A Workflow That Actually Sticks](#15-closing-thoughts-a-workflow-that-actually-sticks)

---

## 1. Introduction: The SwiftLint Configuration Problem

If you've spent any real time with SwiftLint, you know the feeling. It starts well — you run `brew install swiftlint`, drop a `.swiftlint.yml` in your project root, run `swiftlint` for the first time, and suddenly you're staring at 847 violations. Some of them make complete sense. Others feel arbitrary, or worse, they're failing on code you wrote ten minutes ago that you're pretty sure is perfectly idiomatic Swift. You start hunting through SwiftLint's documentation, Googling rule identifiers, trying to figure out what `unused_closure_parameter` actually wants from you, and whether suppressing it in twelve different files is a reasonable response or a sign of surrender.

Then there's the YAML. The SwiftLint configuration file is not complicated in isolation — it's just a YAML file, and YAML is just YAML. But in practice, you're managing lists of disabled rules and opt-in rules, you're adjusting thresholds for things like `line_length`, you're trying to remember whether a rule goes in `disabled_rules` or whether it needs to be removed from `opt_in_rules`, and you're doing all of this by hand-editing a text file and crossing your fingers that you haven't introduced a syntax error that will make the entire linting run silently fail. The feedback loop is slow: edit, run, parse output, edit again.

The situation gets genuinely thorny on a team. Your colleague enables `force_cast` as an error. CI starts failing. Half the team doesn't understand why the build is red. Someone adds a global `// swiftlint:disable force_cast` at the top of a file, which solves the immediate problem and creates a larger philosophical one. Eventually someone with enough seniority just comments out sections of the config and moves on, and the linting setup quietly rots.

SwiftLint Rule Studio exists to solve this class of problem. It doesn't replace SwiftLint — it wraps it in a native macOS interface that lets you understand what you're doing before you do it. You can browse the full rule catalog with real documentation, simulate the impact of enabling a rule on your actual codebase without touching your config, inspect violations with Xcode integration, and review a YAML diff before every single config write. It's the difference between making a change blindly and making a change deliberately.

This guide is not a reference manual — the REFERENCE.md covers every control and field in exhaustive detail. And it's not a step-by-step tutorial — USER_GUIDE.md handles that. What this guide tries to do is explain the thinking behind each feature: what problem it solves, when you'd reach for it, and how it connects to everything else. Think of it as a longer conversation between peers, not a document to skim for the one answer you need.

---

## 2. Getting Started

The onboarding experience is mercifully short. When you launch the app for the first time, a four-step wizard walks you through confirming that SwiftLint is installed, then selecting a workspace directory. That's really it. The wizard checks your `$PATH` for a SwiftLint installation and shows you the detected version — and if nothing is found, it gives you the three most common installation methods (Homebrew being the recommended one for most people).

The workspace concept is worth a moment of explanation. SwiftLint Rule Studio operates on a directory, not on a specific config file. It looks for a `.swiftlint.yml` in the directory you select and treats everything under that directory as the source code it will lint. A valid workspace just needs to contain Swift source files, an Xcode project, an Xcode workspace, or a `Package.swift` — in other words, anything that signals "this is a real Swift project." Once you've opened a workspace, the app remembers it and shows it in a recent workspaces list on subsequent launches, which means day-to-day usage is just opening the app and clicking your project name.

One small but important detail: if your project doesn't have a `.swiftlint.yml` yet, the app will notice and offer to create a default one. This is a great on-ramp for projects that have never had linting set up — you get a sensible starting point without having to hand-craft a config from scratch.

---

## 3. Meeting Your Rules: The Rule Browser

SwiftLint ships with well over 200 rules. If you've never looked at the full list, that number probably surprises you — most developers are aware of ten or fifteen rules at most, usually the ones they've been burned by. The Rule Browser is designed to fix that by making the entire catalog approachable.

The browser is a split view: a scrollable list of rules on the left, and a detail panel on the right when you select one. Above the list, you have search and three filter controls: Status, Category, and Sort. These work in combination, and they update the rule count in real time as you apply them.

The search field is more capable than it looks. It matches against the rule's identifier (the snake_case name like `force_cast` that goes in your config), its human-readable name, and any keyword in its description. So you can search for "force" and see `force_cast`, `force_try`, and `force_unwrapping` together. Or you can search for "whitespace" and find every rule that's concerned with spacing. This is often faster than browsing by category when you have a specific concern in mind.

The Status filter is where things get interesting. You can filter to All rules, Enabled rules, Disabled rules, or Opt-In rules. The Opt-In filter deserves special attention, because the opt-in distinction is something a lot of developers don't fully understand even after years of using SwiftLint.

Here's the situation: SwiftLint rules are divided into two buckets. Default rules are on for everyone unless you explicitly disable them. Opt-in rules are off for everyone unless you explicitly enable them. The opt-in rules tend to be more opinionated, more project-specific, or more aggressive — things where the SwiftLint team decided "this is a good rule, but not everyone should be forced to use it out of the box." But "not on by default" absolutely does not mean "not valuable." Rules like `first_where`, `empty_count`, `contains_over_first_not_nil`, and `sorted_first_last` catch genuinely sloppy patterns that can affect performance and clarity. `empty_count` alone — which flags `collection.count == 0` in favor of `collection.isEmpty` — is the kind of rule that pays for itself on any reasonably-sized codebase.

Most teams running SwiftLint have never explored their opt-in rules. They have whatever the default set gives them and they've stopped there. Filtering the Rule Browser to Opt-In and spending twenty minutes reading through what's available is one of the highest-value things you can do with this app.

The Category filter lets you focus on a particular family of rules. Style rules are about formatting and naming conventions. Performance rules catch patterns that are demonstrably slower than their alternatives. Idiomatic rules push you toward more Swift-native patterns. Metrics rules track things like function length and complexity. SwiftUI rules handle SwiftUI-specific concerns. If your team is debating whether to invest in performance linting or style linting first, the Category filter makes it easy to survey your options in each domain before committing.

---

## 4. Reading a Rule's Detail: Understanding Before You Commit

When you select a rule in the browser, the detail panel gives you the full picture. This is where the app earns a lot of its value, because the SwiftLint documentation — while good — is spread across multiple places and not always easy to navigate from within your editor. Having it right here, next to the controls for enabling the rule, changes the workflow considerably.

The header tells you immediately whether the rule is currently enabled in your config, whether it's an opt-in rule, whether it's auto-correctable, and whether it requires a minimum Swift version. That auto-correctable badge is genuinely useful to know: if you enable a rule and your codebase has 50 violations, but the rule is auto-correctable, then `swiftlint --fix` can clean up those 50 violations for you automatically. That changes the calculus from "do I want to deal with 50 violations?" to "do I want to run one command?"

Below the header, the description section renders the full SwiftLint documentation for the rule, including a rationale section explaining the reasoning behind why this rule exists. This is where the app is doing something the documentation on GitHub doesn't do well: it makes the rationale visible at the moment you're deciding whether to enable the rule. When you're reading "this rule exists because force-casting in Swift can cause crashes at runtime with no compiler warning," you're reading it in the context of your actual codebase, which is a much better time to absorb that information than when you're already dealing with a production bug.

The triggering and non-triggering examples are particularly helpful for rules where the behavior isn't obvious from the name. Some rule names are self-explanatory: `trailing_whitespace` is exactly what it sounds like. But `unused_closure_parameter` has some subtleties — what counts as "used," what happens with multi-argument closures, when the `_` replacement is appropriate — and seeing concrete code examples of both the bad and good patterns makes the rule's intent immediately clear.

The panel also shows you the current violation count for this rule in your workspace, updated after each analysis run. This count is color-coded: green for zero, orange for anything above zero. This simple indicator changes how you browse rules. When you're exploring the full rule catalog, you can quickly see which enabled rules are actually finding violations right now. And for disabled rules, it can tell you — wait, there are already zero violations from this pattern in my codebase, which means I might be able to enable the rule at no cost. (More on that in a moment.)

The related rules section links to other rules in the same category, which is a good jumping-off point when you're trying to understand a whole family of concerns. If you're looking at `force_cast` and want to understand the broader philosophy around force operations in Swift, the related rules let you navigate there naturally.

---

## 5. The Most Important Habit: Simulate Before You Enable

Here is the workflow pattern that this app was fundamentally built around, and it's the thing I'd most want you to internalize: always simulate a rule's impact before you enable it.

Imagine you're inheriting a codebase that has been in active development for three years with minimal linting. You've opened it in SwiftLint Rule Studio, you're browsing the opt-in rules, and you spot `line_length`. The default maximum line length in SwiftLint is 120 characters, and you'd like to enforce it. How many violations would that create? On a codebase with 100,000 lines of Swift, it could be ten violations or it could be a thousand. You have no idea without running it, and you really don't want to enable the rule, commit, push, and discover that CI is now failing across seventy files.

The Simulate Impact button in the rule detail panel solves this exactly. When you click it, the app takes your current `.swiftlint.yml`, creates a temporary version that adds the rule you're looking at, runs SwiftLint against your workspace with that temporary config, and shows you the results — violation count, affected file count, simulation time, and the first 20 violations with their locations. And critically, it does all of this without touching your actual config file. Your `.swiftlint.yml` is completely unchanged. The simulation is entirely non-destructive.

If the result is zero violations, everything changes. The panel shows a clear "safe" indicator and an "Enable Rule" button appears right there in the simulation results. You can enable the rule immediately, with one click, from inside the simulation sheet. You never have to go back to the rule detail, toggle the switch, preview, save — you just click Enable Rule and you're done. The YAML is written, a backup is created, SwiftLint re-runs. It's one of the more satisfying flows in the app.

If the result is non-zero — say, 43 violations across 12 files — you have a much richer conversation with yourself (or your team) about what to do next. Maybe the violations are concentrated in generated code that you're going to add to your `excluded` paths anyway. Maybe they're all in one legacy file that you're planning to refactor. Maybe 43 violations is totally manageable and you'll knock them out in an afternoon. Maybe 43 violations is a political problem that requires a team conversation before you enable anything. All of those are legitimate outcomes, and you're in a position to have that conversation with actual data rather than guessing.

The simulation runs against your real codebase. It's the actual SwiftLint CLI, on your actual Swift files, with your actual patterns. The results are what you'll actually get. There's no sampling, no approximation, no heuristic. If the simulation says 43 violations, enabling the rule will create 43 violations.

This habit — simulate first, then decide — is the single thing that will most change your relationship with SwiftLint configuration. The anxiety of "what will this break?" dissolves when you know exactly what it will break before you do it.

---

## 6. Actually Making Changes: The Preview-Then-Save Flow

When you're ready to make a change — whether you've simulated it first, or you're enabling a simple formatting rule you know is fine, or you're adjusting a parameter — the change process follows a consistent pattern: toggle or adjust, preview the diff, then save.

The preview step is not optional, and I think that's the right call. A lot of manual YAML editing errors are invisible in the moment. You add a rule to `disabled_rules` that was already in `opt_in_rules`, and now you've got a contradiction in your config. You mistype an indentation level and half your config is silently ignored. You change `line_length` to 100 but forget that you'd also set a `warning` threshold, so now your warning threshold is higher than your max and nothing works right. The diff preview catches all of this by showing you exactly what the new YAML will look like, side by side with the old YAML.

The diff shows you added lines, removed lines, and modified lines — the same format you're used to from `git diff`. It's not a summary or an abstraction; it's the actual YAML content. If you're adding `force_cast` to `opt_in_rules`, you'll see the new line appear in the opt_in_rules list. If you're changing `line_length` from 120 to 100, you'll see the specific key-value pair change. If something looks wrong in the diff, you cancel and nothing happens. Your config is untouched.

One detail worth calling out: the YAML engine preserves your existing comments and key ordering. If you've been careful about organizing your config — grouping related rules with comments explaining the team's decisions — that structure survives through the save process. The app isn't re-generating your config from scratch on every save; it's making surgical edits to the existing file. This matters more than it might seem, because config files that live in version control often have meaningful comments that carry important context. Losing them is losing institutional knowledge.

After you click Save, the app writes a timestamped backup of your previous config before overwriting it. This is automatic and silent — you don't have to do anything to get it. Every version of your config that ever existed is preserved and accessible through Version History. More on that shortly.

---

## 7. The Easy Wins: Safe Rules Discovery

If simulating a single rule is good, simulating all of your disabled rules at once and finding out which ones would introduce zero violations is better. That's what Safe Rules Discovery does.

The use case that motivates this feature is something almost every developer has experienced: you've been using SwiftLint on a project for a while, and you know your config isn't as thorough as it could be, but you have no idea where to start. Enabling rules one by one and simulating each is reasonable, but it's tedious if you're doing it across dozens of candidates. And you have no way to know upfront which rules are worth spending time on and which ones would immediately produce hundreds of violations.

Safe Rules Discovery takes the tedium out of that process. You navigate to the Safe Rules section in the sidebar, click Start Discovery, and the app runs simulations sequentially for every disabled rule in your workspace. This takes a while on larger codebases — each simulation is a real SwiftLint run — and the app shows you a progress indicator with the current rule name and count as it runs. As each simulation completes, rules with zero violations are collected into a results list in real time.

When the discovery finishes, you have a list of rules you could enable right now, today, without creating a single new violation. These are your easy wins. For a project that's never been thoroughly linted, this list can be surprisingly long. Anywhere from ten to forty rules that your codebase already happens to comply with, just sitting there, not enforced. Enabling them costs you nothing and adds meaningful coverage.

The experience of seeing that list for the first time is a bit like running a spell-checker on a document you thought was clean and finding out it's actually clean. You get validation that your code is already following a bunch of good patterns — and you get concrete rules you can enable immediately, with the full team's confidence, because you have proof that there are zero violations.

After discovery, you select the rules you want from the results list, click Enable Selected, and the normal YAML diff preview and save flow kicks in. All selected rules are enabled in a single write, a single backup, a single atomic operation. The Violation Inspector updates automatically.

Safe Rules Discovery is particularly valuable when you're inheriting a codebase. On day one, you don't know how clean or messy the existing code is. Running discovery gives you an honest inventory of which standards the code already meets and which ones it doesn't. You can bring real data to a conversation with your new team about what's achievable immediately versus what will require dedicated refactoring time.

---

## 8. Living with Violations: The Violation Inspector

Once you have rules enabled and SwiftLint running, you have violations. The question becomes how to work with them effectively, especially on a project that has accumulated technical debt over time.

The Violation Inspector is the app's answer to that question. After each SwiftLint run, all violations are stored in a local database, and the Inspector gives you a rich interface for browsing, filtering, grouping, and acting on them.

The statistics bar at the top gives you a live count: total violations, errors specifically, warnings specifically. These update as you apply filters, so you can always see the scope of what you're looking at. Filtering to just errors — which presumably block CI — tells you exactly what's standing between you and a green build. Filtering to just warnings tells you the longer tail of things worth cleaning up but not urgent.

The grouping options are more useful than they might initially appear. Group by File if you're doing a focused cleanup session on a specific part of the codebase — you can see all the violations in a given file together, which makes it faster to fix them in a single editor session. Group by Rule if you want to tackle one kind of violation across the entire codebase at once — useful when you're fixing all `unused_closure_parameter` violations systematically, for example. Group by Severity if you're in triage mode and want to distinguish what's blocking from what's aspirational.

Clicking any violation opens its detail on the right side: the rule ID, the full file path, line and column numbers, and the complete violation message. From there, the Open in Xcode button is one of the features that earns its keep every single day. It calls `xed --line N path` under the hood, which means Xcode comes to the foreground with the cursor sitting exactly at the violation. No file browsing, no searching, no scrolling. You're at the problem in one click.

This matters most when you're doing a cleanup pass and need to visit dozens of violations in sequence. The Inspector has arrow key navigation (Command-Right Arrow and Command-Left Arrow to step through violations), so you can get into a rhythm: review the violation in the Inspector, open in Xcode, fix it, come back to the Inspector, next violation. It's a tighter loop than using Xcode's built-in issue navigator, especially when you want to filter violations by a specific rule or file.

The export capability is worth mentioning for teams. If you're doing a code quality audit or presenting a violation inventory to engineering leadership, you can export the current filtered view as JSON or CSV. The CSV format is particularly useful for spreadsheet analysis — you get rule ID, file path, line, column, severity, message, detection timestamp, and suppression status in ten columns. Filter the Inspector to the violations you care about, export, and you have a report.

---

## 9. When Rules Disagree with You: Suppression

Suppression is a sensitive topic in linting culture. There's a school of thought that says suppression is always a code smell — if your code is triggering a lint rule, the right answer is to fix the code, not silence the rule. There's a competing school of thought that says lint rules are heuristics, heuristics are sometimes wrong, and any rule that can't be overridden on a case-by-case basis is a tool that causes more friction than it prevents.

The practical reality is somewhere in the middle. There are genuinely legitimate reasons to suppress a lint violation: a third-party API that requires a force cast because of Objective-C interop, a closure where the parameter really does need to be ignored but `_` would be less readable than the actual name, a line that's 122 characters long because breaking it across two lines would be significantly harder to read. These are real situations that happen in real projects.

SwiftLint's mechanism for this is the `// swiftlint:disable:next ruleID` comment, which tells SwiftLint to ignore the rule on the following line. Writing this by hand is fine for one-off cases, but it gets tedious and error-prone when you're dealing with multiple violations. More importantly, hand-written suppressions give you no tracking — you have no record of which violations were intentionally suppressed versus which ones are in suppressed files because someone ran a batch disable.

The Violation Inspector's suppression feature gives you that tracking. When you click Suppress on a violation, a dialog asks for an optional reason. That reason becomes associated with the violation in the app's database. Suppressed violations stay in the Inspector list — they don't disappear — but they carry a "Suppressed" badge and they're excluded from violation counts. This means you can always come back and look at what's been suppressed, filter to suppressed-only, and review whether those suppressions are still appropriate as the codebase evolves.

The bulk suppress (Command-Shift-S on a selection of violations) is the feature you reach for when you're in a situation like: you've just enabled a rule, there are 30 violations, 27 of them are in a generated file you're going to exclude from linting anyway, and 3 are in production code that you're deliberately fixing later in the sprint. You can select the 27, suppress them with a reason like "generated file — exclude from linting in next config update," and they're tracked. You haven't lost them; you've noted them and moved on.

The important thing about how suppression works in this app is that it's a tracked state, not just a comment you add and forget. Over time, you can look at your suppression history and make a more informed decision about whether a rule is actually a good fit for your codebase, or whether you'd be better off adjusting its parameters, changing its severity, or disabling it entirely.

---

## 10. Never Lose Your Config: Version History

Configuration files are different from source code in one important way: they don't tend to get reviewed as carefully. Source code changes go through pull requests, code review, CI checks. Configuration changes often happen informally — someone edits the YAML, commits directly to main, and by the time anyone notices something is wrong, three other changes have been layered on top.

Version History is insurance against this. Every time you save a change through the app, a timestamped backup of your `.swiftlint.yml` is created automatically, before the new version is written. The filename includes a Unix timestamp, so you always know exactly when each backup was made. The backups live in the same directory as your config file, which means they're findable and understandable without any special tooling.

The History panel shows all your backups in a list with date, time, and file size. You can select any two backups and compare them side by side — the same YAML diff format as the preview-before-save flow. This is useful for questions like "what did we change last week that made CI start complaining?" or "what did the config look like before we enabled all those performance rules?" The diff answer those questions precisely.

Restoring a backup is a right-click away. The app creates a safety backup of your current config before performing the restore, so you can restore the restore if something goes wrong. This might sound paranoid, but config file restores have a way of happening under pressure when you least want to create new problems.

You can also prune old backups if you don't want them accumulating indefinitely. The prune options let you keep the 5, 10, or 20 most recent versions. For most projects, keeping 10 is plenty — it gives you a window of several weeks or months depending on how frequently you make changes.

One scenario where Version History is particularly valuable: you've been experimenting with different rule configurations over a few weeks, and you want to compare where you started versus where you are now. Select your oldest backup as version one and your current config as version two, and you have a complete audit trail of every rule change made through the app. That's the kind of record that's genuinely useful when your team is doing a quarterly code quality review.

---

## 11. Moving Faster with Bulk Operations

Individual rule changes are fine for one-at-a-time decisions. But there are situations where you want to make a large number of changes at once — and trying to do them one by one, with a preview and save cycle for each, would take forever.

Imagine you've just finished a Safe Rules Discovery run and you have 23 rules with zero violations. You want to enable all of them. Or your team has decided to standardize severity levels across a category: everything in the Performance category should be an error, not a warning. Or you're cleaning up a config that was migrated from an older SwiftLint version and half the rules that were manually listed need to be removed.

Multi-select mode in the Rule Browser is built for exactly these situations. You activate it with the toolbar button, and the rule list switches to checkmark selection mode. You can click individual rules, shift-click to select ranges, or command-click to add individual rules to your selection. A toolbar appears showing your selection count and four actions: Enable All, Disable All, Set Severity, and Preview.

The Preview action is the key one. When you click it, the app generates a combined YAML diff for all your selected rules at once. You see all the additions, removals, and modifications in a single diff view. If something looks wrong — a rule you accidentally selected, a severity you misset — you can cancel and adjust before anything is written. When you confirm, all the changes are written in a single atomic operation with a single backup. Your config file changes once, not twenty-three times.

The Set Severity action is particularly useful for the scenario where you want uniform severity across a set of rules. If your team has agreed that all Metrics rules should produce errors (because you want to fail the build when code exceeds complexity thresholds), you can filter to the Metrics category, enter multi-select, select all, set severity to Error, preview, and save. The whole operation takes about two minutes.

Bulk operations work well in combination with the other features. Discover safe rules, select the ones you want from the results list, enable them all in one pass. Or browse rules by category, identify a cohesive set you want to add, select them, preview, save. The bulk flow is always YAML-diff-gated, so you never lose the safety net of seeing what will change before it changes.

---

## 12. How Healthy is Your Config? The Health Score

The Configuration Health Score is a 0-to-100 number with an A-through-F letter grade that tries to give you an honest assessment of how well your `.swiftlint.yml` is doing its job. It's a useful sanity check, especially after a period of active configuration changes, or when you're onboarding a new project and trying to get a sense of its linting maturity.

The score is calculated across five dimensions. Rules coverage (40% of the score) measures what fraction of the total rule set you've enabled, with an optimal target around 50% — the thinking being that enabling literally every rule would be overkill and create too much noise, but enabling only 5% leaves most of SwiftLint's value on the table. Category balance (20%) checks whether you have at least one enabled rule from each major category, because a setup that only lints for style and ignores performance or metrics is leaving significant coverage gaps. Opt-in adoption (15%) checks whether you've enabled a curated list of high-value opt-in rules like `first_where`, `empty_count`, `sorted_first_last`, and others that the SwiftLint ecosystem has broadly endorsed as universally useful. Deprecation (10%) penalizes use of rules that have been removed or renamed in recent SwiftLint versions. Path configuration (15%) rewards having `excluded` paths set up — important for keeping linting fast and clean on projects that include third-party code like Pods or Carthage dependencies.

What makes the Health Score useful is not the number itself but the recommendations it generates. Each recommendation is tagged High, Medium, or Low priority, and many come with specific actions you can take immediately. If your opt-in adoption score is low, the recommendation might tell you exactly which opt-in rules from the curated list you haven't enabled yet. If your path configuration score is low, it might point out that you don't have `Pods` in your `excluded` paths, which means you might be linting CocoaPods-managed code.

A score of B is probably a realistic target for most mature codebases — it means you're doing well across all five dimensions without being maximally strict about everything. An A requires you to be genuinely thorough about your opt-in rules and path configuration in addition to having solid coverage. An F usually means either a brand-new project with a minimal config or a project that has accumulated deprecated rules and almost no coverage.

The score is a conversation starter, not a verdict. If your team decides that minimizing noise is more important than maximizing coverage, a C might be exactly right for your situation. The value is in knowing the score and understanding what drives it.

---

## 13. Importing, Comparing, and Templating

### Starting from a Template

If you're setting up SwiftLint for a new project, or inheriting a project that has no config at all, starting from a template is faster and more thoughtful than starting from an empty file. The Template Library offers curated starting configurations across two dimensions: project type (iOS App, macOS App, Swift Package, Framework) and coding style (Strict, Balanced, Lenient).

The Lenient templates are worth a special mention because they serve a scenario that often gets overlooked: you've just taken over a legacy codebase and you want to introduce linting without immediately failing CI across the board. A Lenient template gives you a minimal but coherent rule set — enough to catch genuinely dangerous patterns without drowning the team in warnings about whitespace and naming conventions. From there, you can incrementally tighten the config as the team gets comfortable with the workflow.

The Strict templates, on the other hand, are for greenfield projects where you want to establish strong conventions from day one, or for teams that have already cleaned up most violations and are ready to hold a higher bar. The Balanced templates sit in the middle and suit most teams well.

Applying any template goes through the standard YAML diff preview, so you can see exactly what the template will write to your config before it happens.

### Importing from a URL

If your organization maintains a shared SwiftLint config in a company repository, or if you want to adopt a community-maintained config file, the Import Config panel lets you pull it in from any URL. The two import modes — Replace and Merge — address different situations.

Replace is the right choice when you want the imported config to be your entire config. A backup of your current config is created before the replacement. Use this when you're adopting a standard company config on a project that currently has its own divergent setup.

Merge is more nuanced. It unions your existing config with the imported one: `disabled_rules`, `opt_in_rules`, and `excluded` paths are combined rather than replaced. Where there are conflicts at the rule level — you have a rule enabled, the imported config has it disabled — the imported config wins. Use this when you want to adopt some standards from a shared config without discarding your project-specific customizations entirely.

### Git Branch Diff

This feature solves a problem that comes up regularly on multi-developer teams: you're on your feature branch and you want to know whether your `.swiftlint.yml` has diverged from `main`. Or you're doing a code review and you want to quickly check whether the PR includes config changes without reading the raw YAML diff in GitHub.

The Git Branch Diff panel lists all your local branches and tags, and when you select one, it fetches the `.swiftlint.yml` from that branch using `git show` and diffs it against your current config. The result is shown in the same YAML diff format as everywhere else in the app. It's a fast way to see "what would change if I merged main into my branch" from a linting perspective.

### Compare Configs

Where Git Branch Diff compares your current config against a version in git, Compare Configs is a free-form comparison: you point it at any two config files on disk and it shows you the diff. This is useful for comparing configs across different projects, comparing a template against your current config to see what the template would add, or just comparing two configs that have no git relationship at all.

---

## 14. Keeping Up with SwiftLint: The Migration Assistant

SwiftLint is actively developed, and it releases new versions regularly. With each release, some rules get renamed (the old name is deprecated in favor of something clearer), some rules get removed (usually consolidated into other rules), and occasionally rule parameters change their names or formats.

If you update SwiftLint and your `.swiftlint.yml` still references old rule names, the result is usually silent: SwiftLint doesn't error loudly on unknown rule names in most configurations, it just ignores them. This means you might be running a newer SwiftLint that has `some_new_rule_name` and your config still says `some_old_rule_name`, and you have no idea that the rule you thought was protecting you has actually been silently doing nothing for the past three releases.

The Migration Assistant detects this by comparing your config against a catalog of known renames, removals, and parameter changes between SwiftLint versions. It categorizes each issue as one of four types: renamed rules (where the old name maps cleanly to a new name), removed deprecated rules (where the rule simply no longer exists), updated parameters (where a parameter was renamed), and manual actions (where something changed that requires human judgment to resolve).

The first three types are auto-applicable: you can select all auto-applicable steps and apply them in bulk. The app will update your config to use the correct rule names and parameters, going through the standard YAML diff preview first. Manual steps are surfaced as informational flags — things like "a new rule was added in this version that you might want to consider enabling."

Running the Migration Assistant when you update SwiftLint should be a routine part of your update process, the same way you'd run a migration script when updating a database schema. It takes a few seconds and it catches the kind of silent drift that's otherwise very easy to miss.

---

## 15. Closing Thoughts: A Workflow That Actually Sticks

The challenge with linting isn't usually the tooling — it's the habit. SwiftLint is easy to install and easy to ignore. It's easy to pile up violations until CI is overwhelmed and the team implicitly agrees to just live with the red warning count. It's easy to add a blanket disable comment at the top of a file and call it solved. The tool being available doesn't mean it's being used well.

What SwiftLint Rule Studio is actually trying to solve is the engagement problem. The raw CLI is powerful but opaque: you run `swiftlint rules` and get a 200-line table in your terminal, you edit YAML by hand, you have no idea if a new rule will produce ten violations or ten thousand. That opacity discourages thoughtful configuration. It's easier to leave things alone than to engage with something you don't fully understand.

The app tries to lower the cost of engagement at every step. You can read full rule documentation without leaving the tool. You can simulate before committing. You can see a diff before saving. You can undo with version history if you made a mistake. You can discover easy wins automatically. You can act on violations with one-click Xcode navigation. Each of these small friction reductions adds up to a workflow that's genuinely easier to stick with.

The workflow I'd suggest for most teams is something like this: start with a template that matches your project type and starts at Balanced strictness. Run Safe Rules Discovery and enable everything with zero violations. Check the Health Score and work through the High priority recommendations. From there, spend a little time each sprint in the Rule Browser, explore the opt-in rules you haven't looked at yet, simulate a few candidates, and enable the ones that fit. Over a few months, you'll end up with a configuration that's genuinely thorough and genuinely yours — not because you sat down for a heroic afternoon of YAML editing, but because you made incremental, informed decisions over time.

The thing that makes SwiftLint valuable in the long run isn't any individual rule. It's the accumulation of consistent standards across a codebase that multiple people are editing every day. The rules you enforce are a written record of what your team has agreed matters. Getting that right takes iteration, and iteration requires tooling that makes iteration easy. That's what this app is for.

---

*This guide is a companion to the step-by-step USER_GUIDE.md and the exhaustive REFERENCE.md. For keyboard shortcuts, field-by-field reference, and specific technical details, see those documents.*
