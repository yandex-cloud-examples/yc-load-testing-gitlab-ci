#!/usr/bin/env bash

set -eo pipefail

# shellcheck disable=SC2155
export _SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# shellcheck source=_functions.sh
source "$_SCRIPT_DIR/_functions.sh"

# shellcheck source=_variables.sh
source "$_SCRIPT_DIR/_variables.sh"

# ---------------------------------------------------------------------------- #
#                     Retrieve arguments from command line                     #
# ---------------------------------------------------------------------------- #

_CMD=''

_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
    create)
        _CMD='create'
        shift
        ;;
    delete)
        _CMD='delete'
        shift
        ;;
    --)
        _ARGS+=("$@")
        break
        ;;
    *)
        _ARGS+=("$1")
        shift
        ;;
    esac
done

if [[ -z "${VAR_FOLDER_ID:-$(yc_ config get folder-id)}" ]]; then
    _log "Folder ID must be specified either via YC_LT_FOLDER_ID or via CLI profile."
    exit 1
fi

if [[ "$_CMD" == 'create' ]]; then
    _log "Compute Agents create request. Number of agents: $VAR_AGENTS_CNT"

    _pids=()
    for _ in $(seq 1 "$VAR_AGENTS_CNT"); do
        run_script "$_SCRIPT_DIR/_agent_create.sh" "${_ARGS[@]}" &
        _pids+=("$!")
    done

    _rc=0
    for _pid in "${_pids[@]}"; do
        wait "$_pid"
        _rc=$((_rc | $?))
    done

    exit ${_rc}

elif [[ "$_CMD" == 'delete' ]]; then
    _log "Compute Agents delete request. Number of agents: $VAR_AGENTS_CNT"

    run_script "$_SCRIPT_DIR/_agent_delete.sh" "${_ARGS[@]}"
    exit $?
fi
