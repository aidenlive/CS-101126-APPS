#!/usr/bin/env bash
# Copies the bodies captured by ContractTests/native-contract.sh into the
# CardsiteKit test bundle, so the Swift decoding tests run against what a
# live API actually returned. Run after re-capturing; `--check` fails if
# the two copies differ (use in CI).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/ContractTests/fixtures"
dst="$here/Packages/CardsiteKit/Tests/CardsiteKitTests/Fixtures"
if [[ "${1:-}" == "--check" ]]; then
  diff -r "$src" "$dst" && echo "fixtures in sync"
  exit $?
fi
mkdir -p "$dst"
rm -f "$dst"/*.json
cp "$src"/*.json "$dst"/
echo "copied $(ls "$dst" | wc -l | tr -d ' ') fixtures"
