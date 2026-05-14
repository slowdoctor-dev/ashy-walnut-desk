#!/usr/bin/env bash
# Phase 1 timeline UI screenshot capture.
#
# Reproducible from `just screenshots`. Assumes the dev server is up
# (`just dev` in another terminal) and that Postgres is running.

set -euo pipefail

URL="${PHX_URL:-http://localhost:4000}"
EMAIL="${DEMO_EMAIL:-demo-admin@example.com}"
DISPLAY_NAME="${DEMO_DISPLAY_NAME:-Aria Demo}"
OUT="${OUT_DIR:-docs/phase-1-screenshots}"

echo "→ verifying dev server at ${URL}"
if ! curl -sSf -o /dev/null -m 5 "${URL}"; then
  echo "✗ no dev server at ${URL}. Start it with: just dev" >&2
  exit 1
fi

echo "→ seeding demo data"
mix phase1.demo.seed --email "${EMAIL}" --display-name "${DISPLAY_NAME}"

echo "→ capturing screenshots into ${OUT}"
python3 scripts/screenshots-phase1.py \
  --url "${URL}" \
  --email "${EMAIL}" \
  --display-name "${DISPLAY_NAME}" \
  --out "${OUT}"

echo "✓ screenshots ready in ${OUT}/"
ls -1 "${OUT}"
