#!/usr/bin/env bash
set -euo pipefail

# Copy-paste detection for first-party Swift sources via PMD's CPD.
#
# CPD finds runs of identical tokens longer than MIN_TOKENS. It catches large
# fresh copy-pastes before they drift; it will NOT catch duplication that has
# already diverged (by then the tokens no longer match), so this is a tripwire,
# not a safety net. Tune MIN_TOKENS deliberately: lower finds more but is noisy.
#
# Exit status: 4 if duplicates are found, 0 if clean (a useful CI gate).
# --skip-lexical-errors: CPD's Swift lexer can't tokenize a few unusual
# backtick tokens; without this it would abort those files and exit 5. With it,
# those (currently 2) files are skipped gracefully and the exit code cleanly
# reflects duplicates-found vs clean.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

MIN_TOKENS="${CPD_MIN_TOKENS:-100}"

if ! command -v pmd >/dev/null 2>&1; then
  echo "error: pmd not found. Install with: brew install pmd" >&2
  exit 127
fi

# Production first-party sources only. The Core package's .build checkout
# directory is never passed in, so vendored dependency code is excluded.
pmd cpd \
  --minimum-tokens "$MIN_TOKENS" \
  --language swift \
  --skip-lexical-errors \
  --dir UI \
  --dir App \
  --dir SwiftLintRuleStudioCore/Sources \
  --format text
