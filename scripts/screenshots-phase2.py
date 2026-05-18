#!/usr/bin/env python3
"""
Capture Phase 2 InboxLive screenshots against a running dev server.

Usage:
    python3 scripts/screenshots-phase2.py \
        --url http://localhost:4000 \
        --email demo-admin@example.com \
        --display-name "Aria Demo" \
        --out docs/phase-2-screenshots
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

from playwright.sync_api import Page, TimeoutError as PWTimeout, sync_playwright


def parse_args() -> argparse.Namespace:
  p = argparse.ArgumentParser(description=__doc__)
  p.add_argument("--url", default="http://localhost:4000")
  p.add_argument("--email", default="demo-admin@example.com")
  p.add_argument("--display-name", default="Aria Demo")
  p.add_argument("--out", default="docs/phase-2-screenshots")
  p.add_argument("--viewport-width", type=int, default=1280)
  p.add_argument("--viewport-height", type=int, default=900)
  return p.parse_args()


def request_magic_link(page: Page, base_url: str, email: str) -> None:
  page.goto(urljoin(base_url, "/sign-in"))
  csrf = page.locator("meta[name='csrf-token']").get_attribute("content")
  if not csrf:
    raise RuntimeError("csrf-token meta tag missing on /sign-in")

  response = page.request.post(
    urljoin(base_url, "/auth/user/magic_link/request"),
    form={"_csrf_token": csrf, "user[email]": email},
    headers={"x-csrf-token": csrf},
  )
  if response.status >= 400:
    raise RuntimeError(f"magic-link request failed: {response.status} {response.text()}")


def extract_magic_link_url(page: Page, base_url: str) -> str:
  page.goto(urljoin(base_url, "/dev/mailbox"))
  page.wait_for_load_state("domcontentloaded")
  # The Swoosh mailbox preview iframe loads asynchronously; give it a moment.
  page.wait_for_selector("body", state="attached")
  body = page.content()
  matches = re.findall(r"https?://[^\s\"<]+/magic_link/[A-Za-z0-9._\-]+", body)
  if not matches:
    raise RuntimeError("no magic-link URL found in /dev/mailbox")
  return matches[-1]


def sign_in(page: Page, base_url: str, email: str) -> None:
  request_magic_link(page, base_url, email)
  href = extract_magic_link_url(page, base_url)
  # MagicSignInLive is a LiveView with a long-running WebSocket; "networkidle"
  # never fires. Wait for the token input element instead — it's hidden in
  # the form but Playwright can still locate it.
  page.goto(href)
  page.wait_for_selector("input[name='user[token]']", state="attached", timeout=10_000)

  token_input = page.locator("input[name='user[token]']").first
  if token_input.count() > 0:
    token = token_input.get_attribute("value")
    csrf = page.locator("input[name='_csrf_token']").first.get_attribute("value")
    if not token or not csrf:
      raise RuntimeError("magic-link confirmation form missing token/csrf")
    response = page.request.post(
      urljoin(base_url, "/auth/user/magic_link"),
      form={"_csrf_token": csrf, "user[token]": token},
      headers={"x-csrf-token": csrf},
    )
    if response.status >= 400:
      raise RuntimeError(f"magic-link confirm failed: {response.status} {response.text()}")
    page.goto(urljoin(base_url, "/"))
    page.wait_for_load_state("domcontentloaded")


def shot(page: Page, out_dir: Path, name: str) -> None:
  out_dir.mkdir(parents=True, exist_ok=True)
  target = out_dir / name
  page.screenshot(path=str(target), full_page=True)
  print(f"  wrote {target}")


def open_latest_inbox(page: Page, base_url: str, summary_suffix: str, status: str) -> None:
  page.goto(urljoin(base_url, f"/inbox?status={status}"))
  page.wait_for_selector("[data-role='inbox-list']", state="visible")
  row = page.locator(f"li:has-text('{summary_suffix}')").first
  row.locator("[data-role='inbox-view']").click()
  page.wait_for_selector("[data-role='inbox-chain']", state="visible")


def main() -> int:
  args = parse_args()
  out_dir = Path(args.out)

  with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=True)
    context = browser.new_context(
      viewport={"width": args.viewport_width, "height": args.viewport_height},
      device_scale_factor=1,
    )
    page = context.new_page()

    try:
      sign_in(page, args.url, args.email)
      open_latest_inbox(page, args.url, "(open)", "open")

      shot(page, out_dir, "01-inbox-open.png")

      open_latest_inbox(page, args.url, "(drafting)", "drafting")
      page.wait_for_selector("[data-role='approve-draft']", state="visible")
      shot(page, out_dir, "02-inbox-drafting.png")

      # LiveView is joined only when the main view element carries the
      # `phx-connected` class. (Not `<body>`: Phoenix LV writes the class
      # to the `[data-phx-main]` element, not the document body.)
      # `liveSocket.isConnected()` is true earlier (raw WS up) but
      # `phx-click` is a no-op until the per-view join completes.
      page.wait_for_function(
        "() => { const m = document.querySelector('[data-phx-main]'); "
        "return m && m.classList.contains('phx-connected'); }",
        timeout=15_000,
      )

      approve = page.locator("[data-role='approve-draft']")
      approve.click()

      try:
        page.wait_for_selector("[data-role='countdown-hint']", state="visible", timeout=10_000)
      except PWTimeout:
        # Surface the rendered chain/flash state so we can see WHY the
        # countdown never appeared.
        print("DEBUG: countdown-hint never appeared. Page snapshot:", flush=True)
        print(page.locator("[data-role='draft-section']").inner_html()[:600], flush=True)
        flash_html = page.locator("#flash-group").inner_html()[:300]
        print(f"DEBUG flash: {flash_html}", flush=True)
        raise
      # Capture in-flight countdown around mid-window to avoid edge race at 0s.
      time.sleep(2.5)
      shot(page, out_dir, "03-inbox-countdown.png")

      # Server execute is scheduled at 5s after approval; add small buffer.
      time.sleep(3.2)
      page.wait_for_timeout(400)
      shot(page, out_dir, "04-inbox-executed.png")
    except PWTimeout as e:
      print(f"timeout: {e}", file=sys.stderr)
      out_dir.mkdir(parents=True, exist_ok=True)
      page.screenshot(path=str(out_dir / "_failure.png"), full_page=True)
      return 2
    finally:
      context.close()
      browser.close()

  return 0


if __name__ == "__main__":
  sys.exit(main())
