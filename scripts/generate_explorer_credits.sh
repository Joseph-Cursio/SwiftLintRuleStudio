#!/usr/bin/env bash
set -euo pipefail

# Regenerates ExplorerApp/Credits.rtf -- the third-party license notices the
# sandboxed Explorer edition shows in its standard About panel (AppKit picks up a
# Credits.rtf in the main bundle on its own; no code reads it).
#
# MIT and Apache-2.0 both require the license text to ship with the binary, and
# the Explorer statically links SwiftLint and its whole dependency graph. Re-run
# this after adding, removing, or bumping a dependency. The list below is what
# SwiftLintFramework links on macOS: CryptoSwift is Linux/Windows-only there, and
# ArgumentParser belongs to the swiftlint executable, not the framework.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$PROJECT_ROOT/ExplorerApp/Credits.rtf"

CHECKOUTS="${CHECKOUTS:-$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/SwiftLintRuleStudio-*/SourcePackages/checkouts 2>/dev/null | head -1)}"
if [[ -z "$CHECKOUTS" || ! -d "$CHECKOUTS" ]]; then
    echo "No resolved package checkouts found. Build the project in Xcode first, or set CHECKOUTS." >&2
    exit 1
fi

# "Display name|checkout directory"
PACKAGES=(
    "SwiftLint|SwiftLint"
    "SourceKitten|SourceKitten"
    "SWXMLHash|SWXMLHash"
    "Yams|Yams"
    "swift-syntax|swift-syntax"
    "swift-filename-matcher|swift-filename-matcher"
    "SwiftyTextTable|SwiftyTextTable"
    "CollectionConcurrencyKit|CollectionConcurrencyKit"
)

html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

HTML="$(mktemp -t explorer-credits).html"
trap 'rm -f "$HTML"' EXIT

{
    cat <<'EOF'
<html><head><meta charset="utf-8"><style>
body { font-family: Helvetica; font-size: 10px; }
h3 { font-size: 11px; margin: 12px 0 2px 0; }
pre { font-family: Helvetica; font-size: 9px; white-space: pre-wrap; }
</style></head><body>
<p>Rule Explorer for SwiftLint is not affiliated with or endorsed by the SwiftLint project.
It includes the following open-source software.</p>
EOF
    for entry in "${PACKAGES[@]}"; do
        name="${entry%%|*}"
        dir="$CHECKOUTS/${entry##*|}"
        license="$(ls "$dir" | grep -iE '^licen[cs]e' | head -1 || true)"
        if [[ -z "$license" ]]; then
            echo "No LICENSE file in $dir" >&2
            exit 1
        fi
        echo "<h3>$name</h3><pre>"
        html_escape < "$dir/$license"
        echo "</pre>"
    done
    echo "</body></html>"
} > "$HTML"

textutil -convert rtf -inputencoding UTF-8 -output "$OUTPUT" "$HTML"
echo "Wrote $OUTPUT"
