#!/usr/bin/env python3
"""Rewrite the checkout's Xcode project for ad-hoc iOS Simulator signing.

The committed project keeps Automatic signing and the development team so
local devices work. GitHub-hosted runners have no Apple certificate, and the
App Group entitlement cannot be ad-hoc signed. This only changes the runner
working copy: Manual signing, ad-hoc identity, and an empty entitlements file.
"""

from __future__ import annotations

from pathlib import Path

EMPTY_ENTITLEMENTS = ".github/ci/Empty.entitlements"
ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "Queue.xcodeproj" / "project.pbxproj"

DROP_PREFIXES = (
    "DEVELOPMENT_TEAM ",
    "CODE_SIGN_IDENTITY ",
    "CODE_SIGNING_REQUIRED ",
    "CODE_SIGNING_ALLOWED ",
    "PROVISIONING_PROFILE",
)


def rewrite(text: str) -> str:
    rewritten: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith(DROP_PREFIXES):
            continue
        if stripped.startswith("CODE_SIGN_STYLE "):
            indent = line[: len(line) - len(line.lstrip())]
            rewritten.append(f"{indent}CODE_SIGN_STYLE = Manual;\n")
            rewritten.append(f'{indent}CODE_SIGN_IDENTITY = "-";\n')
            rewritten.append(f"{indent}CODE_SIGNING_REQUIRED = YES;\n")
            rewritten.append(f"{indent}CODE_SIGNING_ALLOWED = YES;\n")
            continue
        if stripped.startswith("CODE_SIGN_ENTITLEMENTS "):
            indent = line[: len(line) - len(line.lstrip())]
            rewritten.append(f"{indent}CODE_SIGN_ENTITLEMENTS = {EMPTY_ENTITLEMENTS};\n")
            continue
        rewritten.append(line)
    return "".join(rewritten)


def main() -> None:
    original = PROJECT.read_text()
    updated = rewrite(original)
    if updated.count("{") != updated.count("}"):
        raise SystemExit("Refusing to write project.pbxproj: brace count changed")
    PROJECT.write_text(updated)
    print(f"Prepared ad-hoc simulator signing in {PROJECT}")


if __name__ == "__main__":
    main()
