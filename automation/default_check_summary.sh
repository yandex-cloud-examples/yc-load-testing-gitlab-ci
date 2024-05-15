#!/usr/bin/env bash

rc=0

check_json_val \
    'test status doesnt indicate an error' \
    '.summary.status' \
    '| IN("DONE", "AUTOSTOPPED")'

rc=$((rc | $?))

exit $rc
