# RuleStudio for SwiftLint — Distribution & Submission Checklist

> Status: pre-submission prep. Apple Developer Program (LLC / Organization) enrollment **approved**.
> This is a planning/reference doc — no code changes implied by its existence.

---

## 0. Decide the distribution path first (this forks everything below)

| Path | You get | You must do | Sandbox required? |
| --- | --- | --- | --- |
| **Mac App Store** | Store listing, discovery, Apple handles notarization, in-app-purchase infra | App Store Connect record, screenshots, App Review | **Yes** |
| **Direct distribution** (DMG from your own site) | No review, no store cut, ship on your schedule | You notarize + staple, build your own updater | No (but Hardened Runtime yes) |

You can ship both eventually, but pick the **primary** path before doing the rest.
Default assumption for this doc: **Mac App Store primary.**

---

## ⚠️ Do this investigation BEFORE the cosmetic work: App Sandbox

> **Note:** This is believed to have been **resolved in an earlier session** — treat the section below as a *verification checklist*, not fresh work. Confirm the distribution build lints in-process via `SwiftLintInProcessBackend` and that file access uses security-scoped bookmarks. If both hold, check this off and move on; don't re-solve it.

The Mac App Store **requires App Sandbox**. RuleStudio likely needs to:

- Read arbitrary Swift source files the user points it at.
- Possibly invoke an external `swiftlint` binary / run analysis.

Both are constrained under the sandbox:

- **File access** → must go through user-selected open panels and **security-scoped bookmarks**; no free filesystem reads.
- **Shelling out to an external binary** → heavily restricted / effectively disallowed for arbitrary executables. If RuleStudio spawns `swiftlint` as a subprocess, that design may not survive the sandbox and may need an in-process backend instead. (Note: this repo already contains a `SwiftLintInProcessBackend` target — confirm whether that's the sandbox-safe path.)

**Action:** confirm the sandbox story before investing in icons/screenshots, because it can force real architectural changes. This is the single most likely blocker.

---

## 1. Signing & identifiers

- [ ] Register the **App ID / Bundle ID** (developer.apple.com → Certificates, IDs & Profiles → Identifiers)
- [ ] **Apple Distribution** certificate + **Mac App Store** provisioning profile (Xcode automatic signing usually handles both)
- [ ] Enable **App Sandbox** entitlement (mandatory for MAS)
- [ ] Enable **Hardened Runtime**
- [ ] Add only the sandbox entitlements actually needed (user-selected files read/write, etc.) — least privilege

---

## 2. App Store Connect record

- [ ] Create the app; reserve a **unique app name** (unique across the entire App Store)
- [ ] SKU, primary language
- [ ] **Category**: Developer Tools
- [ ] **Pricing & availability**
- [ ] **Age rating** questionnaire
- [ ] **App Privacy** ("nutrition label") data-collection questionnaire — required even if you collect nothing
- [ ] **Export compliance** — encryption question (set `ITSAppUsesNonExemptEncryption` in Info.plist to answer it once)

---

## 3. Assets

- [ ] **App icon** — full set in the asset catalog **plus** the **1024×1024** App Store icon
- [ ] **Screenshots** — Mac requires one of: **1280×800, 1440×900, 2560×1600, or 2880×1800**. Minimum 1, up to 10.
- [ ] (Optional) app preview video

---

## 4. Metadata / text

- [ ] Description
- [ ] Keywords
- [ ] Promotional text
- [ ] "What's New" (release notes)
- [ ] **Support URL** (required)
- [ ] **Privacy Policy URL** (required)
- [ ] Marketing URL (optional)
- [ ] Copyright string

---

## 5. Build configuration

- [ ] `CFBundleShortVersionString` (e.g. `1.0`)
- [ ] `CFBundleVersion` (build number — must increment each upload)
- [ ] `LSApplicationCategoryType` in Info.plist (Developer Tools)
- [ ] Minimum macOS deployment target set intentionally

---

## 6. Ship it

- [ ] Archive in Xcode → Organizer → Distribute App → upload (or `xcodebuild` + **Transporter**)
- [ ] (Optional) **TestFlight for Mac** to beta first
- [ ] Submit for review; add **reviewer notes** if the app needs setup steps or sample input to demonstrate

---

## 7. Direct-distribution extras (only if shipping a DMG yourself)

- [ ] **Developer ID Application** certificate (different from the App Store cert)
- [ ] Hardened Runtime + entitlements
- [ ] **Notarize** with `notarytool`
- [ ] **Staple** the ticket to the app/DMG
- [ ] Package as **DMG or PKG**
- [ ] (Optional) **Sparkle** for auto-updates (no App Store = you build the update mechanism)

---

## Most-commonly-forgotten items (the "few more things")

1. **App Sandbox entitlements** — and the design fallout for file access + subprocess use.
2. **Privacy nutrition label** in App Store Connect.
3. **Support URL + Privacy Policy URL** (both required).
4. **Export compliance** encryption answer.
5. **Unique app name** reservation.
6. **Build-number increment** on every upload.

---

### Suggested order of attack

1. Resolve the **sandbox** question (may change the app's architecture).
2. Get the App target **building + signing** under the LLC's team (small verifiable win).
3. **App Store Connect record** + metadata + required URLs.
4. **Icon + screenshots**.
5. **Upload → TestFlight → submit for review.**
