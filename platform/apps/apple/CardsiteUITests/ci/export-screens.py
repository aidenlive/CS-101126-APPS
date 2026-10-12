#!/usr/bin/env python3
"""Export the screenshots attached by CardsiteUITests from an .xcresult.

    export-screens.py <bundle.xcresult> <output-dir>

Runs `xcrun xcresulttool export attachments` (Xcode 16+), then renames each
file from its exported UUID to the attachment's name, e.g.
`ios-iphone17promax-dark-default-links.png`. Screenshots XCTest takes
automatically on a failure go to `failures/`. Prints the files written.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

SUFFIX = re.compile(r"_\d+_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")
SAFE = re.compile(r"[^A-Za-z0-9._-]+")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: export-screens.py <bundle.xcresult> <output-dir>", file=sys.stderr)
        return 2
    bundle, out = sys.argv[1], sys.argv[2]
    if not os.path.isdir(bundle):
        print(f"::warning::No result bundle at {bundle}; nothing to export")
        return 0
    os.makedirs(out, exist_ok=True)
    raw = tempfile.mkdtemp(prefix="attachments-")
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", bundle, "--output-path", raw], check=True)

    manifest_path = os.path.join(raw, "manifest.json")
    entries = []
    if os.path.exists(manifest_path):
        with open(manifest_path, encoding="utf-8") as handle:
            for test in json.load(handle):
                for attachment in test.get("attachments", []):
                    entries.append((test.get("testIdentifier", ""), attachment))
    else:
        entries = [("", {"exportedFileName": name}) for name in os.listdir(raw) if name != "manifest.json"]

    written = []
    used = set()
    for test, attachment in entries:
        exported = attachment.get("exportedFileName")
        if not exported or not os.path.exists(os.path.join(raw, exported)):
            continue
        ext = os.path.splitext(exported)[1] or ".bin"
        human = attachment.get("suggestedHumanReadableName") or exported
        stem = SUFFIX.sub("", os.path.splitext(human)[0])
        stem = SAFE.sub("-", stem).strip("-") or "attachment"
        folder = out
        # Our captures are named <platform>-<device>-…; anything else is
        # XCTest's own (failure screenshots, UI hierarchies).
        if attachment.get("isAssociatedWithFailure") or not re.match(r"^(ios|ipados|macos|missing-identifiers)-", stem):
            folder = os.path.join(out, "failures")
            test_name = SAFE.sub("-", test).strip("-")
            stem = f"{test_name}-{stem}" if test_name else stem
        os.makedirs(folder, exist_ok=True)
        target = os.path.join(folder, stem + ext)
        counter = 2
        while target in used or os.path.exists(target):
            target = os.path.join(folder, f"{stem}-{counter}{ext}")
            counter += 1
        used.add(target)
        shutil.copyfile(os.path.join(raw, exported), target)
        written.append(target)

    shutil.rmtree(raw, ignore_errors=True)
    for path in sorted(written):
        print(path)
    print(f"{len(written)} attachments exported to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
