#!/usr/bin/env bash

function _log {
    if [[ "$1" == '-f' ]]; then
        shift
        cat >&2 "$@"
    else
        echo >&2 "$@"
    fi
}

function _logv {
    if [[ ${VERBOSE:-0} -ge "$1" ]]; then
        shift
        _log "$@"
    fi
}

function assert_installed {
    for _cmd in "$@"; do
        if ! command -v "$_cmd" 1>/dev/null 2>&1; then
            _log "ERROR!!! Assertion failed: $_cmd is not installed"
            exit 1
        fi
    done
    return 0
}

function assert_not_empty {
    if [[ -z "${!1}" ]]; then
        _log "ERROR!!! Assertion failed: variable $1 is empty or not defined"
        exit 1
    fi
    return 0
}

function assert_exists {
    if [[ -z "${!1+empty}" ]]; then
        _log "ERROR!!! Assertion failed: variable $1 is not defined"
        exit 1
    fi
    return 0
}

function rand_str {
    (
        set +o pipefail
        LC_ALL=C tr -d -c '0-9a-f' </dev/urandom | head -c 6
    )
}

function run_script {
    /usr/bin/env bash "$@"
}

function yc_ {
    local yc_options=()
    if [[ "$VAR_CLI_INTERACTIVE" == "0" ]]; then
        yc_options+=(--no-browser)
    fi
    if [[ -n "$VAR_CLI_PROFILE" ]]; then
        yc_options+=(--profile "$VAR_CLI_PROFILE")
    fi
    if [[ -n "$VAR_FOLDER_ID" ]]; then
        yc_options+=(--folder-id "$VAR_FOLDER_ID")
    fi

    _logv 2 "Calling yc ${yc_options[*]} $*"
    yc "${yc_options[@]}" "$@"
    return $?
}

function yc_get_token {
    yc_ --format text iam create-token
    return $?
}

function yc_lt {
    yc_ --format json loadtesting "$@"
    return $?
}

function yc_s3_upload {
    local -r file=$1
    local -r bucket_path=$2
    local -r bucket=${3:-"$VAR_DATA_BUCKET"}

    assert_not_empty file
    assert_not_empty bucket
    assert_not_empty bucket_path

    local -r token=${VAR_TOKEN:-$(yc_get_token)}
    local -r auth_h="X-YaCloud-SubjectToken: $token"
    curl -L -H "$auth_h" --upload-file - "$VAR_OBJECT_STORAGE_URL/$bucket/$bucket_path" \
        2>/dev/null \
        <"$file"

    return $?
}

function yc_s3_delete {
    local -r bucket_path=$1
    local -r bucket=${2:-"$VAR_DATA_BUCKET"}

    assert_not_empty bucket
    assert_not_empty bucket_path

    local -r token=${VAR_TOKEN:-$(yc_get_token)}
    local -r auth_h="X-YaCloud-SubjectToken: $token"
    curl -L -H "$auth_h" -X DELETE "$VAR_OBJECT_STORAGE_URL/$bucket/$bucket_path" \
        2>/dev/null

    return $?
}

function concat_optional {
    local -r lhs=$1
    local -r rhs=$2
    local -r delimiter=$3
    if [[ -n "$lhs" && -n "$rhs" ]]; then
        echo "${lhs}${delimiter}${rhs}"
    else
        echo "${lhs:-"$rhs"}"
    fi
    return 0
}

function check_json_val {
    local -r description=${1:-"$2 $3"}
    local -r filter=$2
    local -r condition=$3
    local -r file=${4:-$_CHECK_JSON_FILE}
    echo "- $description"
    echo "-- $(jq -r "$filter" "$file" 2>/dev/null) $condition"
    if jq -re "($filter) $condition" "$file" >/dev/null ; then
        echo "-- OK"
        return 0
    else
        echo "-- filter: $filter"
        echo "-- FAIL"
        return 1
    fi
}
