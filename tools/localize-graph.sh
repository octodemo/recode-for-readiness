#!/usr/bin/env bash
#
# Make graphify's graph.html safe to open on stage.
#
# Graphify writes a genuinely nice interactive graph to graphify-out/graph.html,
# but it loads its rendering library from a CDN:
#
#   <script src="https://unpkg.com/vis-network@9.1.6/..." integrity="sha384-...">
#
# Three problems with that, in order of how badly they end the demo:
#
#   1. Beat 2's entire argument is that comprehension happens in-boundary with
#      no network. Showing a picture that just phoned a CDN to render undercuts
#      the claim in front of exactly the audience that will notice.
#   2. Conference wifi. A blank white rectangle on the projector.
#   3. It cannot be shown at all in --airplane mode, which is the strongest
#      version of the beat.
#
# So: vendor the library once, verify it against the Subresource Integrity hash
# graphify itself published, and inline it into the page. The result is a
# single self-contained file that renders identically with the network
# physically off.
#
# Idempotent. Safe to run after every graph rebuild, and it is.
set -euo pipefail

cd "$(dirname "$0")/.."

GRAPH_HTML="${1:-legacy/graphify-out/graph.html}"
VENDOR="demo/vendor/vis-network.min.js"

# The SRI hash graphify puts in its own <script> tag. We check the vendored copy
# against it rather than trusting the bytes we happened to download. If upstream
# graphify bumps the library version this will fail loudly, which is the point.
VIS_URL="https://unpkg.com/vis-network@9.1.6/standalone/umd/vis-network.min.js"
VIS_SRI="Ux6phic9PEHJ38YtrijhkzyJ8yQlH8i/+buBR8s3mAZOJrP1gwyvAcIYl3GWtpX1"

if [[ ! -f "$GRAPH_HTML" ]]; then
  echo "localize-graph: $GRAPH_HTML not found -- run 'make graph' first" >&2
  exit 1
fi

# Already inlined by a previous run? Nothing to do.
if ! grep -q "unpkg.com" "$GRAPH_HTML"; then
  if grep -qE 'src="https?://|href="https?://' "$GRAPH_HTML"; then
    echo "localize-graph: unexpected external reference survived:" >&2
    grep -oE 'https?://[^"]+' "$GRAPH_HTML" | sort -u | sed 's/^/  /' >&2
    exit 1
  fi
  echo "  graph.html already self-contained"
  exit 0
fi

verify() {
  local got
  got="$(openssl dgst -sha384 -binary "$1" | openssl base64 -A)"
  [[ "$got" == "$VIS_SRI" ]]
}

if [[ ! -f "$VENDOR" ]]; then
  echo "  vendoring vis-network (one time, needs network)..."
  mkdir -p "$(dirname "$VENDOR")"
  if ! curl -sSL --max-time 60 -o "$VENDOR.tmp" "$VIS_URL"; then
    rm -f "$VENDOR.tmp"
    echo "localize-graph: could not download vis-network, and no vendored copy" >&2
    echo "  exists. Run this once with a network, then commit $VENDOR." >&2
    exit 1
  fi
  mv "$VENDOR.tmp" "$VENDOR"
fi

if ! verify "$VENDOR"; then
  echo "localize-graph: $VENDOR does not match the SRI hash graphify published." >&2
  echo "  Refusing to inline it. Delete it and re-run to fetch a clean copy." >&2
  exit 1
fi

python3 - "$GRAPH_HTML" "$VENDOR" <<'PY'
import re
import sys

html_path, vendor_path = sys.argv[1], sys.argv[2]

with open(html_path, encoding="utf-8") as fh:
    html = fh.read()
with open(vendor_path, encoding="utf-8") as fh:
    js = fh.read()

# Match the whole <script ...unpkg...></script> element, attributes and all.
pattern = re.compile(
    r'<script\b[^>]*\bsrc="https://unpkg\.com/[^"]*"[^>]*>\s*</script>',
    re.IGNORECASE,
)
if not pattern.search(html):
    sys.exit("localize-graph: could not find the unpkg <script> element")

# Verified above against the hash graphify shipped, so no integrity attribute is
# needed -- and an SRI attribute on an inline script is meaningless anyway.
banner = (
    "<!-- vis-network 9.1.6 (MIT), vendored from unpkg and verified against the\n"
    "     SRI hash graphify publishes, then inlined so this page renders with\n"
    "     the network physically off. See tools/localize-graph.sh. -->"
)
html = pattern.sub(lambda _: banner + "\n<script>\n" + js + "\n</script>", html, count=1)

with open(html_path, "w", encoding="utf-8") as fh:
    fh.write(html)
PY

if grep -qE 'src="https?://|href="https?://' "$GRAPH_HTML"; then
  echo "localize-graph: an external reference survived:" >&2
  grep -oE 'https?://[^"]+' "$GRAPH_HTML" | sort -u | sed 's/^/  /' >&2
  exit 1
fi

echo "  graph.html inlined -- renders with the network off ($(du -h "$GRAPH_HTML" | cut -f1))"
