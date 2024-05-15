#!/usr/bin/env bash

set -eo pipefail

# shellcheck disable=SC2155
export _SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# shellcheck source=_functions.sh
source "$_SCRIPT_DIR/_functions.sh"

# shellcheck source=_variables.sh
source "$_SCRIPT_DIR/_variables.sh"

assert_installed yc jq curl

if [[ -z ${VAR_AGENT_NAME_PREFIX:-} && -z ${VAR_AGENT_LABELS:-} && -z ${VAR_AGENT_IDS:-} ]]; then
    _log "Cannot pick an agent to delete. Define at least on of (YC_LT_AGENT_NAME_PREFIX, YC_LT_AGENT_LABELS, YC_LT_AGENT_ID)"
    exit 1
fi

# ---------------------------------------------------------------------------- #
#                                Compose filter                                #
# ---------------------------------------------------------------------------- #

function add_filter {
    if [[ -n ${_FILTER} ]]; then
        _FILTER+=" and "
    fi
    _FILTER+="$*"
}

_FILTER=""

if [[ -n ${VAR_AGENT_NAME_PREFIX:-} ]]; then
    add_filter "name contains \"$VAR_AGENT_NAME_PREFIX\""
fi

if [[ -n ${VAR_AGENT_LABELS:-} ]]; then
    IFS=',' read -ra _LABELS <<<"$VAR_AGENT_LABELS"
    for _kv in "${_LABELS[@]}"; do
        IFS='=' read -r _key _value <<<"$_kv"
        add_filter "labels.$_key = \"$_value\""
    done <<<"$VAR_AGENT_LABELS"
fi

if [[ -n ${VAR_AGENT_IDS:-} ]]; then
    add_filter "id in ($VAR_AGENT_IDS)"
fi

if [[ -z ${_FILTER} ]]; then
    _log "Error! Filter is empty"
fi

_log "Filter: $_FILTER"

# ---------------------------------------------------------------------------- #
#                   Determine which agents should be deleted                   #
# ---------------------------------------------------------------------------- #

_log "Determining which agents to be deleted..."


_AGENT_IDS=()
IFS=' ' read -r -a _AGENT_IDS < <(yc_lt agent list --filter "$_FILTER" | jq -r '[.[].id] | join(" ")')

if [[ ${#_AGENT_IDS} -eq 0 ]]; then
    _log "No agents were found for given filter"
    exit 0
fi

_log "Agents to be deleted: ${_AGENT_IDS[*]}"

# ---------------------------------------------------------------------------- #
#                                 Delete agents                                #
# ---------------------------------------------------------------------------- #

_log "Deleting agents..."
yc_lt agent delete "${_AGENT_IDS[@]}"

exit $?
