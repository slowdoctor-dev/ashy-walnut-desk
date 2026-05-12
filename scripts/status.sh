#!/usr/bin/env bash
# Show current Phase, story progress, Season 1 overview, and what's next.

set -euo pipefail

SPECS_DIR="${SPECS_DIR:-specs}"

if [ ! -d "$SPECS_DIR" ]; then
    echo "❌ No $SPECS_DIR directory found. Run from project root."
    exit 1
fi

echo "📋 ashy-walnut-desk status"
echo ""

# Find current phase: highest phase with any story file
current_phase=0
for phase_dir in "$SPECS_DIR"/phase-*; do
    [ -d "$phase_dir" ] || continue
    phase_num=$(basename "$phase_dir" | sed 's/phase-//')
    stories=$(find "$phase_dir/stories" -name "story-*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$stories" -gt 0 ]; then
        current_phase="$phase_num"
    fi
done

echo "Current phase: $current_phase"

# Phase architecture status for current phase
PHASE_DIR="$SPECS_DIR/phase-$current_phase"
if [ -f "$PHASE_DIR/architecture.md" ]; then
    arch_lines=$(wc -l < "$PHASE_DIR/architecture.md")
    if [ "$arch_lines" -gt 10 ]; then
        echo "Architecture: ✅ drafted ($arch_lines lines)"
    else
        echo "Architecture: ⏳ not yet drafted (run: just architect-prompt)"
    fi
else
    echo "Architecture: ⏳ not yet drafted (run: just architect-prompt)"
fi

# Story counts for current phase
STORIES_DIR="$PHASE_DIR/stories"
if [ -d "$STORIES_DIR" ]; then
    total=$(find "$STORIES_DIR" -name "story-*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    done_count=0
    inprogress=0
    ready=0
    blocked=0

    for story_file in "$STORIES_DIR"/story-*.md; do
        [ -f "$story_file" ] || continue
        status_line=$(grep -m1 '^\*\*Status\*\*:' "$story_file" 2>/dev/null || echo "")
        case "$status_line" in
            *done*)        done_count=$((done_count + 1)) ;;
            *in-progress*) inprogress=$((inprogress + 1)) ;;
            *blocked*)     blocked=$((blocked + 1)) ;;
            *ready*)       ready=$((ready + 1)) ;;
        esac
    done

    echo ""
    echo "Stories in phase $current_phase: $total total"
    echo "  ✅ Done:        $done_count"
    echo "  🟡 In-progress: $inprogress"
    echo "  ⏳ Ready:       $ready"
    echo "  🔴 Blocked:     $blocked"

    # Next ready story (first 3)
    if [ "$ready" -gt 0 ]; then
        echo ""
        echo "Next ready stories:"
        for story_file in "$STORIES_DIR"/story-*.md; do
            [ -f "$story_file" ] || continue
            status_line=$(grep -m1 '^\*\*Status\*\*:' "$story_file" 2>/dev/null || echo "")
            if [[ "$status_line" == *ready* ]]; then
                title=$(head -1 "$story_file" | sed 's/^# Story //')
                echo "  - $title"
            fi
        done 2>/dev/null | head -3
    fi
else
    echo ""
    echo "Stories: not yet generated. Run: just pm-prompt"
fi

# Overall progress: show whatever phase directories exist
echo ""
echo "Phases known to the repo:"
found_any=0
for p in 0 1 2 3 4 5 6 7 8 9; do
    P_DIR="$SPECS_DIR/phase-$p"
    if [ -d "$P_DIR" ]; then
        found_any=1
        if [ -f "$P_DIR/retrospective.md" ]; then
            echo "  Phase $p: ✅ complete (retrospective filed)"
        elif [ -f "$P_DIR/architecture.md" ] && [ -d "$P_DIR/stories" ]; then
            stories_count=$(find "$P_DIR/stories" -name "story-*.md" 2>/dev/null | wc -l | tr -d ' ')
            if [ "$stories_count" -gt 0 ]; then
                echo "  Phase $p: 🟡 in progress ($stories_count stories)"
            else
                echo "  Phase $p: 🟡 architecture done, no stories yet"
            fi
        elif [ -f "$P_DIR/requirements.md" ]; then
            echo "  Phase $p: ⏳ requirements drafted (architecture not yet drafted)"
        else
            echo "  Phase $p: ❌ directory exists but empty"
        fi
    fi
done
[ "$found_any" -eq 0 ] && echo "  (no phase directories yet)"
echo ""
echo "Future phases (1+) are created when reached, per SDD just-in-time spec."

echo ""
echo "Commands:"
echo "  just analyst-prompt    — clarify requirements (BMAD Analyst)"
echo "  just architect-prompt  — design phase architecture (BMAD Architect)"
echo "  just pm-prompt         — break phase into stories (BMAD PM)"
echo "  just story-prompt      — implement next ready story (GSD)"
echo "  just verify            — run all quality gates"
