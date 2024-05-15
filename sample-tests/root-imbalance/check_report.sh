#!/usr/bin/env bash

if ! run_script -- "$_DEFAULT_CHECK"; then
    exit 1
fi

rc=0

check_json_val \
    'response time 99th percentile less than 10s' \
    '.overall.quantiles.q99 | tonumber' \
    '< 10000'

rc=$((rc | $?))

check_json_val \
    'at least 1000 successful responses' \
    '.overall.http_codes."200" // 0 | tonumber' \
    '>= 1000'

rc=$((rc | $?))

check_json_val \
    'at least 75% of net responses are 0' \
    '(.overall.net_codes."0" // 0 | tonumber) / ([.overall.net_codes[] | tonumber] | add)' \
    '> 0.75'

rc=$((rc | $?))

check_json_val \
    'at least 75% of http responses are 200' \
    '(.overall.http_codes."200" // 0 | tonumber) / ([.overall.http_codes[] | tonumber] | add)' \
    '> 0.75'

rc=$((rc | $?))

exit $rc
