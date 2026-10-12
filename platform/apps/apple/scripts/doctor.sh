#!/usr/bin/env bash
# Checks that everything the Xcode project points at is on disk, before
# `xcodegen generate`. "Missing package product" in Xcode almost always means
# one of these paths is absent: the app needs the repository around it, not
# just platform/apps/apple.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
ok=1
check() {
  if [[ -e "$here/$1" ]]; then echo "ok       $1"; else echo "MISSING  $1  — $2"; ok=0; fi
}
check "Packages/CardsiteKit/Package.swift" "CardsiteKit package"
check "../../studio/packages/swift/Package.swift" "StudioKit (platform/studio/packages/swift): unzip the full CSxFINAL-main, or the Swift bundle, so this path exists"
check "../../studio/packages/swift/Sources/StudioKit/Resources/Fonts" "StudioKit fonts"
check "Cardsite/Supporting/Info.plist" "Info.plist"
check "Cardsite/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" "app icon"
if command -v xcodegen >/dev/null; then echo "ok       xcodegen $(xcodegen --version 2>/dev/null | tail -1)"; else echo "MISSING  xcodegen — brew install xcodegen"; ok=0; fi
if command -v xcodebuild >/dev/null; then echo "ok       $(xcodebuild -version | head -1)"; else echo "MISSING  Xcode 26 or later"; ok=0; fi
if [[ -e "$here/../../Makefile" ]]; then
  echo "ok       platform/Makefile (local API: make -C ../.. up)"
else
  echo "note     platform/Makefile absent — the app builds, but there's no local API to sign in against"
fi
[[ $ok == 1 ]] && echo "ready: xcodegen generate && open Cardsite.xcodeproj" || exit 1
