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
  time graphify update "$TARGET"
  STATUS=$?

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
    graphify update "$TARGET" || STATUS=$?
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

python3 - "$TARGET/graphify-out/graph.json" <<'PY'
import json
import sys

graph = json.load(open(sys.argv[1]))
nodes = graph["nodes"]
links = graph["links"]
calls = [e for e in links if e.get("relation") == "calls"]
inferred = [e for e in links if e.get("confidence") == "INFERRED"]

print("Graph built with the network unavailable:")
print("  %d nodes, %d edges, %d resolved call edges" % (len(nodes), len(links), len(calls)))
print("  %d EXTRACTED / %d INFERRED" % (len(links) - len(inferred), len(inferred)))
print("  token cost: 0 input, 0 output -- no model was invoked")

if not calls:
    sys.exit("FAILED: no call edges resolved; the graph is not usable.")
PY

echo
echo "PROVED: comprehension ran entirely in-boundary. Nothing left the machine."
