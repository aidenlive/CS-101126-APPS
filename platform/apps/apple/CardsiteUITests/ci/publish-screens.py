#!/usr/bin/env python3
"""Commit a run's screenshots to the orphan `screens` branch.

    publish-screens.py <dir-with-one-folder-per-device>

Layout on the branch:

    index.md                 every kept run, newest first
    runs.txt                 the same list, machine-readable
    runs/<sha>/index.md      that run's screens as a grid (screen x variant)
    runs/<sha>/<device>/…    the PNGs, e.g. ios-iphone17promax-dark-default-links.png

The branch is rewritten as a single parentless commit holding the newest
KEEP_RUNS runs (default 10), so it does not grow without bound. The session
reads it with git, which works through its proxy where artifact downloads
do not.

Needs GITHUB_TOKEN (contents: write), GITHUB_REPOSITORY and GITHUB_SHA;
optional GITHUB_REF_NAME, GITHUB_RUN_ID, GITHUB_SERVER_URL, KEEP_RUNS, and
SCREENS_REMOTE (a different remote, for trying this locally).
"""
import datetime
import os
import re
import shutil
import subprocess
import sys
import tempfile

NAME = re.compile(r"^(?P<platform>ios|ipados|macos)-(?P<device>[a-z0-9]+)-(?P<appearance>[a-z]+)-(?P<text>[a-z0-9]+)-(?P<screen>.+)\.png$")
VARIANTS = [("light", "default"), ("dark", "default"), ("light", "ax5")]


def git(*args: str, cwd: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=cwd, check=check, text=True, capture_output=True)


