#!/usr/bin/env python3
"""Capture Phase 4/5 screenshots: manuals admin, personas, grounded generation, audit chain."""

from __future__ import annotations
import argparse
import re
import sys
from pathlib import Path
from urllib.parse import urljoin

from playwright.sync_api import Page, TimeoutError as PWTimeout, sync_playwright


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--url", default="http://localhost:4000")
    p.add_argument("--email", default="demo-admin@example.com")
    p.add_argument("--manual-id", required=True)
    p.add_argument("--inbox-a", required=True, help="inbox with a drafting grounded candidate")
    p.add_argument("--inbox-b", required=True, help="inbox driven to :executed")
    p.add_argument("--out", default="docs/phase-5-screenshots")
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
        raise RuntimeError(f"magic-link request failed: {response.status}")


def extract_magic_link_url(page: Page, base_url: str) -> str:
    page.goto(urljoin(base_url, "/dev/mailbox"))
    page.wait_for_load_state("domcontentloaded")
    page.wait_for_selector("body", state="attached")
    body = page.content()
    matches = re.findall(r"https?://[^\s\"<]+/magic_link/[A-Za-z0-9._\-]+", body)
    if not matches:
        raise RuntimeError("no magic-link URL found in /dev/mailbox")
    return matches[-1]


def sign_in(page: Page, base_url: str, email: str) -> None:
    request_magic_link(page, base_url, email)
    href = extract_magic_link_url(page, base_url)
    page.goto(href)
    page.wait_for_selector("input[name='user[token]']", state="attached", timeout=10_000)

    token_input = page.locator("input[name='user[token]']").first
    if token_input.count() > 0:
        token = token_input.get_attribute("value")
        csrf = page.locator("input[name='_csrf_token']").first.get_attribute("value")
        if not token or not csrf:
            raise RuntimeError("magic-link form missing token/csrf")
        response = page.request.post(
            urljoin(base_url, "/auth/user/magic_link"),
            form={"_csrf_token": csrf, "user[token]": token},
            headers={"x-csrf-token": csrf},
        )
        if response.status >= 400:
            raise RuntimeError(f"magic-link confirm failed: {response.status}")
        page.goto(urljoin(base_url, "/"))
        page.wait_for_load_state("domcontentloaded")


def shot(page: Page, out_dir: Path, name: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / name
    page.screenshot(path=str(target), full_page=True)
    print(f"  wrote {target}")


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

            # 1. Manuals index (incl. archived toggle state)
            page.goto(urljoin(args.url, "/manuals"))
            page.wait_for_selector("[data-role='manual-list']", state="visible", timeout=10_000)
            page.locator("[data-role='toggle-archived']").click()
            page.wait_for_selector("[data-role='archived-badge']", state="visible", timeout=10_000)
            shot(page, out_dir, "01-manuals-index.png")

            # 2. Manual edit + version history
            page.goto(urljoin(args.url, f"/manuals/{args.manual_id}/edit"))
            page.wait_for_selector("[data-role='version-history']", state="visible", timeout=10_000)
            page.wait_for_selector("[data-role='version-row']", state="visible", timeout=10_000)
            shot(page, out_dir, "02-manual-edit-version-history.png")

            # 3. Personas index
            page.goto(urljoin(args.url, "/personas"))
            page.wait_for_selector("[data-role='persona-list']", state="visible", timeout=10_000)
            shot(page, out_dir, "03-personas-index.png")

            # 4. Generation panel with validator + retrieval badges
            page.goto(urljoin(args.url, f"/inbox/{args.inbox_a}"))
            page.wait_for_selector("[data-role='generation-panel']", state="visible", timeout=10_000)
            page.wait_for_selector("[data-role='candidate-card']", state="visible", timeout=10_000)
            page.wait_for_selector("[data-role='retrieval-badge']", state="visible", timeout=10_000)
            shot(page, out_dir, "04-inbox-grounded-candidate.png")

            # 5. Audit chain with draft_generation_* events
            page.goto(urljoin(args.url, f"/audit/chain?topic={args.inbox_b}"))
            page.wait_for_selector("[data-role='chain-events']", state="visible", timeout=10_000)
            page.wait_for_selector("[data-role='audit-row']", state="visible", timeout=10_000)
            shot(page, out_dir, "05-audit-chain-generation-events.png")
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
