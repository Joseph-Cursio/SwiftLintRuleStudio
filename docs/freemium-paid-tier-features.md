# Freemium model — paid-tier (Team / Enterprise) UI features

A product proposal for monetizing SwiftLintRuleStudio: **free for individuals,
paid for teams and organizations.** This document describes, in detail, the
future UI surfaces reserved for the paid tier — and, just as importantly, what
stays free.

---

## 1. Guiding principle

> The free tier must be a genuinely great tool for one developer on their own
> projects. The paid tier is **additive value for teams** — capabilities an
> individual literally does not need — not a crippled version of the free one.

Two failure modes to avoid:

1. **Crippling the individual** (e.g. "max 5 rules," "1 export per day," nagging
   upsell modals). This poisons word-of-mouth, which is the entire growth engine
   for a developer tool.
2. **Gating the obvious** (basic linting, rule browsing, editing one config).
   These are table stakes; gating them makes the app look hostile.

The clean dividing line is **cardinality and audience**:

| Dimension | Free (Individual) | Paid (Team / Enterprise) |
|---|---|---|
| Repos | one at a time | a *fleet* of repos |
| People | you | a team, with roles |
| Config | your local `.swiftlint.yml` | a shared, governed standard |
| Audience | the developer | also managers / leads / security |
| Runtime | local, offline | local **+** a synced team account |

Everything inherently **multi-repo, multi-person, governed, or reported-on** is
paid. Everything a solo dev needs to lint their own code well is free.

---

## 2. What stays free (the Individual tier)

The full single-developer experience — and it should feel complete, not like a
demo:

- **Rule browser** — all rules, examples, before/after, search, filter by
  category/opt-in.
- **Config editor** — edit one `.swiftlint.yml` with live diff, atomic
  save + backup.
- **Live impact simulation** — "N of M files would change per rule" on one
  project (the existing RuleAudit / ImpactSimulator).
- **Config health analysis** — score, grade, and recommendations for one config
  (the existing `ConfigurationHealthAnalyzer`).
- **Conflict & autocorrect-safety advisories** — the proposed rule-conflict and
  unsafe-autocorrect warnings (see `proposal-rule-conflict-and-autocorrect-safety.md`).
  These are individually useful and build goodwill — keep them free.
- **Built-in presets + local custom presets.**
- **Single-report export** (HTML/CSV/JSON) for one project.
- **Git-branch config diff** for one repo.
- **Migration assistant** for one project (one SwiftLint version bump at a time).

Free is local and offline. No account required.

---

## 3. Paid-tier UI features

Grouped by theme. Each entry describes the UI surface and *why it's team value*.

### A. Shared standards & config governance

The heart of the paid tier: a team defines **one canonical standard** and keeps
every repo aligned to it.

- **Team Standards Library.** A new top-level section listing the org's canonical
  configs ("iOS App Standard," "SwiftUI Package," "Strict"). Each shows an owner,
  description, version history, and a changelog. An individual edits one file; a
  team needs a *distributed, versioned source of truth*. Free tier: local configs
  only.
- **Resolved-config inspector (layering).** SwiftLint supports parent/child config
  chaining. A UI that shows the **resolved** config for a repo and *which layer*
  contributed each rule/severity (org base → team → repo override), with the
  ability to manage the layers. Turns "why is this rule on?" from archaeology into
  a click.
