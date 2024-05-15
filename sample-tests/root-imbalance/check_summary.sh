#!/usr/bin/env bash

if ! run_script -- "$_DEFAULT_CHECK"; then
    exit 1
fi

rc=0

check_json_val \
    'test status is AUTOSTOPPED' \
    '.summary.status' \
    '== "AUTOSTOPPED"'

rc=$((rc | $?))

check_json_val \
    'no error reported' \
    '.summary.error // ""' \
    '== ""'

rc=$((rc | $?))

check_json_val \
    'degradation reached' \
    '.summary.imbalance_point.rps // 0 | tonumber' \
    '!= 0'

[[ $? == 0 ]]

check_json_val \
    'handled 3000 rps' \
    '.summary.imbalance_point.rps // 0 | tonumber' \
    '> 3000'

[[ $? == 0 ]]

exit $rc
