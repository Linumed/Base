#!/usr/bin/env bash
# Renders every docs/diagrams/*.mmd to docs/img/*.svg (issue #65).
#
# Why pre-render instead of letting the browser do it: the diagrams appear on three
# surfaces - the MkDocs site, GitHub and Forgejo - and each has its own Mermaid theme.
# Styling only ever reached the first of the three, so a themed diagram looked like a
# different diagram depending on where it was read. A committed SVG looks the same
# everywhere and needs no JavaScript at all, which also removed the vendored
# mermaid.min.js and the class-name workaround that existed purely to stop Material
# from pulling its renderer off unpkg.com at runtime.
#
# The .mmd files are the source; the SVGs are build output that happens to be committed.
# Edit the .mmd, run this, commit both. CI re-runs this and fails on any difference, so
# a stale SVG cannot ship (see .forgejo/workflows/docs-site.yml) - the same class of
# silent drift as #48 and #63, and worth guarding for the same reason.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${REPO_ROOT}/docs/diagrams"
OUT_DIR="${REPO_ROOT}/docs/img"

# Pinned: mermaid's layout engine changes between releases, and an unpinned renderer
# would produce a different SVG for an unchanged source - which the CI drift check would
# then report as a failure nobody caused.
MERMAID_CLI_VERSION="11.4.2"

# Trap worth knowing before editing a .mmd: a line containing nothing but `%%` is a parse
# error ("Expecting 'NEWLINE', 'SPACE', 'GRAPH', got 'NODE_STRING'" pointing at line 1,
# which is not where the problem is). A comment line needs at least one character after
# the marker - the sources here use `%% -` as the blank separator.

# Puppeteer's Chromium is large and must not land in /tmp: that is a tmpfs on the
# machine this repo is developed on, so a download there competes with real memory.
export PUPPETEER_CACHE_DIR="${PUPPETEER_CACHE_DIR:-/var/tmp/puppeteer}"

mkdir -p "${OUT_DIR}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/var/tmp}/linumed-diagrams.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

# The palette is the site's own teal (mkdocs.yml theme.palette primary: teal) so the
# figures read as part of the documentation rather than as stock Mermaid output.
#
# A deliberate, documented trade-off: an SVG carries fixed colours and cannot follow the
# site's light/dark toggle the way the old runtime rendering did. These render as a light
# card, which stays legible on both backgrounds. "Identical on all three surfaces" was
# the point of pre-rendering, and a card that ignores the toggle is the price.
cat > "${WORK_DIR}/config.json" <<'JSON'
{
  "theme": "base",
  "themeVariables": {
    "primaryColor": "#e0f2f1",
    "primaryTextColor": "#0f2b2a",
    "primaryBorderColor": "#00897b",
    "lineColor": "#4d7a75",
    "secondaryColor": "#b2dfdb",
    "tertiaryColor": "#ffffff",
    "clusterBkg": "#f3fbfa",
    "clusterBorder": "#4d7a75",
    "fontFamily": "-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
  },
  "flowchart": { "curve": "basis", "useMaxWidth": true }
}
JSON

# --no-sandbox: the CI runner executes as root inside a container, where Chromium's
# sandbox cannot initialise. The input is this repository's own diagram sources, not
# untrusted content.
cat > "${WORK_DIR}/puppeteer.json" <<'JSON'
{ "args": ["--no-sandbox", "--disable-gpu"] }
JSON

shopt -s nullglob
sources=("${SRC_DIR}"/*.mmd)
if [ ${#sources[@]} -eq 0 ]; then
  echo "No diagram sources in ${SRC_DIR}" >&2
  exit 1
fi

for src in "${sources[@]}"; do
  name="$(basename "${src}" .mmd)"
  echo "==> ${name}"
  npx -y "@mermaid-js/mermaid-cli@${MERMAID_CLI_VERSION}" \
    --input "${src}" \
    --output "${OUT_DIR}/${name}.svg" \
    --configFile "${WORK_DIR}/config.json" \
    --puppeteerConfigFile "${WORK_DIR}/puppeteer.json" \
    --backgroundColor "#ffffff" \
    --width 1400 \
    >/dev/null
done

echo "==> Rendered ${#sources[@]} diagram(s) to docs/img/"
