#!/usr/bin/env bash
set -euo pipefail

# Regenerate the checked-in .err / .disasm golden files under tests/rea/ for
# named fixtures, using the exact invocation + normalisation run.sh applies
# when comparing. Intended for bringing goldens back in sync after a
# deliberate, verified VM/disassembly-format change (e.g. opcode renames) —
# NOT for papering over real behavioural regressions. Verify with run.sh
# first that only disassembly text differs (stdout + exit code unaffected)
# before trusting a regenerated golden.
#
# Usage: tests/tools/regen_golden.sh [--bin PATH] fixture_name [fixture_name...]
#   REA_BIN can also be set via env, same default as run.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REA_BIN="${REA_BIN:-$TESTS_DIR/../build/rea}"
RUNNER_PY="$TESTS_DIR/tools/run_with_timeout.py"
TEST_TIMEOUT="${TEST_TIMEOUT:-25}"

if [ "${1:-}" = "--bin" ]; then
    REA_BIN="$2"
    shift 2
fi

if [ "$#" -eq 0 ]; then
    printf 'usage: %s [--bin PATH] fixture_name [fixture_name...]\n' "$0" >&2
    exit 2
fi

strip_ansi_inplace() {
    local path="$1"
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]|\e\][^\a]*(?:\a|\e\\)//g' "$path" > "$path.clean"
    mv "$path.clean" "$path"
}

normalise_rea_stderr() {
    strip_ansi_inplace "$1"
    perl -0 -pe 's/^Compilation successful.*\n//m; s/^Loaded cached bytecode.*\n//m' "$1" > "$1.clean"
    mv "$1.clean" "$1"
}

for test_name in "$@"; do
    src_rel="rea/$test_name.rea"
    src="$TESTS_DIR/$src_rel"
    if [ ! -f "$src" ]; then
        printf 'skip %s: no such fixture %s\n' "$test_name" "$src" >&2
        continue
    fi

    disasm_expect="$TESTS_DIR/rea/$test_name.disasm"
    err_expect="$TESTS_DIR/rea/$test_name.err"
    args_file="$TESTS_DIR/rea/$test_name.args"

    if [ -f "$disasm_expect" ]; then
        tmp_err=$(mktemp)
        (cd "$TESTS_DIR" && python3 "$RUNNER_PY" --timeout "$TEST_TIMEOUT" "$REA_BIN" --dump-bytecode-only "$src_rel" > /dev/null 2> "$tmp_err")
        normalise_rea_stderr "$tmp_err"
        cp "$tmp_err" "$disasm_expect"
        rm -f "$tmp_err"
        printf 'regenerated %s\n' "$disasm_expect"
    fi

    if [ -f "$err_expect" ]; then
        arg_list=()
        args_source=""
        args_file_present=0
        if [ -f "$args_file" ]; then
            args_file_present=1
            if IFS= read -r args_source < "$args_file"; then
                :
            else
                args_source=""
            fi
        fi
        if [ -n "$args_source" ]; then
            read -r -a arg_list <<< "$args_source"
        elif [ $args_file_present -eq 0 ]; then
            arg_list=(--dump-bytecode-only)
        fi

        tmp_out=$(mktemp)
        tmp_err=$(mktemp)
        input_file="$TESTS_DIR/rea/$test_name.in"
        cmd=(python3 "$RUNNER_PY" --timeout "$TEST_TIMEOUT" "$REA_BIN")
        if (( ${#arg_list[@]} )); then
            cmd+=("${arg_list[@]}")
        fi
        cmd+=("$src_rel")

        set +e
        if [ -f "$input_file" ]; then
            (cd "$TESTS_DIR" && "${cmd[@]}" < "$input_file" > "$tmp_out" 2> "$tmp_err")
        else
            (cd "$TESTS_DIR" && "${cmd[@]}" > "$tmp_out" 2> "$tmp_err")
        fi
        run_status=$?
        set -e

        strip_ansi_inplace "$tmp_out"
        normalise_rea_stderr "$tmp_err"

        if [ $run_status -ne 0 ]; then
            printf 'WARNING %s: rea exited %d, .err NOT regenerated (check for real regression)\n' "$test_name" "$run_status" >&2
        else
            cp "$tmp_err" "$err_expect"
            printf 'regenerated %s\n' "$err_expect"
        fi
        rm -f "$tmp_out" "$tmp_err"
    fi
done
