#!/usr/bin/env bash
# scripts/run-ops-tests.sh
# Run all operational shell-script test suites (#558, #559, #560).
#
# These suites are hermetic — they mock Stellar, AWS, the API and Postgres — so
# they are safe to run locally and in CI without any infrastructure.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUITES=(
    "test-disaster-recovery.sh"
    "test-backup-integrity.sh"
    "test-canary-deployment.sh"
)

FAILED=()
for suite in "${SUITES[@]}"; do
    echo ""
    echo "###########################################################"
    echo "# $suite"
    echo "###########################################################"
    if ! bash "$DIR/$suite"; then
        FAILED+=("$suite")
    fi
done

echo ""
echo "==========================================================="
if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "OPS TESTS FAILED: ${FAILED[*]}"
    exit 1
fi
echo "ALL OPS TEST SUITES PASSED"
