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

_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
    --service-account-id)
        VAR_AGENT_SA_ID=$2
        shift
        shift
        ;;
    --name)
        _AGENT_NAME=$2
        shift
        shift
        ;;
    --description)
        VAR_AGENT_DESCRIPTION=$2
        shift
        shift
        ;;
    --labels)
        VAR_AGENT_LABELS=$2
        shift
        shift
        ;;
    --zone)
        VAR_AGENT_ZONE=$2
        shift
        shift
        ;;
    --cores)
        VAR_AGENT_CORES=$2
        shift
        shift
        ;;
    --memory)
        VAR_AGENT_MEMORY=$2
        shift
        shift
        ;;
    --network-interfact)
        VAR_AGENT_SUBNET_ID=
        VAR_AGENT_SECURITY_GROUP_IDS=
        _ARGS+=("$2")
        shift
        shift
        ;;
    *)
        _ARGS+=("$1")
        shift
        ;;
    esac
done

assert_not_empty YC_LT_AGENT_SA_ID
assert_not_empty YC_LT_AGENT_SUBNET_ID
assert_not_empty YC_LT_AGENT_SECURITY_GROUP_IDS

if [[ -z "$_AGENT_NAME" ]];then
    _AGENT_NAME="$VAR_AGENT_NAME_PREFIX-$(rand_str)"
fi

# ---------------------------------------------------------------------------- #
#                               Assert variables                               #
# ---------------------------------------------------------------------------- #

if [[ -z "${VAR_FOLDER_ID:-$(yc_ config get folder-id)}" ]]; then
    _log "Folder ID must be specified either via YC_LT_FOLDER_ID or via CLI profile."
    exit 1
fi

# ---------------------------------------------------------------------------- #
#                         Compose command line options                         #
# ---------------------------------------------------------------------------- #

_ARGS+=("--name" "$_AGENT_NAME")
_ARGS+=(--service-account-id "$VAR_AGENT_SA_ID")
_ARGS+=(--description "$VAR_AGENT_DESCRIPTION")
_ARGS+=(--labels "$VAR_AGENT_LABELS")
_ARGS+=(--zone "$VAR_AGENT_ZONE")
_ARGS+=(--cores "$VAR_AGENT_CORES")
_ARGS+=(--memory "$VAR_AGENT_MEMORY")

if [[ -n ${VAR_AGENT_SUBNET_ID} || -n ${VAR_AGENT_SECURITY_GROUP_IDS} ]]; then
    _ARGS+=(--network-interface)
    _ARGS+=("subnet-id=$VAR_AGENT_SUBNET_ID,security-group-ids=$VAR_AGENT_SECURITY_GROUP_IDS")
fi

# ---------------------------------------------------------------------------- #
#                                Create an agent                               #
# ---------------------------------------------------------------------------- #

_log "[agent=$_AGENT_NAME] Creating an agent..."

if ! _AGENT=$(yc_lt agent create "${_ARGS[@]}"); then
    _log "[agent=$_AGENT_NAME] Failed to create an agent. $_AGENT"
    exit 1
fi

_AGENT_ID=$(echo "$_AGENT" | jq -r '.id')
_log "[agent=$_AGENT_NAME] Agent created. id=$_AGENT_ID"

# ---------------------------------------------------------------------------- #
#                      Wait until agent is READY_FOR_TEST                      #
# ---------------------------------------------------------------------------- #

_log "[agent=$_AGENT_NAME] Waiting for agent to be ready..."

_TICK="5" 
_TIMEOUT="600"

_TS_START=$(date +%s)
_TS_TIMEOUT=$((_TS_START + _TIMEOUT))
while [ "$(date +%s)" -lt $_TS_TIMEOUT ]; do
    if ! _AGENT_STATUS=$(yc_lt agent get "$_AGENT_ID" | jq -r '.status'); then
        _log "[agent=$_AGENT_NAME] Failed to get agent status"
        continue
    fi

    if [[ "$_AGENT_STATUS" == "READY_FOR_TEST" ]]; then
        echo "$_AGENT_ID"

        _log "[agent=$_AGENT_NAME] READY_FOR_TEST"
        exit 0
    fi

    _logv 1 "[agent=$_AGENT_NAME] STATUS=$_AGENT_STATUS. Next check in ${_TICK}s"
    sleep "$_TICK"
done

echo "$_AGENT_ID"

_log "[agent=$_AGENT_NAME] STATUS=$_AGENT_STATUS. Timeout of ${_TIMEOUT}s exceeded"
_log "[agent=$_AGENT_NAME] Agent is not ready and likely cant be used in tests!"
exit 1
