#!/usr/bin/env bash
# lint-design.sh: the Studio design bar, enforced.
#
# Fails, printing file:line for each hit, when app code under Cardsite/
# carries a design literal instead of a StudioKit token:
#
#   colour     Color(red:/hue:/white:/.sRGB …), Color(hex…), Color("asset"),
#              #colorLiteral, UIColor(red…)/NSColor(red…), and named system
#              colours (.red, Color.blue, UIColor.systemGreen …). Allowed:
#              .primary, .secondary, .accentColor, .clear.
#   padding    a numeric literal in .padding(…) or EdgeInsets(…), other than 0
#   spacing    a numeric literal after spacing:, other than 0
#   radius     a numeric literal after cornerRadius: or in .cornerRadius(…), other than 0
#   font       .system(size: …), i.e. .font(.system(size:)) or Font.system(size:)
#
# Use Color.studio*, StudioSpace.*, StudioRadius.*, StudioLayout.* and
# .studioText(…) instead. For a chart use Color.studioViz1…6.
#
# Allow-listed: anything inside a #Preview { … } block or a PreviewProvider
# type, comments, and the contents of string literals. A line that renders
# USER data (a colour the user picked for their bio page, say) rather than
# app design can opt out with a trailing reason the reviewer can judge:
#
#     return Color(.sRGB, red: r, green: g, blue: b)  // lint-design: allow user colour
#
# Usage: scripts/lint-design.sh [file-or-dir …]   (default: Cardsite/)
# Exit:  0 clean, 1 violations, 2 usage error.
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -eq 0 ]]; then
  set -- "$here/Cardsite"
fi

files=()
for target in "$@"; do
  if [[ -d "$target" ]]; then
    while IFS= read -r -d '' f; do files+=("$f"); done \
      < <(find "$target" -type f -name '*.swift' -print0 | sort -z)
  elif [[ -f "$target" ]]; then
    files+=("$target")
  else
    echo "lint-design: no such file or directory: $target" >&2
    exit 2
  fi
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "lint-design: no Swift files found" >&2
  exit 0
fi

# Print paths relative to the app directory when they are inside it.
awk -v root="$here/" '
function rel(path) { return index(path, root) == 1 ? substr(path, length(root) + 1) : path }

function report(rule, what) {
  printf "%s:%d: %s: %s\n", rel(FILENAME), FNR, rule, what
  count[rule]++
  total++
}

# Every numeric literal captured by `re` (whose match ends in the number)
# that is not zero is reported once per occurrence.
function numeric(code, re, rule, label,    s, m, n) {
  s = code
  while (match(s, re)) {
    m = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    if (match(m, /-?[0-9]*\.?[0-9]+$/)) {
      n = substr(m, RSTART, RLENGTH)
      if (n + 0 != 0) report(rule, "literal " n " in " label)
    }
  }
}

function braces(s,    t, opens, closes) {
  t = s
  opens = gsub(/\{/, "", t)
  t = s
  closes = gsub(/\}/, "", t)
  return opens - closes
}

FNR == 1 { inBlockComment = 0; inPreview = 0; depth = 0; opened = 0 }

