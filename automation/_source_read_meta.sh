#!/usr/bin/env bash

declare -r _TEST_META_FILE="$1"

assert_not_empty _TEST_META_FILE

export _TEST_CONFIG_MASK=
export _TEST_NAME=
export _TEST_DESCRIPTION=
export _TEST_MULTI_FACTOR=
export _TEST_LABELS=
export _TEST_AGENT_FILTER=
export _TEST_DATA_EXTERNAL_FILES=
export _TEST_DATA_EXTERNAL_FILES_SPECS=

if [[ ! -f "$_TEST_META_FILE" ]]; then
    return 0
fi

function read_meta {
    jq -r "$1" "$_TEST_META_FILE"
    return 0
}

_TEST_CONFIG_MASK=$(read_meta '
    .config_mask // "" 
    | tostring 
')
_TEST_NAME=$(read_meta '
    .name // "" 
    | tostring 
')
_TEST_DESCRIPTION=$(read_meta '
    .description // "" 
    | tostring 
')
_TEST_MULTI_FACTOR=$(read_meta '
    .multi // "" 
    | tostring 
')
_TEST_LABELS=$(read_meta '
    .labels // {} 
    | to_entries 
    | map("\(.key)=\(.value)") 
    | join(",")
')
_TEST_AGENT_FILTER=$(read_meta '
    .agent_labels // {} 
    | to_entries
    | map("labels.\(.key)=\"\(.value)\"") 
    | join(" and ")
')

IFS=$'\n' read -d '' -ra _TEST_DATA_EXTERNAL_FILES < <(read_meta '
    .external_data // []
    | [.[] | select(.name? and .s3file? and .s3bucket?)]
    | map("\(.name)")
    | join("\n")
') || true

IFS=$'\n' read -d '' -ra _TEST_DATA_EXTERNAL_FILES_SPECS < <(read_meta '
    .external_data // []
    | [.[] | select(.name? and .s3file? and .s3bucket?)]
    | map("name=\(.name),s3file=\(.s3file),s3bucket=\(.s3bucket)")
    | join("\n")
') || true
