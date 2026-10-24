#!/usr/bin/env bash
# Prints -only-testing arguments for the failed UI tests whose only failures
# are the app failing to launch, a simulator stall on a busy runner rather
# than a defect. Exits 2 when some failed test also failed for another reason,
# so the caller can retry the launch failures and still fail the job.
# Usage: ui-test-launch-failures.sh <result bundle>
set -euo pipefail

bundle=$1
target=CANCompanionUITests
launch='Failed to launch|Failed to get launch progress|Timed out while (launching|requesting launch progress)'

failed=$(xcrun xcresulttool get test-results tests --path "$bundle" | jq -c --arg launch "$launch" '
  [.. | objects | select(.nodeType == "Test Case" and .result == "Failed")
   | { id: .nodeIdentifier,
       launch: ([.children[]? | select(.nodeType == "Failure Message") | .name | test($launch)]
                | length > 0 and all) }]')

jq -r --arg t "$target" \
  '.[] | select(.launch) | "-only-testing:\($t)/\(.id | rtrimstr("()"))"' <<<"$failed" | paste -sd ' ' -

if [ "$(jq '[.[] | select(.launch | not)] | length' <<<"$failed")" -gt 0 ]; then
  exit 2
fi
