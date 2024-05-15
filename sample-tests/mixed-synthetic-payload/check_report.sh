#!/usr/bin/env bash

if ! run_script -- "$_DEFAULT_CHECK"; then
    exit 1
fi

rc=0

check_json_val \
    'response time 50th percentile less than 5s' \
    '.overall.quantiles.q50 | tonumber' \
    '< 5000'

rc=$((rc | $?))

check_json_val \
    'has some successful requests to /' \
    '.cases."root".http_codes."200" // 0 | tonumber' \
    '> 0'

rc=$((rc | $?))

check_json_val \
    'has some successful requests to /foo' \
    '.cases."foo".http_codes."200" // 0 | tonumber' \
    '> 0'

rc=$((rc | $?))

check_json_val \
    'has some successful requests to /bar' \
    '.cases."bar".http_codes."200" // 0 | tonumber' \
    '> 0'

rc=$((rc | $?))

exit $rc
