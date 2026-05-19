#!/usr/bin/env bash
# Phase 3 AuditLive + Compensation flow screenshot capture.
#
# Reproducible from `just phase3-screenshots`. Assumes the dev server is up
# (`just dev` in another terminal) and Postgres is running.

set -euo pipefail

URL="${PHX_URL:-http://localhost:4000}"
EMAIL="${DEMO_EMAIL:-demo-admin@example.com}"
DISPLAY_NAME="${DEMO_DISPLAY_NAME:-Aria Demo}"
OUT="${OUT_DIR:-docs/phase-3-screenshots}"

echo "→ verifying dev server at ${URL}"
if ! curl -sSf -o /dev/null -m 5 "${URL}"; then
  echo "✗ no dev server at ${URL}. Start it with: just dev" >&2
  exit 1
fi

echo "→ seeding phase 3 demo data"
mix phase3.demo.seed --email "${EMAIL}" --display-name "${DISPLAY_NAME}"

# Pull the seeded inbox id (most-recently created, since the seed
# creates exactly one chain per run).
INBOX_ID=$(mix run -e '
  require Ash.Query
  row =
    AshyWalnutDesk.Interaction.Inbox
    |> Ash.Query.sort(created_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  IO.write(row.id)
' 2>/dev/null | tail -1)

if [ -z "${INBOX_ID}" ]; then
  echo "✗ no inbox seeded" >&2
  exit 1
fi

echo "→ capturing phase 3 screenshots (inbox ${INBOX_ID}) into ${OUT}"
python3 scripts/screenshots-phase3.py \
  --url "${URL}" \
  --email "${EMAIL}" \
  --inbox-id "${INBOX_ID}" \
  --out "${OUT}"

echo "✓ screenshots ready in ${OUT}/"
ls -1 "${OUT}"
