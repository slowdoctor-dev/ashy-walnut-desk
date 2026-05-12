#!/usr/bin/env bash
# Validate that code matches /specs.
# Run as part of `just verify`.

set -euo pipefail

EXIT_CODE=0
SPECS_DIR="${SPECS_DIR:-specs}"

echo "🔍 Spec consistency check..."

# Check 1: AGENTS.md exists and is under 300 lines
if [ ! -f AGENTS.md ]; then
    echo "❌ AGENTS.md missing"
    EXIT_CODE=1
else
    lines=$(wc -l < AGENTS.md)
    if [ "$lines" -gt 300 ]; then
        echo "⚠️  AGENTS.md is $lines lines (should be < 300 per AGENTS.md standard)"
        EXIT_CODE=1
    fi
fi

# Check 2: BASELINE.md exists
if [ ! -f BASELINE.md ]; then
    echo "❌ BASELINE.md missing"
    EXIT_CODE=1
fi

# Check 3: All phase directories have requirements.md
for phase_dir in "$SPECS_DIR"/phase-*; do
    [ -d "$phase_dir" ] || continue
    phase_num=$(basename "$phase_dir" | sed 's/phase-//')
    if [ ! -f "$phase_dir/requirements.md" ]; then
        echo "❌ $phase_dir/requirements.md missing"
        EXIT_CODE=1
    fi
done

# Check 4: Every story file has required sections
for story_file in "$SPECS_DIR"/phase-*/stories/story-*.md; do
    [ -f "$story_file" ] || continue
    name=$(basename "$story_file")
    for required in "## Goal" "## Acceptance criteria" "## Verification"; do
        if ! grep -q "^$required" "$story_file"; then
            echo "⚠️  $name missing section: $required"
            EXIT_CODE=1
        fi
    done
done

# Check 5: Stories reference existing files (for Files to create / modify sections)
# (Skipped for now — phase 0 has no code yet)

# Check 6: ADR files follow naming convention
for adr_file in "$SPECS_DIR"/decisions/ADR-*.md; do
    [ -f "$adr_file" ] || continue
    name=$(basename "$adr_file")
    if ! echo "$name" | grep -qE '^ADR-[0-9]{3}-[a-z0-9-]+\.md$'; then
        echo "⚠️  $name doesn't match ADR-NNN-kebab-name.md"
        EXIT_CODE=1
    fi
done

# Check 7: Deployer-specific terminology hooks
# Deployments may want to enforce terminology conventions specific to
# their domain or locale (e.g., respectful client terms in healthcare,
# specific case terms in legal contexts, or any non-English vocabulary
# discipline). Add such checks in a deployment-specific override script
# if needed. The framework itself does not enforce any locale-specific
# or domain-specific terminology.

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "✓ Spec consistency check passed"
else
    echo ""
    echo "Fix the issues above, then re-run."
fi

exit $EXIT_CODE
