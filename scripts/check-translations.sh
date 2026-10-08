#!/bin/bash
set -euo pipefail

# Validates HADashboard/<lang>.lproj/Localizable.strings (and .stringsdict)
# against the en.lproj source of truth. See docs/translations.md and
# docs/plans/i18n-plan.md §4.3 for the rules this enforces:
#
#   1. Key extraction: every HALocalizedString(@"key", ...) call site in
#      source has a matching en.lproj entry.
#   2. Key-set parity: non-en .lproj files must not define keys en.lproj
#      lacks (missing keys are allowed -- a partial translation falls back
#      to en at runtime).
#   3. Format-specifier parity: each key's printf-style specifiers must
#      match exactly between en and every other language. A mismatch is a
#      crash, not a cosmetic bug.
#   4. plutil -lint on every .strings / .stringsdict file (macOS only; see
#      check_translations.py's own plistlib-based validation for the
#      cross-platform equivalent, used in CI).
#   5. UTF-8 / no-BOM encoding check.
#
# --strict additionally fails on missing keys, empty values, and
# .stringsdict plural-category gaps -- this is CI's mode
# (.github/workflows/translations.yml): a language must be merged
# complete, never partial. See docs/translations.md.
#
# Usage:
#   scripts/check-translations.sh              # run all checks, exit non-zero on failure
#   scripts/check-translations.sh --strict      # CI's mode -- also fails on incompleteness
#   scripts/check-translations.sh --pseudo      # also (re)generate HADashboard/en-XA.lproj
#   scripts/check-translations.sh --strict --pseudo   # combine freely, any order

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

PY_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --pseudo) PY_ARGS+=(--pseudo) ;;
        --strict) PY_ARGS+=(--strict) ;;
        *)
            echo "❌ Unknown argument: $arg (expected --pseudo and/or --strict)" >&2
            exit 1
            ;;
    esac
done

if ! command -v python3 &>/dev/null; then
    echo "❌ python3 not found" >&2
    exit 1
fi

set +e
python3 -I "$SCRIPT_DIR/check_translations.py" "$PROJECT_DIR" ${PY_ARGS[@]+"${PY_ARGS[@]}"}
STATUS=$?
set -e

# plutil -lint every .strings / .stringsdict (only available on macOS, which
# is the only place these build scripts ever run anyway).
if command -v plutil &>/dev/null; then
    echo ""
    echo "Running plutil -lint over all .strings/.stringsdict files..."
    LINT_LOG="$(mktemp)"
    while IFS= read -r -d '' f; do
        if ! plutil -lint "$f" >"$LINT_LOG" 2>&1; then
            echo "❌ plutil -lint failed for $f"
            cat "$LINT_LOG"
            STATUS=1
        fi
    done < <(find HADashboard -type d -name "*.lproj" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | xargs -0 -I{} find {} \( -name "*.strings" -o -name "*.stringsdict" \) -print0)
    rm -f "$LINT_LOG"
fi

exit "$STATUS"
