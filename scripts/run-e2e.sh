#!/usr/bin/env bash
# Trigger the e2e.yml GitHub Actions workflow and optionally wait for it.
# Runs on a GitHub-hosted macOS runner with its own virtual display, so your
# local machine is never touched.
#
# Usage:
#   ./scripts/run-e2e.sh                          # run all UI tests
#   ./scripts/run-e2e.sh TabCreationTests          # run one test class
#   ./scripts/run-e2e.sh TabCreationTests/testNewTab --wait
#   ./scripts/run-e2e.sh --ref my-branch --timeout 300

set -euo pipefail

REPO="hoishing/kterm"
WORKFLOW="e2e.yml"

TEST_FILTER=""
REF=""
TIMEOUT="120"
WAIT=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [test_filter] [options]

Arguments:
  test_filter       Test class or class/method (e.g. TabCreationTests)

Options:
  --ref <ref>       Branch or SHA to test (default: current branch)
  --timeout <sec>   Per-test timeout in seconds (default: 120)
  --wait            Wait for the run to complete and print the result
  -h, --help        Show help
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)
      REF="$2"; shift 2 ;;
    --timeout)
      TIMEOUT="$2"; shift 2 ;;
    --wait)
      WAIT=true; shift ;;
    -h|--help)
      usage ;;
    *)
      if [ -n "$TEST_FILTER" ]; then
        echo "Unknown argument: $1" >&2
        usage
      fi
      TEST_FILTER="$1"
      shift
      ;;
  esac
done

[ -n "$REF" ] || REF="$(git rev-parse --abbrev-ref HEAD)"

FIELDS=(-f "test_filter=$TEST_FILTER" -f "test_timeout=$TIMEOUT" -f "ref=$REF")

echo "Triggering $WORKFLOW on $REPO (ref=$REF, test_filter=${TEST_FILTER:-<all>}, timeout=$TIMEOUT)"
gh workflow run "$WORKFLOW" --repo "$REPO" "${FIELDS[@]}"

sleep 3
RUN_ID=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId')
RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"
echo "Run: $RUN_URL"

if [ "$WAIT" = true ]; then
  gh run watch "$RUN_ID" --repo "$REPO" --exit-status
fi
