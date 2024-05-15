#!/usr/bin/env bash

assert_not_empty _TEST_CONFIG_FILES
assert_not_empty _TEST_NAME
assert_not_empty _TEST_MULTI_FACTOR
assert_exists _TEST_DESCRIPTION
assert_exists _TEST_LABELS
assert_exists _TEST_AGENT_FILTER

function join_args {
    local joined
    joined=$(printf ",%s" "$@")
    echo "${joined:1}"
}

_DATA_ARGS=()
_DATA_ARGS+=("${_TEST_DATA_EXTERNAL_FILES_SPECS[@]}")
if [[ -n ${VAR_DATA_BUCKET} ]]; then
    for _file in "${_TEST_DATA_FILES[@]}"; do
        _file_rel=${_file#"$_TEST_DIR/"}

        arr=()
        arr+=("name=$_file_rel")
        arr+=("s3file=$_TEST_DATA_BUCKET_DIR/$_file_rel")
        arr+=("s3bucket=$VAR_DATA_BUCKET")

        arr_joined=$(join_args "${arr[@]}")

        _DATA_ARGS+=("$arr_joined")
    done
fi

_CONFIG_ARGS=()
for _ in $(seq 1 "$_TEST_MULTI_FACTOR"); do
    for _id in "${_CONFIG_IDS[@]}"; do
        arr=()
        arr+=("id=$_id")
        arr+=("agent-by-filter=$_TEST_AGENT_FILTER")

        for _file in "${_TEST_DATA_EXTERNAL_FILES[@]}"; do
            arr+=("test-data=$_file")
        done
        for _file in "${_TEST_DATA_FILES[@]}"; do
            _file_rel=${_file#"$_TEST_DIR/"}
            arr+=("test-data=$_file_rel")
        done

        arr_joined=$(join_args "${arr[@]}")

        _CONFIG_ARGS+=("$arr_joined")
    done
done

_TEST_CREATE_CMD_ARGS=()
_TEST_CREATE_CMD_ARGS+=(--name "$_TEST_NAME")
_TEST_CREATE_CMD_ARGS+=(--description "$_TEST_DESCRIPTION")
_TEST_CREATE_CMD_ARGS+=(--labels "$_TEST_LABELS")
for x in "${_CONFIG_ARGS[@]}"; do
    _TEST_CREATE_CMD_ARGS+=(--configuration "$x")
done
for x in "${_DATA_ARGS[@]}"; do
    _TEST_CREATE_CMD_ARGS+=(--test-data "$x")
done

export _TEST_CREATE_CMD_ARGS
