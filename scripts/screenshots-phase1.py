#!/usr/bin/env python3
"""
Capture Phase 1 timeline UI screenshots against a running dev server.

Usage:
    python3 scripts/screenshots-phase1.py \
        --url http://localhost:4000 \
        --email demo-admin@example.com \
        --display-name "Aria Demo" \
        --out docs/phase-1-screenshots

Assumes the dev server is already running (`just dev`) and that
`mix phase1.demo.seed` has populated demo data for `--email` /
`--display-name`. The orchestrator at scripts/screenshots-phase1.sh
runs the seed for you.
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
    p.add_argument("--out", default="docs/phase-1-screenshots")
    p.add_argument(
        "--viewport-width",
        type=int,
        default=1280,
        help="Browser viewport width in px (default 1280)",
    )
    p.add_argument(
        "--viewport-height",
        type=int,
        default=900,
        help="Browser viewport height in px (default 900)",
    )
    return p.parse_args()


def request_magic_link(page: Page, base_url: str, email: str) -> None:
    # The /sign-in form is a LiveView component (phx-submit), so a plain
    # form click races the WebSocket connection. POST directly to the
    # form's action endpoint instead — same code path on the server side,
    # no LV timing dance.
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
        raise RuntimeError(
            f"magic-link request failed: {response.status} {response.text()}"
        )


def extract_magic_link_url(page: Page, base_url: str, email: str) -> str:
    """Open /dev/mailbox, return the magic-link URL from the latest message body."""
    # Plug.Swoosh.MailboxPreview redirects /dev/mailbox to a session-keyed
    # path on first visit; auto-selects the only message and renders the
    # text body inline as <div id="text-body-content">. Just regex it out.
    page.goto(urljoin(base_url, "/dev/mailbox"))
    # LV WS keeps the connection open in dev; networkidle never settles.
    page.wait_for_load_state("domcontentloaded")
    body = page.content()
    matches = re.findall(r"https?://[^\s\"<]+/magic_link/[A-Za-z0-9._\-]+", body)
    if not matches:
        raise RuntimeError(f"no magic-link URL in /dev/mailbox for {email}")
    # Return the most recent (last) match.
    return matches[-1]


def sign_in(page: Page, base_url: str, email: str) -> None:
    request_magic_link(page, base_url, email)
    href = extract_magic_link_url(page, base_url, email)
    page.goto(href)
    # MagicSignInLive holds a long-running LV WS; `networkidle` never settles.
    page.wait_for_selector("input[name='user[token]']", state="attached", timeout=10_000)

    # `require_interaction?(true)` on the magic-link strategy means
    # /magic_link/<token> renders a LiveView confirmation form that POSTs
    # to /auth/user/magic_link. Same LV-vs-WS race as the request form,
    # so submit it directly with the token + csrf from the page.
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
            raise RuntimeError(
                f"magic-link confirm failed: {response.status} {response.text()}"
            )
        # The POST set the session cookie on the request context; navigate
        # the page so the browser context picks it up.
        page.goto(urljoin(base_url, "/"))
        page.wait_for_load_state("domcontentloaded")


def shot(page: Page, out_dir: Path, name: str) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / name
    page.screenshot(path=str(target), full_page=True)
    print(f"  wrote {target}")
    return target


def open_show_for_identity(page: Page, base_url: str, display_name: str) -> None:
    page.goto(urljoin(base_url, "/identities"))
    page.wait_for_selector("[data-role='identity-list']", state="visible")
    # The most recent identity with this display name appears first in
    # the list (the seed task appends, the LiveView reads default order).
    page.locator(f"a:has-text('{display_name}')").first.click()
    page.wait_for_selector("[id='identity-timeline']", state="visible")


def expand_record_event(page: Page) -> None:
    section = page.locator("[data-role='record-event-section']").first
    section.wait_for(state="visible")
    if section.get_attribute("open") is None:
        section.locator("summary").click()
    # Wait for the input to be visible after the <details> expands.
    page.wait_for_selector("#event-form input[name='event_form[summary]']", state="visible")


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

            page.goto(urljoin(args.url, "/identities"))
            page.wait_for_selector("[data-role='identity-list']", state="visible")
            shot(page, out_dir, "01-identities-index.png")

            open_show_for_identity(page, args.url, args.display_name)
            shot(page, out_dir, "02-identity-show-timeline.png")

            expand_record_event(page)
            shot(page, out_dir, "03-identity-show-record-event-form.png")
        except PWTimeout as e:
            print(f"timeout: {e}", file=sys.stderr)
            page.screenshot(path=str(out_dir / "_failure.png"), full_page=True)
            return 2
        finally:
            context.close()
            browser.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
