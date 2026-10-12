#!/usr/bin/env python3
"""Pick an available iOS simulator for the screenshot run.

    pick-simulator.py "<preferred name>" "<fallback regex>"

Tries the preferred name on the newest iOS runtime first, then any device
whose name matches the regex (newest runtime first). Prints
`udid=…` and `name=…` lines for $GITHUB_OUTPUT. Exits 1 with the list of
available devices when nothing matches.
"""
import json
import re
import subprocess
import sys


def runtime_version(key: str) -> tuple:
    # com.apple.CoreSimulator.SimRuntime.iOS-26-0 -> (26, 0)
    match = re.search(r"iOS-(\d+)(?:-(\d+))?(?:-(\d+))?", key)
    return tuple(int(part or 0) for part in match.groups()) if match else (0,)


def main() -> int:
    preferred = sys.argv[1] if len(sys.argv) > 1 else ""
    pattern = re.compile(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else None
    listing = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    runtimes = sorted((key for key in listing["devices"] if ".iOS-" in key), key=runtime_version, reverse=True)

    candidates = []
    for key in runtimes:
        for device in listing["devices"][key]:
            if device.get("isAvailable", True):
                candidates.append((key, device))

    chosen = next((d for _, d in candidates if d["name"] == preferred), None)
    if chosen is None and pattern:
        chosen = next((d for _, d in candidates if pattern.search(d["name"])), None)
    if chosen is None:
        print(f"No simulator named {preferred!r} or matching {pattern.pattern if pattern else None!r}. Available:", file=sys.stderr)
        for key, device in candidates:
            print(f"  {device['name']}  ({key.rsplit('.', 1)[-1]})", file=sys.stderr)
        return 1
    print(f"udid={chosen['udid']}")
    print(f"name={chosen['name']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
