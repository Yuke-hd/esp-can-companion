#!/usr/bin/env bash
# Prints the -only-testing arguments for one shard of the UI tests.
# Usage: ui-test-shard.sh <shard index, 0-based> <shard count>
#
# Tests are found by scanning AppUITests for `class X: XCTestCase` and
# `func testY()`, sorted, then dealt round-robin so new tests join a shard
# without editing the workflow.
set -euo pipefail

index=$1
count=$2
target=CANCompanionUITests

tests=$(awk '
  match($0, /class [A-Za-z0-9_]+: *XCTestCase/) {
    split(substr($0, RSTART + 6, RLENGTH - 6), parts, ":"); cls = parts[1]
  }
  cls != "" && match($0, /func test[A-Za-z0-9_]*\(\)/) {
    print cls "/" substr($0, RSTART + 5, RLENGTH - 7)
  }
' AppUITests/*.swift | sort)

if [ -z "$tests" ]; then
  echo "::error::no UI tests found in AppUITests" >&2
  exit 1
fi

args=$(awk -v i="$index" -v n="$count" -v t="$target" \
  '(NR - 1) % n == i { printf "-only-testing:%s/%s ", t, $0 }' <<<"$tests")

if [ -z "$args" ]; then
  echo "::error::UI test shard $index of $count is empty" >&2
  exit 1
fi

echo "$args"