def run_index(sha: str, run_dir: str, meta: dict) -> str:
    lines = [f"# Screens for {sha[:12]}", ""]
    lines.append(f"- Commit: [{sha[:12]}]({meta['server']}/{meta['repo']}/commit/{sha})")
    if meta["ref"]:
        lines.append(f"- Ref: `{meta['ref']}`")
    if meta["run"]:
        lines.append(f"- Workflow run: [{meta['run']}]({meta['server']}/{meta['repo']}/actions/runs/{meta['run']})")
    lines.append(f"- Captured: {meta['date']}")
    lines.append("")

    for device in sorted(os.listdir(run_dir)):
        folder = os.path.join(run_dir, device)
        if not os.path.isdir(folder):
            continue
        shots = {}
        others = []
        for name in sorted(os.listdir(folder)):
            match = NAME.match(name)
            if match:
                key = (match["appearance"], match["text"])
                shots.setdefault(match["screen"], {})[key] = name
            elif os.path.isfile(os.path.join(folder, name)):
                others.append(name)
        lines.append(f"## {device}")
        lines.append("")
        if shots:
            lines.append("| Screen | " + " | ".join(f"{a} / {t}" for a, t in VARIANTS) + " |")
            lines.append("|---|" + "---|" * len(VARIANTS))
            for screen in sorted(shots):
                cells = []
                for variant in VARIANTS:
                    file = shots[screen].get(variant)
                    cells.append(f'<a href="{device}/{file}"><img src="{device}/{file}" width="200"></a>' if file else "–")
                lines.append(f"| `{screen}` | " + " | ".join(cells) + " |")
            lines.append("")
            lines.append("Files:")
            lines.append("")
            for screen in sorted(shots):
                for file in sorted(shots[screen].values()):
                    lines.append(f"- [{file}]({device}/{file})")
            lines.append("")
        failures = os.path.join(folder, "failures")
        if os.path.isdir(failures):
            lines.append("Failure attachments:")
            lines.append("")
            for name in sorted(os.listdir(failures)):
                lines.append(f"- [{name}]({device}/failures/{name})")
            lines.append("")
        for name in others:
            lines.append(f"- [{name}]({device}/{name})")
        if others:
            lines.append("")
    return "\n".join(lines) + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: publish-screens.py <screens-dir>", file=sys.stderr)
        return 2
    source = os.path.abspath(sys.argv[1])
    devices = [d for d in sorted(os.listdir(source)) if os.path.isdir(os.path.join(source, d))] if os.path.isdir(source) else []
    if not devices:
        print("::warning::No screenshots to publish")
        return 0

    token = os.environ["GITHUB_TOKEN"]
    repo = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    keep = int(os.environ.get("KEEP_RUNS", "10"))
    meta = {
        "repo": repo,
        "server": os.environ.get("GITHUB_SERVER_URL", "https://github.com"),
        "ref": os.environ.get("GITHUB_REF_NAME", ""),
        "run": os.environ.get("GITHUB_RUN_ID", ""),
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    }

    work = tempfile.mkdtemp(prefix="screens-")
    git("init", "-q", cwd=work)
    git("config", "user.name", "github-actions[bot]", cwd=work)
    git("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com", cwd=work)
    remote = os.environ.get("SCREENS_REMOTE") or f"https://x-access-token:{token}@github.com/{repo}.git"
    git("remote", "add", "origin", remote, cwd=work)
    if git("fetch", "-q", "--depth", "1", "origin", "screens", cwd=work, check=False).returncode == 0:
        git("checkout", "-q", "FETCH_HEAD", cwd=work)

    # The run list, newest first: "<sha> <date> <ref>".
    runs_file = os.path.join(work, "runs.txt")
    runs = []
    if os.path.exists(runs_file):
        with open(runs_file, encoding="utf-8") as handle:
            runs = [line.strip() for line in handle if line.strip() and not line.startswith(sha + " ")]
    runs.insert(0, f"{sha} {meta['date']} {meta['ref']}".strip())
    runs = runs[:keep]
    kept = {line.split()[0] for line in runs}

    runs_root = os.path.join(work, "runs")
    os.makedirs(runs_root, exist_ok=True)
    for existing in os.listdir(runs_root):
        if existing not in kept:
            shutil.rmtree(os.path.join(runs_root, existing), ignore_errors=True)

    run_dir = os.path.join(runs_root, sha)
    shutil.rmtree(run_dir, ignore_errors=True)
    for device in devices:
        shutil.copytree(os.path.join(source, device), os.path.join(run_dir, device))
    with open(os.path.join(run_dir, "index.md"), "w", encoding="utf-8") as handle:
        handle.write(run_index(sha, run_dir, meta))

    with open(runs_file, "w", encoding="utf-8") as handle:
        handle.write("\n".join(runs) + "\n")
    with open(os.path.join(work, "index.md"), "w", encoding="utf-8") as handle:
        handle.write("# Cardsite Apple screens\n\n")
        handle.write("Written by `.github/workflows/apple.yml` (job `screens-publish`). Newest first; ")
        handle.write(f"the last {keep} runs are kept. See `platform/apps/apple/CardsiteUITests/README.md`.\n\n")
        for line in runs:
            parts = line.split(" ", 3)
            run_sha = parts[0]
            rest = " ".join(parts[1:])
            handle.write(f"- [{run_sha[:12]}](runs/{run_sha}/index.md) {rest}\n")

    # One parentless commit with everything kept.
    git("checkout", "-q", "--orphan", "screens-next", cwd=work)
    git("add", "-A", cwd=work)
    git("commit", "-q", "-m", f"Screens for {sha[:12]} ({meta['ref'] or 'detached'})", cwd=work)
    pushed = git("push", "-q", "--force", "origin", "screens-next:refs/heads/screens", cwd=work, check=False)
    if pushed.returncode != 0:
        print(pushed.stderr.replace(token, "***"), file=sys.stderr)
        return 1
    count = sum(len(files) for _, _, files in os.walk(run_dir))
    print(f"Published {count} files to screens:runs/{sha}/")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"Screens: branch `screens`, folder `runs/{sha}/` ({count} files).\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
