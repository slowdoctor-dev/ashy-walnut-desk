#!/usr/bin/env bash
# Phase 4/5 manuals + grounded-generation screenshot capture.
#
# Reproducible from `just phase5-screenshots`. Assumes the dev server is up
# (`just dev` in another terminal) and Postgres is running.

set -euo pipefail

URL="${PHX_URL:-http://localhost:4000}"
EMAIL="${DEMO_EMAIL:-demo-admin@example.com}"
OUT="${OUT_DIR:-docs/phase-5-screenshots}"

echo "→ verifying dev server at ${URL}"
if ! curl -sSf -o /dev/null -m 5 "${URL}"; then
  echo "✗ no dev server at ${URL}. Start it with: just dev" >&2
  exit 1
fi

echo "→ seeding phase 5 demo data"
SEED_OUT=$(mix phase5.demo.seed --email "${EMAIL}")
echo "${SEED_OUT}"

MANUAL_ID=$(echo "${SEED_OUT}" | sed -n 's/^MANUAL_ID=//p' | tail -1)
INBOX_A=$(echo "${SEED_OUT}" | sed -n 's/^INBOX_A=//p' | tail -1)
INBOX_B=$(echo "${SEED_OUT}" | sed -n 's/^INBOX_B=//p' | tail -1)

if [ -z "${MANUAL_ID}" ] || [ -z "${INBOX_A}" ] || [ -z "${INBOX_B}" ]; then
  echo "✗ seed output missing MANUAL_ID/INBOX_A/INBOX_B" >&2
  exit 1
fi

echo "→ capturing phase 5 screenshots into ${OUT}"
python3 scripts/screenshots-phase5.py \
  --url "${URL}" \
  --email "${EMAIL}" \
  --manual-id "${MANUAL_ID}" \
  --inbox-a "${INBOX_A}" \
  --inbox-b "${INBOX_B}" \
  --out "${OUT}"

echo "✓ screenshots ready in ${OUT}/"
ls -1 "${OUT}"
