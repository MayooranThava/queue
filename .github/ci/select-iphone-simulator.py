#!/usr/bin/env python3
"""Print an xcodebuild -destination value for an available iPhone simulator.

Stdout is only the destination string. The chosen device name is written to
stderr so command substitution stays a single argument.
"""

from __future__ import annotations

import json
import subprocess
import sys
from typing import Any


def parse_ios_version(runtime: str) -> tuple[int, ...] | None:
    marker = "iOS-"
    index = runtime.find(marker)
    if index < 0:
        return None
    parts: list[int] = []
    for piece in runtime[index + len(marker) :].split("-"):
        if not piece.isdigit():
            break
        parts.append(int(piece))
    return tuple(parts) if parts else None


def preference(name: str) -> int:
    """Lower is a better default. Prefer a plain iPhone over Pro, Air, or SE."""
    lowered = name.lower()
    if "se" in lowered:
        return 3
    if "air" in lowered or name.endswith("e"):
        return 2
    if "pro" in lowered:
        return 1
    return 0


def select_device(data: dict[str, Any]) -> tuple[str, str, str]:
    candidates: list[tuple[tuple[int, ...], int, int, str, str, str]] = []
    for runtime, devices in data.get("devices", {}).items():
        version = parse_ios_version(runtime)
        if version is None:
            continue
        for device in devices:
            if device.get("isAvailable", True) is False:
                continue
            name = device.get("name") or ""
            udid = device.get("udid") or ""
            if not name.startswith("iPhone") or not udid:
                continue
            candidates.append(
                (version, -preference(name), -len(name), name, runtime, udid)
            )
    if not candidates:
        raise SystemExit("No available iPhone simulators")
    _version, _preference, _length, name, runtime, udid = max(candidates)
    return name, runtime, udid


def destination_for(data: dict[str, Any]) -> str:
    name, runtime, udid = select_device(data)
    print(f"{name} ({runtime})", file=sys.stderr)
    return f"platform=iOS Simulator,id={udid}"


def load_simctl() -> dict[str, Any]:
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as handle:
            return json.load(handle)
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        text=True,
    )
    return json.loads(raw)


def main() -> None:
    try:
        data = load_simctl()
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"Could not list simulators: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    print(destination_for(data))


if __name__ == "__main__":
    main()
