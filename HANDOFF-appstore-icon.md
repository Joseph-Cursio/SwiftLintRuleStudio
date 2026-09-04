# Handoff: App Store prep for "RuleExplorer for SwiftLint"

Target in question: **SwiftLintRuleExplorer** (the sandboxed, App-Store edition).
Team ID: L3QPPH39L5 (org account, LLC "Groovy Software Labs").

## Changes already made (all on disk, verified)
project.pbxproj (Explorer app target, both Debug+Release):
- CODE_SIGN_STYLE = Automatic, DEVELOPMENT_TEAM = L3QPPH39L5, CODE_SIGN_IDENTITY = "Apple Development"
- PRODUCT_BUNDLE_IDENTIFIER = com.GroovySoftwareLabs.SwiftLintRuleExplorer (tests: ...ExplorerTests)
- INFOPLIST_KEY_CFBundleDisplayName = "Rule Explorer for SwiftLint"
- Added `Assets.xcassets` to the Resources build phase of BOTH the Explorer and Studio app
  targets. It was missing from EVERY target's Resources phase (this is a file-system-
  synchronized-groups project; Assets.xcassets sits at repo root, outside the synced folders).

Scheme: renamed SwiftLintRuleExplorer.xcscheme -> "RuleExplorer for SwiftLint.xcscheme"
(and updated xcschememanagement.plist key). Still builds the SwiftLintRuleExplorer target.

Icon:
- Active icon = Assets.xcassets/AppIcon.icon (Icon Composer; light + dark 1024 layers,
  per-appearance opacity toggling — verified correct in icon.json).
- Old static PNG set moved OUT of the catalog to AppIconSource/AppIcon.appiconset-static-backup
  (to end an AppIcon name collision). NOT deleted. Source 1024s in AppIconSource/.

Backups: project.pbxproj.bak-preappstore, project.pbxproj.bak-preicon (in the .xcodeproj).

## OPEN ISSUE (unresolved)
App icon shows as a blank white box. Root cause: the asset catalog is NOT compiling into the
built app — the built SwiftLintRuleExplorer.app has NO Assets.car and NO CFBundleIconName.
The on-disk pbxproj IS correct (catalog is in the Explorer Resources phase; the file ref
resolves to the real Assets.xcassets at repo root). Xcode's GUI build was not honoring it
(suspected stale build state).

### Next step
Build from the command line (reads project fresh) and inspect:
  xcodebuild -project SwiftLintRuleStudio.xcodeproj -scheme "RuleExplorer for SwiftLint" \
    -configuration Debug -destination 'platform=macOS' build 2>&1 | tee /tmp/re_build.log \
    | grep -iE "CompileAssetCatalog|actool|error:|BUILD SUCCEEDED|BUILD FAILED"
Then check the built .app for Assets.car / CFBundleIconName.
- If Assets.car appears -> project is fine; it was GUI state (reset Xcode/Dep. data + icon cache).
- If not -> read /tmp/re_build.log around actool for the real error.

Note: the `networkd_settings_read_from_file_locked` console message is harmless sandbox noise; ignore.

## Still TODO for submission (unrelated to the icon)
- App Store Connect: create app record (com.GroovySoftwareLabs.SwiftLintRuleExplorer),
  screenshots, description, support URL, App Privacy questionnaire, export compliance,
  pricing, paid-apps agreement + banking/tax under the LLC.
