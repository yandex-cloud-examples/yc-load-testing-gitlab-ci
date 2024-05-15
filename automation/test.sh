#!/usr/bin/env bash

set -e

# shellcheck disable=SC2155
export _SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# shellcheck source=_functions.sh
source "$_SCRIPT_DIR/_functions.sh"

# shellcheck source=_variables.sh
source "$_SCRIPT_DIR/_variables.sh"

assert_installed yc jq curl

_logv 1 "YC CLI provile: ${VAR_CLI_PROFILE:-"current aka <$(yc_ config profile list | grep ' ACTIVE')>"}"
_logv 1 ""

_log -f <<EOF
Execution:
|--------------------
| folder: ${VAR_FOLDER_ID:-$(yc_ config get folder-id)}
| skip results check: $VAR_SKIP_TEST_CHECK
|
| data bucket: $VAR_DATA_BUCKET
| extra test labels: $VAR_TEST_EXTRA_LABELS
| extra test description: $VAR_TEST_EXTRA_DESCRIPTION
|
| output local dir: $VAR_OUTPUT_DIR
|--------------------
EOF
_log ""

if [[ -z "${VAR_FOLDER_ID:-$(yc_ config get folder-id)}" ]]; then
    _log "Folder ID must be specified either via YC_LT_FOLDER_ID or via CLI profile."
    exit 1
fi

declare -ir _TOTAL_CNT="$#"
declare -i _FAILED_CNT=0
declare _FAILED_TESTS=()

mkdir -p "$VAR_OUTPUT_DIR"

declare -r _TEST_DIRECTORIES=("$@")
for _dir in "${_TEST_DIRECTORIES[@]}"; do
    _log "-> [RUN]: $_dir"

    if _test_id=$(run_script "$_SCRIPT_DIR/_test_run.sh" "$_dir"); then
        _log "-> [RUN]: success (test_id=$_test_id)"
    else
        ((_FAILED_CNT += 1))
        _FAILED_TESTS+=("RUN FAILED: $_dir")

        _log "-> [RUN]: fail"
        continue
    fi

    export _TEST_OUTPUT_DIR="$VAR_OUTPUT_DIR/$_test_id"
    mkdir -p "$_TEST_OUTPUT_DIR"

    if [[ "${VAR_SKIP_TEST_CHECK:-0}" == 0 ]]; then
        _check_result_file="$_TEST_OUTPUT_DIR/check_result.txt"
        _log "-> [CHECK]: begin"
        if run_script "$_SCRIPT_DIR/_test_check.sh" "$_dir" "$_test_id" >"$_check_result_file"; then
            _logv 1 -f <"$_check_result_file"
            _log "-> [CHECK]: success"
        else
            ((_FAILED_CNT += 1))
            _FAILED_TESTS+=("CHECK FAILED: $_dir. Result in $_check_result_file")

            _log -f <"$_check_result_file"
            _log "-> [CHECK]: failed"
        fi
        _log ""
    else
        _log "-> [CHECK]: skip due to YC_LT_SKIP_TEST_CHECK"
        _log ""
    fi

done

_SUCCESS_CNT=$((_TOTAL_CNT - _FAILED_CNT))
_S="[ OK - $_SUCCESS_CNT | FAILED - $_FAILED_CNT ]"

_log "==================== $_S ===================="
_log ""
if ((_FAILED_CNT != 0)); then
    _log "$_FAILED_CNT out of $_TOTAL_CNT tests have failed:"
    _log "$(
        IFS=$'\n'
        echo "${_FAILED_TESTS[*]}"
    )"
fi
_log ""
_log "==================== $_S ===================="

echo "$_FAILED_CNT"

exit "$_FAILED_CNT"
