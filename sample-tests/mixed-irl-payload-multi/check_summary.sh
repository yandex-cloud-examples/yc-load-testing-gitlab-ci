#!/usr/bin/env bash

if ! run_script -- "$_DEFAULT_CHECK"; then
    exit 1
fi

rc=0

check_json_val \
    'test status is DONE' \
    '.summary.status' \
    '== "DONE"'

rc=$((rc | $?))

check_json_val \
    'no error reported' \
    '.summary.error // ""' \
    '== ""'

rc=$((rc | $?))

exit $rc
