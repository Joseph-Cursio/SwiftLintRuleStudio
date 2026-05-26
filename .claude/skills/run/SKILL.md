---
name: run
description: Launch and drive SwiftLintRuleStudio's macOS SwiftUI desktop app. This is the verified recipe for this repo — used by the harness `run` skill in preference to its generic fallback patterns. Last verified 2026-05-26 on macOS 26 (Darwin 25.5.0) with Xcode 26.5.
---

# Build

```bash
# CLAUDE.md prefers Xcode-beta; fall back to default Xcode when beta isn't installed.
DEV_DIR=/Applications/Xcode-beta.app/Contents/Developer
[ -d "$DEV_DIR" ] || DEV_DIR=$(xcode-select -p)

DEVELOPER_DIR=$DEV_DIR xcodebuild \
  -project SwiftLintRuleStudio.xcodeproj \
  -scheme SwiftLintRuleStudio \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

Resolve the product path (the DerivedData hash differs per machine — the user works across two machines syncing via GitHub, so don't hard-code it):

```bash
APP=$(DEVELOPER_DIR=$DEV_DIR xcodebuild \
  -project SwiftLintRuleStudio.xcodeproj -scheme SwiftLintRuleStudio \
  -configuration Debug -destination 'platform=macOS' \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/BUILT_PRODUCTS_DIR/{gsub(/^[[:space:]]+/,"",$2); print $2; exit}')/SwiftLintRuleStudio.app
```

Incremental rebuilds are reliable for source-only changes. If a `git pull` updated `Package.resolved` (Yams, ViewInspector, LintStudioUI bumps) or the project file changed, just re-run the same `xcodebuild` line — it re-resolves the package graph in-place.

# Launch

```bash
pkill -x SwiftLintRuleStudio 2>/dev/null
sleep 1
open -a "$APP"
```

No CLI arguments needed for a smoke check — the app opens into its workspace-picker / onboarding flow. To start with a specific workspace already loaded, append a workspace directory: `open -a "$APP" /path/to/workspace`.

# Verify

Don't reach for `screencapture` or `osascript`/System Events first — both are blocked by macOS TCC in most terminal sessions running Claude (Screen Recording and Accessibility respectively, both denied silently). The reliable path is `CGWindowListCopyWindowInfo`, which reads window bounds, on-screen state, and alpha without elevated permissions:

```bash
PID=$(pgrep -x SwiftLintRuleStudio) || { echo "process not running"; exit 1; }
cat > /tmp/list_windows.swift <<'EOF'
import Foundation
import CoreGraphics
guard CommandLine.arguments.count >= 2, let pid = Int32(CommandLine.arguments[1]),
      let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
else { exit(1) }
let mine = info.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
for w in mine {
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    let onScreen = w[kCGWindowIsOnscreen as String] as? Bool ?? false
    let alpha = w[kCGWindowAlpha as String] as? Double ?? -1
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    print("layer=\(layer) onScreen=\(onScreen) alpha=\(alpha) bounds=\(b["Width"] ?? 0)x\(b["Height"] ?? 0)")
}
EOF
swift /tmp/list_windows.swift "$PID"
```

Healthy result: at least one row with `layer=0 onScreen=true alpha=1.0` and bounds wider than ~1000×600 — that's the main app window. Any rows showing 1440×30 off-screen are AppKit's hidden title-bar / window backing surfaces from SwiftUI's `WindowGroup` infrastructure; ignore them, they aren't extra app windows.

Cross-check process health with `ps -p "$PID" -o stat,etime,%cpu,command`. After a few seconds of idle, `%cpu` should settle near 0.0 — that's the event loop quiescent, not a crash loop or busy-wait. Confirm no fresh crash report under `~/Library/Logs/DiagnosticReports/` matching `SwiftLintRuleStudio-*`.

A secondary behavior signal: `lsappinfo list | grep -A1 SwiftLintRuleStudio` should show a child entry `Open and Save Panel Service (SwiftLintRuleStudio)` once the workspace picker is open — that XPC subprocess only spawns when `NSOpenPanel` is presented, so its presence is positive evidence the app reached a real view, not just an empty `App.body` shell.

# Gotchas

- **Xcode-beta vs Xcode**: project `CLAUDE.md` calls for `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, but the beta isn't always installed (the user works across two machines). The build snippet above falls back to `xcode-select -p` when the beta path is missing, so it works on either machine without edits.
- **Screen Recording / Accessibility TCC denied silently**: `screencapture -o out.png` exits 0 but writes nothing and prints `could not create image from display`. `osascript`'s System Events queries return `-25211 osascript is not allowed assistive access`. Both are TCC denials, not bugs. The verify path here sidesteps them; if you specifically need screenshots or UI automation, grant Screen Recording (for `screencapture` + `CGWindowList` window titles) or Accessibility (for `osascript` System Events) to the terminal/IDE running Claude in System Settings → Privacy & Security.
- **DerivedData path is per-machine, not per-repo**: don't hard-code the `SwiftLintRuleStudio-<hash>` segment. The hash is derived from the absolute project path, so the two sync'd machines produce different hashes. Use `xcodebuild -showBuildSettings` to resolve `BUILT_PRODUCTS_DIR` each time, as above.
- **Stale binary after `git pull`**: incremental `xcodebuild` is usually correct, but if behavior diverges from source after pulling — especially across `Package.resolved` bumps — the package cache may need re-resolution. Re-running the same `xcodebuild` line does this; only escalate to deleting `~/Library/Developer/Xcode/DerivedData/SwiftLintRuleStudio-*` if symptoms persist.
