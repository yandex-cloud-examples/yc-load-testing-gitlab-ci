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

_TEST_DATA_BUCKET_DIR="test-runs/$(rand_str)"
declare -r _TEST_DATA_BUCKET_DIR

# ---------------------------------------------------------------------------- #
#                           Determine test parameters                          #
# ---------------------------------------------------------------------------- #

_logv 1 "Reading $VAR_TEST_META_FILE"

# shellcheck source=_source_read_meta.sh
source "$_SCRIPT_DIR/_source_read_meta.sh" "$_TEST_DIR/$VAR_TEST_META_FILE"

_TEST_CONFIG_MASK=${_TEST_CONFIG_MASK:-"$VAR_TEST_CONFIG_MASK"}
_TEST_NAME=${_TEST_NAME:-"$VAR_TEST_NAME_PREFIX-$(basename "$_TEST_DIR")"}
_TEST_MULTI_FACTOR=${_TEST_MULTI_FACTOR:-"$VAR_TEST_MULTI_FACTOR"}

_TEST_AGENT_FILTER=$(concat_optional "$VAR_TEST_AGENT_FILTER" "$_TEST_AGENT_FILTER" " and ")
_TEST_LABELS=$(concat_optional "$VAR_TEST_EXTRA_LABELS" "$_TEST_LABELS" ",")
_TEST_DESCRIPTION=$(concat_optional "$VAR_TEST_EXTRA_DESCRIPTION" "$_TEST_DESCRIPTION" "  \n\n")

_TEST_CONFIG_FILES=()
while IFS= read -d '' -r _f; do _TEST_CONFIG_FILES+=("$_f"); done < \
    <(find "$_TEST_DIR" -type f -name "$_TEST_CONFIG_MASK" -maxdepth 1 -print0)

_TEST_ALL_FILES=()
while IFS= read -d '' -r _f; do _TEST_ALL_FILES+=("$_f"); done < \
    <(find "$_TEST_DIR" -type f -print0)

_TEST_DATA_FILES=()
for _f in "${_TEST_ALL_FILES[@]}"; do
    _IS_NON_DATA_FILE=0

    _NON_DATA_FILES=("${_TEST_CONFIG_FILES[@]}")
    _NON_DATA_FILES+=("$_TEST_DIR/$VAR_TEST_META_FILE")
    _NON_DATA_FILES+=("$_TEST_DIR/$VAR_CHECK_SUMMARY_SCRIPT_NAME")
    _NON_DATA_FILES+=("$_TEST_DIR/$VAR_CHECK_REPORT_SCRIPT_NAME")
    for _ndf in "${_NON_DATA_FILES[@]}"; do
        if [[ "$_f" == "$_ndf" ]]; then
            _IS_NON_DATA_FILE=1
            break
        fi
    done

    if [[ "$_IS_NON_DATA_FILE" == 0 ]]; then
        _TEST_DATA_FILES+=("$_f")
    fi
done

_logv 1 -f <<EOF
Test parameters:
|--------------------
| name: $_TEST_NAME
| description: $_TEST_DESCRIPTION
| labels: $_TEST_LABELS
| agent filter: $_TEST_AGENT_FILTER
| multitest factor: $_TEST_MULTI_FACTOR -- every config will be run on $_TEST_MULTI_FACTOR agents
|
| configs: ${_TEST_CONFIG_FILES[*]}
|
| bucket temp path: $_TEST_DATA_BUCKET_DIR
| local data files: ${_TEST_DATA_FILES[*]}
|
| external data files: ${_TEST_DATA_EXTERNAL_FILES[*]}
|--------------------
EOF
_logv 1 ""

# ---------------------------------------------------------------------------- #
#                         Upload data to object storage                        #
# ---------------------------------------------------------------------------- #

if [[ -n "$VAR_DATA_BUCKET" ]]; then
    _logv 1 "Uploading data files..."

    function cleanup_data_files {
        _log "Cleaning up data files..."
        for _file in "${_TEST_DATA_FILES[@]}"; do
            _file_bucket="$_TEST_DATA_BUCKET_DIR/${_file#"$_TEST_DIR/"}"
            if ! yc_s3_delete "$_file_bucket" >/dev/null; then
                _log "- failed to delete $_file_bucket"
            fi
        done
    }
    trap cleanup_data_files EXIT

    for _file in "${_TEST_DATA_FILES[@]}"; do
        _file_bucket="$_TEST_DATA_BUCKET_DIR/${_file#"$_TEST_DIR/"}"
        if ! yc_s3_upload "$_file" "$_file_bucket" >/dev/null; then
            _log "- failed to upload $_file_bucket"
        fi
    done
else
    _logv 1 "YC_LT_DATA_BUCKET is not specified. Data files will not be uploaded."
    _TEST_DATA_FILES=()
fi

# ---------------------------------------------------------------------------- #
#                                Create configs                                #
# ---------------------------------------------------------------------------- #

_logv 1 "Creating configs..."

_CONFIG_IDS=()
for _file in "${_TEST_CONFIG_FILES[@]}"; do
    _content=$(cat "$_file")

    # shellcheck disable=SC2016
    _content=${_content/'${YC_LT_TARGET}'/"${YC_LT_TARGET:-localhost}"}
    config_id=$(yc_lt test-config create --yaml-string "$_content" | jq -r '.id')
    _CONFIG_IDS+=("$config_id")
done

# ---------------------------------------------------------------------------- #
#                                 Run the test                                 #
# ---------------------------------------------------------------------------- #

_logv 1 "Running test..."

# shellcheck source=_source_create_test_args.sh
source "$_SCRIPT_DIR/_source_create_test_args.sh"
_RUN_OUTPUT=$(yc_lt test create --wait --wait-idle-timeout 60s "${_TEST_CREATE_CMD_ARGS[@]}")

# check the output is json
if ! (echo "$_RUN_OUTPUT" | jq -e . >/dev/null 2>&1); then
    _log "ERROR!!! test creation result should be a json"
    _log "$_RUN_OUTPUT"
    _log ""
    exit 1
fi

echo "$_RUN_OUTPUT" | jq -r '.id'