{
  code = $0

  # Block comments, including ones that span lines.
  if (inBlockComment) {
    if (match(code, /\*\//)) { code = substr(code, RSTART + 2); inBlockComment = 0 }
    else next
  }
  while (match(code, /\/\*/)) {
    pre = substr(code, 1, RSTART - 1)
    rest = substr(code, RSTART + 2)
    if (match(rest, /\*\//)) { code = pre " " substr(rest, RSTART + 2) }
    else { code = pre; inBlockComment = 1; break }
  }

  # String literals (contents can never be a design literal), then line
  # comments. Escaped quotes are handled; raw and multi-line strings are rare
  # enough in view code to accept the approximation.
  gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
  sub(/(^|[ \t])\/\/.*$/, "", code)

  # Explicit, reasoned opt-out for lines that render user data. A bare
  # "lint-design: allow" with no reason does not count.
  if ($0 ~ /\/\/[ \t]*lint-design:[ \t]*allow[ \t]+[^ \t]/) next

  # Allow-list: #Preview blocks and PreviewProvider types.
  if (!inPreview && (code ~ /^[ \t]*#Preview/ || code ~ /:[ \t]*PreviewProvider/)) {
    inPreview = 1; depth = 0; opened = 0
  }
  if (inPreview) {
    d = braces(code)
    depth += d
    if (code ~ /\{/) opened = 1
    if (opened && depth <= 0) inPreview = 0
    next
  }

  # Colour literals.
  if (code ~ /Color\([ \t]*(red|green|blue|hue|white|hex)[ \t]*:/ || code ~ /Color\([ \t]*hex/ || code ~ /Color\([ \t]*\.(sRGB|displayP3|sRGBLinear)/)
    report("colour", "Color(...) literal")
  if (code ~ /Color\([ \t]*""/)
    report("colour", "asset-catalog Color(\"...\")")
  if (code ~ /#colorLiteral/)
    report("colour", "#colorLiteral")
  if (code ~ /UIColor\([ \t]*(red|white|hue|displayP3Red)[ \t]*:/ || code ~ /NSColor\([ \t]*(red|srgbRed|calibratedRed|deviceRed|white|calibratedWhite|hue|calibratedHue)[ \t]*:/)
    report("colour", "UIColor/NSColor literal")
  if (code ~ /(UIColor|NSColor)\.(system[A-Z][A-Za-z]*|red|orange|yellow|green|cyan|blue|purple|magenta|brown|white|black|gray|darkGray|lightGray|label|secondaryLabel)([^A-Za-z0-9_]|$)/)
    report("colour", "UIColor/NSColor system colour")
  if (code ~ /Color\.(red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|black|gray)([^A-Za-z0-9_]|$)/)
    report("colour", "system colour Color.<name>")
  else if (code ~ /[(,:?][ \t]*\.(red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|black|gray)([^A-Za-z0-9_]|$)/)
    report("colour", "system colour .<name>")

  # Spacing, padding and radius literals (0 is allowed).
  numeric(code, "\\.padding\\([ \t]*-?[0-9]*\\.?[0-9]+", "padding", ".padding(…)")
  numeric(code, "\\.padding\\([ \t]*\\.[A-Za-z]+[ \t]*,[ \t]*-?[0-9]*\\.?[0-9]+", "padding", ".padding(edge, …)")
  numeric(code, "\\.padding\\([ \t]*\\[[^]]*\\][ \t]*,[ \t]*-?[0-9]*\\.?[0-9]+", "padding", ".padding([edges], …)")
  # EdgeInsets: every labelled argument. RSTART/RLENGTH are global and
  # numeric() overwrites them, so take the slice before calling it.
  rest = code
  while (match(rest, /EdgeInsets\([^)]*\)/)) {
    args = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    numeric(args, ":[ \t]*-?[0-9]*\\.?[0-9]+", "padding", "EdgeInsets(…)")
  }
  numeric(code, "spacing:[ \t]*-?[0-9]*\\.?[0-9]+", "spacing", "spacing:")
  numeric(code, "cornerRadius:[ \t]*-?[0-9]*\\.?[0-9]+", "radius", "cornerRadius:")
  numeric(code, "\\.cornerRadius\\([ \t]*-?[0-9]*\\.?[0-9]+", "radius", ".cornerRadius(…)")

  # Font literals.
  if (code ~ /\.system\([ \t]*size[ \t]*:/)
    report("font", ".system(size:) — use .studioText(...)")
}

END {
  if (total > 0) {
    printf "\nlint-design: %d violation(s)", total
    sep = " ("
    for (r in count) { printf "%s%s %d", sep, r, count[r]; sep = ", " }
    printf ")\n"
    exit 1
  }
  print "lint-design: clean"
}
' "${files[@]}"
