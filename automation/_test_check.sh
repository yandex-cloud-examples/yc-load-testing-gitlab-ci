#!/usr/bin/env bash

set -eo pipefail

# shellcheck disable=SC2155
export _SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# shellcheck source=_functions.sh
source "$_SCRIPT_DIR/_functions.sh"

# shellcheck source=_variables.sh
source "$_SCRIPT_DIR/_variables.sh"

assert_installed yc jq curl

# ---------------------------------------------------------------------------- #
#                            Arguments and constants                           #
# ---------------------------------------------------------------------------- #

declare -r _TEST_DIR=$1
assert_not_empty _TEST_DIR

declare -r _TEST_ID=$2
assert_not_empty _TEST_ID

declare -r _SUMMARY_JSON="$_TEST_OUTPUT_DIR/summary.json"
declare -r _REPORT_JSON="$_TEST_OUTPUT_DIR/report.json"

declare -r _CUSTOM_SUMMARY_CHECK="$_TEST_DIR/$VAR_CHECK_SUMMARY_SCRIPT_NAME"
declare -r _CUSTOM_REPORT_CHECK="$_TEST_DIR/$VAR_CHECK_REPORT_SCRIPT_NAME"

# ---------------------------------------------------------------------------- #
#                          Determine checking scripts                          #
# ---------------------------------------------------------------------------- #

function first_existing {
    for _file in "$@"; do
        if [[ -f ${_file} ]]; then
            echo "$_file"
            return 0
        fi
    done
    return 1
}

_SUMMARY_CHECK=$(first_existing "$_TEST_DIR/$VAR_CHECK_SUMMARY_SCRIPT_NAME" "$VAR_DEFAULT_CHECK_SUMMARY_SCRIPT_PATH")
_REPORT_CHECK=$(first_existing "$_TEST_DIR/$VAR_CHECK_REPORT_SCRIPT_NAME" "$VAR_DEFAULT_CHECK_REPORT_SCRIPT_PATH")

# ---------------------------------------------------------------------------- #
#                            Retrieve data to check                            #
# ---------------------------------------------------------------------------- #

if ! yc_lt test get "$_TEST_ID" >"$_SUMMARY_JSON"; then
    _log "ERROR!!! failed to download test summary"
    exit 1
fi
if ! yc_lt test get-report-table "$_TEST_ID" >"$_REPORT_JSON"; then
    _log "ERROR!!! failed to download test report"
    exit 1
fi

# ---------------------------------------------------------------------------- #
#                                  Run checks                                  #
# ---------------------------------------------------------------------------- #

set +e

export -f run_script
export -f check_json_val

_logv 1 "Running script $_SUMMARY_CHECK"
_CHECK_JSON_FILE="$_SUMMARY_JSON" _DEFAULT_CHECK="$VAR_DEFAULT_CHECK_SUMMARY_SCRIPT_PATH" \
    run_script -- "$_SUMMARY_CHECK" "$_SUMMARY_JSON"

_SUMMARY_RES=$?

_logv 1 "Running script $_REPORT_CHECK"
_CHECK_JSON_FILE="$_REPORT_JSON" _DEFAULT_CHECK="$VAR_DEFAULT_CHECK_REPORT_SCRIPT_PATH" \
    run_script -- "$_REPORT_CHECK" "$_REPORT_JSON"

_REPORT_RES=$?

((_SUMMARY_RES == 0 && _REPORT_RES == 0))
exit $?
