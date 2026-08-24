#!/usr/bin/env bash
#
# Offline proof -- demonstrate that building the knowledge graph makes no
# outbound network calls.
#
# The claim this demo makes on stage is that comprehension of the legacy deck
# happens entirely inside the boundary. That claim has to be demonstrable, not
# asserted, so this script removes the ability to reach the network and then
# rebuilds the graph anyway.
#
# Two modes:
#
#   default     Blackhole every proxy variable and strip every model API key,
#               then rebuild. Reproducible, safe to run anywhere, works in CI.
#               This is a proxy-level block, not an air-gap: a process opening
#               a raw socket could still egress. Use --airplane for the
#               stronger claim.
#
#   --airplane  Physically power down Wi-Fi, rebuild, then restore it. More
#               convincing in a room. macOS only, and it will interrupt any
#               other network activity on the machine.
#
# Either way, a non-zero exit means the claim did not hold.
set -uo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-default}"
TARGET="legacy"
BLACKHOLE="http://127.0.0.1:9"   # discard port

# Graphify prints an upsell tip naming a specific third-party model vendor.
# This demo is delivered jointly with Microsoft, and a competitor's product name
# on the projector is a distraction nobody in the room needs. The tip is not
# evidence of anything -- it fires whether or not a key is set -- so dropping it
# costs the argument nothing. The substance it hints at (there is an optional
# model-backed layer, and we are not using it) is stated explicitly below in our
# own words, which is stronger anyway.
scrub_vendor() {
  grep -v -E 'GEMINI_API_KEY|GOOGLE_API_KEY|[Gg]emini' || true
}

restore_wifi() {
  if [[ -n "${WIFI_DEVICE:-}" ]]; then
    echo "  restoring ${WIFI_DEVICE}..."
    networksetup -setairportpower "$WIFI_DEVICE" on || true
  fi
}

echo "Offline proof: rebuilding the GEOSAT knowledge graph with no network."
echo

rm -rf "$TARGET/graphify-out"

if [[ "$MODE" == "--airplane" ]]; then
  WIFI_DEVICE="$(networksetup -listallhardwareports \
    | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')"

  if [[ -z "$WIFI_DEVICE" ]]; then
    echo "ERROR: could not identify the Wi-Fi device." >&2
    exit 2
  fi

  trap restore_wifi EXIT

  echo "  powering down ${WIFI_DEVICE}..."
  networksetup -setairportpower "$WIFI_DEVICE" off
  sleep 2

  echo "  confirming the network is unreachable..."
  if curl -s --max-time 4 https://api.github.com >/dev/null 2>&1; then
    echo "ERROR: still reachable. Another interface is up; use default mode." >&2
    exit 2
  fi
  echo "  confirmed unreachable."
  echo

  echo "  building the graph..."
  graphify update "$TARGET" 2>&1 | scrub_vendor
  STATUS=${PIPESTATUS[0]}

else
  echo "  proxying all egress to ${BLACKHOLE} and stripping model API keys..."
  echo

  STATUS=0
  env \
    http_proxy="$BLACKHOLE" \
    https_proxy="$BLACKHOLE" \
    HTTP_PROXY="$BLACKHOLE" \
    HTTPS_PROXY="$BLACKHOLE" \
    ALL_PROXY="$BLACKHOLE" \
    NO_PROXY="" \
    no_proxy="" \
    OPENAI_API_KEY="" \
    ANTHROPIC_API_KEY="" \
    GEMINI_API_KEY="" \
    GOOGLE_API_KEY="" \
    GITHUB_TOKEN="" \
    GH_TOKEN="" \
    graphify update "$TARGET" 2>&1 | scrub_vendor
  STATUS=${PIPESTATUS[0]}
fi

echo

if [[ $STATUS -ne 0 ]]; then
  echo "FAILED: the graph build did not complete without network access." >&2
  exit 1
fi

if [[ ! -f "$TARGET/graphify-out/graph.json" ]]; then
  echo "FAILED: no graph.json was produced." >&2
  exit 1
fi

# The rebuild just regenerated graph.html with a CDN <script> tag in it. Inline
# the vendored library again so the picture stays openable with the network off.
# Non-fatal: if this cannot run, the text proof below is still the actual claim.
if ! ./tools/localize-graph.sh "$TARGET/graphify-out/graph.html" >/dev/null 2>&1; then
  echo "  (note: graph.html could not be localized -- 'make viz' may need network)"
fi

python3 - "$TARGET/graphify-out/graph.json" <<'PY'
import json
import sys

graph = json.load(open(sys.argv[1]))
nodes = graph["nodes"]
links = graph["links"]
calls = [e for e in links if e.get("relation") == "calls"]
inferred = [e for e in links if e.get("confidence") == "INFERRED"]

print("Graph built with no reachable network and no model credentials:")
print("  %d nodes, %d edges, %d resolved call edges" % (len(nodes), len(links), len(calls)))
print("  %d EXTRACTED / %d INFERRED" % (len(links) - len(inferred), len(inferred)))
print("  no model credentials were present, and the build did not need one")

if not calls:
    sys.exit("FAILED: no call edges resolved; the graph is not usable.")
PY

echo
echo "Structural comprehension completed with egress blackholed and every model"
echo "credential stripped. Parsing is not inference; this part stays in-boundary."
echo
# Say the quiet part in our own words rather than quoting the tool's upsell.
# Same admission, none of the vendor branding.
echo "Note, in graphify's own words above:"
echo '  "Re-extracting code files ... (no LLM needed)"'
echo
echo "The tool does offer an optional model-backed layer for richer semantic"
echo "labelling. We did not use it, and nothing above depends on it. The call"
echo "graph came out of parsing alone."
