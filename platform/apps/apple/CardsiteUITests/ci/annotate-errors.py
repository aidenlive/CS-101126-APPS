#!/usr/bin/env python3
"""Turn the `error:` lines of an xcodebuild or `swift build/test` log into
GitHub Actions annotations, so a failure is readable from the check run
without opening the raw log.

    annotate-errors.py <log> [max-lines]

- Prints the first `max-lines` (default 200) distinct error lines.
- GitHub shows at most 10 error annotations per step, so the first few
  located errors (file:line:col) become `::error file=…,line=…,col=…::`
  annotations and the rest are packed into a few multi-line annotations.
- Appends the same list to the job summary when $GITHUB_STEP_SUMMARY is set.

Always exits 0; the calling step decides whether the job fails.
"""
import os
import re
import sys

LOCATED = re.compile(r"^(?P<file>/[^:\n]+):(?P<line>\d+):(?:(?P<col>\d+):)?\s*(?:fatal )?error:\s*(?P<msg>.*)$")
ANY_ERROR = re.compile(r"(^|\s)(?:fatal )?error:\s")
LOCATED_ANNOTATIONS = 4
PACKED_ANNOTATIONS = 5
LINES_PER_PACK = 40
MAX_LINE = 400


def escape_data(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_property(text: str) -> str:
    return escape_data(text).replace(":", "%3A").replace(",", "%2C")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: annotate-errors.py <log> [max-lines]", file=sys.stderr)
        return 0
    path = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    root = os.environ.get("GITHUB_WORKSPACE", "").rstrip("/")

    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            raw = handle.read().splitlines()
    except OSError as error:
        print(f"::warning::Couldn't read {path}: {error}")
        return 0

    seen = set()
    errors = []
    for line in raw:
        line = line.rstrip()
        if not ANY_ERROR.search(line) or line in seen:
            continue
        seen.add(line)
        errors.append(line[:MAX_LINE])
        if len(errors) >= limit:
            break

    if not errors:
        print(f"No error: lines in {path}.")
        return 0

    def relative(file: str) -> str:
        if root and file.startswith(root + "/"):
            return file[len(root) + 1:]
        return file

    print(f"::group::First {len(errors)} error lines in {os.path.basename(path)}")
    for line in errors:
        print(line)
    print("::endgroup::")

    located = [m for m in (LOCATED.match(line) for line in errors) if m]
    for match in located[:LOCATED_ANNOTATIONS]:
        props = [f"file={escape_property(relative(match['file']))}", f"line={match['line']}"]
        if match["col"]:
            props.append(f"col={match['col']}")
        print(f"::error {','.join(props)}::{escape_data(match['msg'])}")

    packed = [
        (lambda m: f"{relative(m['file'])}:{m['line']}: {m['msg']}" if m else line)(LOCATED.match(line))
        for line in errors
    ]
    for index in range(PACKED_ANNOTATIONS):
        chunk = packed[index * LINES_PER_PACK:(index + 1) * LINES_PER_PACK]
        if not chunk:
            break
        first = index * LINES_PER_PACK + 1
        title = f"errors {first}-{first + len(chunk) - 1} of {len(errors)} ({os.path.basename(path)})"
        print(f"::error title={escape_property(title)}::{escape_data(chr(10).join(chunk))}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"### First {len(errors)} error lines ({os.path.basename(path)})\n\n```\n")
            handle.write("\n".join(packed))
            handle.write("\n```\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