- **Locked rules / required baseline.** Admins mark certain rules and severities
  as **locked** (a developer can't disable them locally) or define a **required
  baseline** every repo must include. The config editor renders locked entries
  with a lock badge and explains the policy. This is the core "governance"
  primitive an individual has no use for.
- **Drift detection.** A per-repo indicator: "in sync with standard" vs "drifted
  (3 rules differ)," with a one-click **Re-align** that previews the impact before
  applying.

### B. Fleet / multi-repo

- **Fleet dashboard.** Add many repos; a grid showing each repo's config **health
  grade**, drift status, SwiftLint version, and violation count. Free is
  one-project-at-a-time; this is the multi-repo aggregate view a lead lives in.
- **Cross-repo config comparison.** Pick several repos and see a matrix of how
  their configs differ — surfacing accidental inconsistency — with a "normalize to
  standard" action.
- **Bulk apply.** Push a standard change to N repos at once, with a **per-repo
  impact preview** (files/rules affected) before committing, and a summary of what
  changed where.
- **Fleet-wide impact simulation.** "If we enable rule X org-wide: 1,240 files
  across 18 repos would change," ranked by repo/team — so leads can scope a
  rollout. The free impact simulator answers this for *one* project; the paid one
  answers it for the *org*.

### C. Reporting & dashboards (manager-facing)

- **Adoption & trend dashboards.** Charts of rule coverage, health-grade
  trajectory, and violation trends **over time** (requires stored history → a
  backend). The free tier shows a point-in-time snapshot; paid shows the curve.
- **Compliance reports.** "16 of 18 repos meet the baseline" with owners and the
  specific gaps; exportable to PDF and schedulable as a recurring email. This is a
  management/security artifact an individual never produces.
- **Hotspot reports.** Which repos/files carry the most violations, where to focus
  cleanup effort.

### D. Collaboration & workflow

- **Config change review.** Propose a standard change, request review, approve —
  a "pull request for the config," inside the app, with an audit trail of who
  changed what and **why**. Individuals just edit and save; teams need
  proposal → review → approval.
- **Rule rationale / annotations.** Attach team-authored notes to a rule
  explaining the org's reason for enabling/disabling it — institutional knowledge
  that survives turnover. Shared across the team; the free tier has no one to
  share with.
- **Shared presets & templates.** Publish custom presets to the team library
  (free tier gets built-in + local-only custom).

### E. CI/CD & integrations

- **CI setup & sync.** Generate GitHub Actions / GitLab CI / Bitrise steps that
  enforce the standard, and keep each repo's config in sync with the org standard
  via an automated PR/bot.
- **PR annotations.** Post SwiftLint findings as inline review comments on
  GitHub/GitLab PRs (the app drives the integration).
- **Chat notifications.** Slack/Teams alerts when a repo drifts from the standard
  or a health grade drops below threshold.
- **Webhooks / API.** Programmatic access for custom CI.

### F. Onboarding & scale

- **New-repo wizard.** One click applies the org standard to a fresh repo —
  config, sensible excludes, and CI — so a new project is compliant from commit 1.
- **Fleet migration assistant.** Bulk-migrate many repos to a new SwiftLint
  version or a new standard, with per-repo compatibility checks (the existing
  `MigrationAssistant` / `VersionCompatibilityChecker`, scaled from one repo to
  many).

### G. Enterprise controls (a distinct top tier)

- **SSO / SAML** for the team account.
- **Role-based access** — admins (own the standard) vs contributors (propose
  changes) vs viewers (dashboards only).
- **Audit log** — every config change, who/when/why, for SOC2-style compliance.
- **Policy enforcement gate** — block merges that don't meet the baseline (via the
  CI integration).
- **On-prem / self-hosted** backend option.

### H. Support (not UI, but part of the paid value)

Priority support, onboarding/training, and an SLA.

---

## 4. Suggested packaging

A three-tier ladder is conventional and maps cleanly to the audience split:

| | **Free** (Individual) | **Team** | **Enterprise** |
|---|:-:|:-:|:-:|
| Full single-project experience | ✅ | ✅ | ✅ |
| Team Standards Library + locked rules | — | ✅ | ✅ |
| Fleet dashboard + bulk apply + cross-repo | — | ✅ | ✅ |
| Trend dashboards + compliance reports | — | ✅ | ✅ |
| Config review/approval + rule rationale | — | ✅ | ✅ |
| CI/PR/chat integrations | — | ✅ | ✅ |
| SSO / RBAC / audit log / policy gate | — | — | ✅ |
| On-prem | — | — | ✅ |
| Support | community | priority | SLA |

Billing is **per-seat** (or per-repo) for Team; **custom/contract** for
Enterprise.

---

## 5. Architecture implications (worth flagging early)

Most paid features are inherently **multi-user and stateful** — a shared standard,
trend history, dashboards, review workflow, integrations — which the current
**local-only macOS app cannot provide alone**. The paid tier implies:

- A **team account + backend service** (the standard library, history, audit log,
  webhooks live server-side and sync to the app).
- The **free tier stays fully local and offline** — no account, no network. This
  keeps the individual experience fast, private, and trust-building, and makes the
  free/paid boundary also a clean *local vs. synced* boundary.

This is a significant build, but it can be **incremental**: ship the free local
app first (it's nearly done), then add the account/backend and light up paid
surfaces one theme at a time (Standards Library → Fleet → Dashboards →
Integrations → Enterprise).

## 6. Gating & licensing (brief)

- Free is unauthenticated and local; paid features appear only when signed into a
  team account with an active subscription.
- Gate at the **capability** level (a feature requires a team), not by nagging or
  artificial per-action limits.
- Graceful downgrade: if a subscription lapses, paid features become read-only /
  hidden, but the local config the user already saved is never held hostage.

## 7. What we should *not* gate

To protect the growth engine, keep these free forever:

- Linting, rule browsing, and editing **one** config.
- Single-project impact simulation, health analysis, and the conflict /
  autocorrect-safety advisories.
- Built-in presets and single-report export.

These are the features that earn the word-of-mouth that fills the top of the
funnel. The paid tier monetizes the moment that single developer becomes "we, the
team, need everyone aligned" — which is exactly when a budget appears.
