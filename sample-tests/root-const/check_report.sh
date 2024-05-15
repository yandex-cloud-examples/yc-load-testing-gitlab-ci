#!/usr/bin/env bash

if ! run_script -- "$_DEFAULT_CHECK"; then
    exit 1
fi

rc=0

check_json_val \
    'response time 50th percentile less than 200ms' \
    '.overall.quantiles.q50 | tonumber' \
    '< 200'

rc=$((rc | $?))

exit $rc
