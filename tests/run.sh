#!/usr/bin/env bash
set -euo pipefail

# This runner ships inside the rea repo at tests/. The .rea fixtures live in
# tests/rea/ beside it, the shared harness tools in tests/tools/, and the example
# programs one directory up in examples/. REA_BIN defaults to the standalone build
# (./build/rea); callers can override it, e.g. the umbrella points it at
# build/bin/rea over this same corpus.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR"
EX_DIR="$(cd "$SCRIPT_DIR/../examples" && pwd)"
REA_BIN="${REA_BIN:-$SCRIPT_DIR/../build/rea}"
RUNNER_PY="$TESTS_DIR/tools/run_with_timeout.py"
TEST_TIMEOUT="${TEST_TIMEOUT:-25}"

. "$TESTS_DIR/tools/harness_utils.sh"
harness_init

shift_mtime() {
    local path="$1"
    local delta="$2"
    python3 - "$path" "$delta" <<'PY'
import os
import sys
import time

path = sys.argv[1]
delta = float(sys.argv[2])
try:
    st = os.stat(path)
except FileNotFoundError:
    sys.exit(1)
now = time.time()
if delta >= 0:
    base = max(st.st_mtime, now)
else:
    base = min(st.st_mtime, now)
target = base + delta
if target < 0:
    target = 0.0
os.utime(path, (target, target))
PY
}

strip_ansi_inplace() {
    local path="$1"
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]|\e\][^\a]*(?:\a|\e\\)//g' "$path" > "$path.clean"
    mv "$path.clean" "$path"
}

normalise_rea_stdout() {
    strip_ansi_inplace "$1"
}

normalise_rea_stderr() {
    strip_ansi_inplace "$1"
    perl -0 -pe 's/^Compilation successful.*\n//m; s/^Loaded cached bytecode.*\n//m' "$1" > "$1.clean"
    mv "$1.clean" "$1"
}

has_ext_builtin_category() {
    local binary="$1"
    local category="$2"
    set +e
    "$binary" --dump-ext-builtins | grep -Ei "^category[[:space:]]+${category}$" >/dev/null
    local status=$?
    set -e
    return $status
}

run_rea_ext_builtin_dump() {
    local label="$1"
    local tmp_out tmp_err
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    set +e
    "$REA_BIN" --dump-ext-builtins >"$tmp_out" 2>"$tmp_err"
    local status=$?
    set -e

    if [ $status -ne 0 ]; then
        printf 'rea --dump-ext-builtins exited with %d for %s\n' "$status" "$label"
        if [ -s "$tmp_err" ]; then
            printf 'stderr:\n%s\n' "$(cat "$tmp_err")"
        fi
        rm -f "$tmp_out" "$tmp_err"
        return 1
    fi

    if [ -s "$tmp_err" ]; then
        printf 'rea --dump-ext-builtins produced stderr for %s:\n%s\n' "$label" "$(cat "$tmp_err")"
        rm -f "$tmp_out" "$tmp_err"
        return 1
    fi

    if ! python3 - "$tmp_out" <<'PY'
import sys

path = sys.argv[1]
seen = set()
groups = {}
DEFAULT_GROUP = 'default'
with open(path, 'r', encoding='utf-8') as fh:
    for idx, raw_line in enumerate(fh, 1):
        line = raw_line.rstrip('\n')
        if not line:
            continue
        parts = line.split()
        if not parts:
            continue
        tag = parts[0]
        if tag == 'category':
            if len(parts) != 2:
                print(f"Invalid category line {idx}: {raw_line.rstrip()}", file=sys.stderr)
                sys.exit(1)
            seen.add(parts[1])
            groups.setdefault(parts[1], set())
        elif tag == 'group':
            if len(parts) != 3:
                print(f"Invalid group line {idx}: {raw_line.rstrip()}", file=sys.stderr)
                sys.exit(1)
            if parts[1] not in seen:
                print(f"Group references unknown category on line {idx}: {raw_line.rstrip()}", file=sys.stderr)
                sys.exit(1)
            groups.setdefault(parts[1], set()).add(parts[2])
        elif tag == 'function':
            if len(parts) != 4:
                print(f"Invalid function line {idx}: {raw_line.rstrip()}", file=sys.stderr)
                sys.exit(1)
            category, group = parts[1], parts[2]
            if category not in seen:
                print(f"Function references unknown category on line {idx}: {raw_line.rstrip()}", file=sys.stderr)
                sys.exit(1)
            if group != DEFAULT_GROUP and group not in groups.get(category, set()):
                print(f"Function references unknown group on line {idx}: {raw_line.rstrip()}", file=sys.stderr)
                sys.exit(1)
        else:
            print(f"Unknown directive on line {idx}: {raw_line.rstrip()}", file=sys.stderr)
            sys.exit(1)
sys.exit(0)
PY
    then
        printf 'rea --dump-ext-builtins emitted unexpected directives for %s\n' "$label"
        printf '%s\n' "$(cat "$tmp_out")"
        rm -f "$tmp_out" "$tmp_err"
        return 1
    fi

    rm -f "$tmp_out" "$tmp_err"
    return 0
}

rea_cli_version() {
    local tmp_out tmp_err
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    set +e
    "$REA_BIN" -v >"$tmp_out" 2>"$tmp_err"
    local status=$?
    set -e

    local issues=()
    if [ $status -ne 0 ]; then
        issues+=("rea -v exited with $status")
    fi
    if [ -s "$tmp_err" ]; then
        issues+=("rea -v wrote to stderr:\n$(cat "$tmp_err")")
    fi
    if ! grep -q "latest tag:" "$tmp_out"; then
        issues+=("rea -v stdout missing 'latest tag:' line:\n$(cat "$tmp_out")")
    fi

    rm -f "$tmp_out" "$tmp_err"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_cli_strict_dump() {
    local fixture="$TESTS_DIR/tools/fixtures/cli_rea.rea"
    if [ ! -f "$fixture" ]; then
        printf 'Rea CLI fixture missing at %s\n' "$fixture"
        return 1
    fi

    local tmp_out tmp_err
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    set +e
    "$REA_BIN" --no-cache --strict --dump-bytecode-only "$fixture" >"$tmp_out" 2>"$tmp_err"
    local status=$?
    set -e

    local issues=()
    if [ $status -ne 0 ]; then
        issues+=("rea --strict --dump-bytecode-only exited with $status")
    fi
    if ! grep -q "Compiling Main Program AST to Bytecode" "$tmp_err"; then
        issues+=("stderr missing disassembly banner:\n$(cat "$tmp_err")")
    fi

    rm -f "$tmp_out" "$tmp_err"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_cli_no_run() {
    local fixture="$TESTS_DIR/tools/fixtures/cli_rea.rea"
    if [ ! -f "$fixture" ]; then
        printf 'Rea CLI fixture missing at %s\n' "$fixture"
        return 1
    fi

    local tmp_out tmp_err
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    set +e
    "$REA_BIN" --verbose --no-cache --no-run "$fixture" >"$tmp_out" 2>"$tmp_err"
    local status=$?
    set -e

    local issues=()
    if [ $status -ne 0 ]; then
        issues+=("rea --no-run exited with $status")
    fi
    if [ -s "$tmp_out" ]; then
        issues+=("rea --no-run produced stdout:\n$(cat "$tmp_out")")
    fi
    if ! grep -q "Compilation successful" "$tmp_err"; then
        issues+=("stderr missing compilation banner:\n$(cat "$tmp_err")")
    fi
    if grep -q -- "--- executing Program" "$tmp_err"; then
        issues+=("stderr should not announce VM execution:\n$(cat "$tmp_err")")
    fi

    rm -f "$tmp_out" "$tmp_err"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_cli_vm_trace() {
    local fixture="$TESTS_DIR/tools/fixtures/cli_rea.rea"
    if [ ! -f "$fixture" ]; then
        printf 'Rea CLI fixture missing at %s\n' "$fixture"
        return 1
    fi

    local tmp_out tmp_err
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    set +e
    "$REA_BIN" --no-cache --vm-trace-head=3 "$fixture" >"$tmp_out" 2>"$tmp_err"
    local status=$?
    set -e

    local issues=()
    if [ $status -ne 0 ]; then
        issues+=("rea --vm-trace-head exited with $status")
    fi
    if ! grep -q "[VM-TRACE]" "$tmp_err"; then
        issues+=("stderr missing [VM-TRACE] entries:\n$(cat "$tmp_err")")
    fi

    rm -f "$tmp_out" "$tmp_err"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

SKIP_TESTS=()
if [ -n "${REA_SKIP_TESTS:-}" ]; then
    IFS=' ' read -r -a SKIP_TESTS <<< "$REA_SKIP_TESTS"
fi

should_skip() {
    local candidate="$1"
    local entry
    local found=1

    set +u
    for entry in "${SKIP_TESTS[@]}"; do
        if [ "$entry" = "$candidate" ]; then
            found=0
            break
        fi
    done
    set -u

    if [ $found -eq 0 ]; then
        return 0
    fi
    return 1
}

run_rea_fixture() {
    local test_name="$1"
    # Fixtures live in tests/rea/. Pass the path relative to the test cwd
    # ($TESTS_DIR) so the disassembly banner prints the "rea/<name>.rea" tail the
    # .disasm fixtures expect; the binary keeps only the last two path segments.
    local src="$TESTS_DIR/rea/$test_name.rea"
    local src_rel="rea/$test_name.rea"
    local input_file="$TESTS_DIR/rea/$test_name.in"
    local stdout_expect="$TESTS_DIR/rea/$test_name.out"
    local stderr_expect="$TESTS_DIR/rea/$test_name.err"
    local disasm_expect="$TESTS_DIR/rea/$test_name.disasm"
    local sqlite_marker="$TESTS_DIR/rea/$test_name.sqlite"
    local args_file="$TESTS_DIR/rea/$test_name.args"

    if should_skip "$test_name"; then
        harness_report SKIP "rea_${test_name}" "Rea fixture $test_name" "Skipped via REA_SKIP_TESTS"
        return
    fi

    if [ -f "$sqlite_marker" ] && [ "$REA_SQLITE_AVAILABLE" -ne 1 ]; then
        harness_report SKIP "rea_${test_name}" "Rea fixture $test_name" "SQLite builtins disabled"
        return
    fi

    if [ "$REA_THREED_AVAILABLE" -ne 1 ] && { [ "$test_name" = "balls3d_builtin_compare" ] || [ "$test_name" = "balls3d_demo_regression" ]; }; then
        harness_report SKIP "rea_${test_name}" "Rea fixture $test_name" "3D builtins disabled"
        return
    fi

    local arg_list=()
    local args_source=""
    local args_file_present=0
    if [ -f "$args_file" ]; then
        args_file_present=1
        # Read the first line verbatim; empty files intentionally signal
        # "no extra arguments", so treat a failed read as an empty string.
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

    local details=()
    local status="PASS"

    if [ -f "$disasm_expect" ]; then
        local disasm_stderr=$(mktemp)
        set +e
        python3 "$RUNNER_PY" --timeout "$TEST_TIMEOUT" "$REA_BIN" --dump-bytecode-only "$src_rel" > /dev/null 2> "$disasm_stderr"
        local disasm_status=$?
        set -e
        normalise_rea_stderr "$disasm_stderr"
        if [ $disasm_status -ne 0 ]; then
            status="FAIL"
            details+=("Disassembly exited with status $disasm_status")
            if [ -s "$disasm_stderr" ]; then
                details+=("Disassembly stderr:\n$(cat "$disasm_stderr")")
            fi
        else
            set +e
            diff_output=$(diff -u "$disasm_expect" "$disasm_stderr")
            local diff_status=$?
            set -e
            if [ $diff_status -ne 0 ]; then
                status="FAIL"
                if [ $diff_status -eq 1 ]; then
                    details+=("Disassembly mismatch:\n$diff_output")
                else
                    details+=("Disassembly diff failed with status $diff_status")
                fi
            fi
        fi
        rm -f "$disasm_stderr"
    fi

    local actual_out=$(mktemp)
    local actual_err=$(mktemp)

    if [ "$status" = "PASS" ]; then
        local -a cmd=(python3 "$RUNNER_PY" --timeout "$TEST_TIMEOUT" "$REA_BIN")
        if (( ${#arg_list[@]} )); then
            cmd+=("${arg_list[@]}")
        fi
        cmd+=("$src_rel")

        set +e
        if [ -f "$input_file" ]; then
            "${cmd[@]}" < "$input_file" > "$actual_out" 2> "$actual_err"
        else
            "${cmd[@]}" > "$actual_out" 2> "$actual_err"
        fi
        local run_status=$?
        set -e

        normalise_rea_stdout "$actual_out"
        normalise_rea_stderr "$actual_err"

        if [ -f "$stdout_expect" ]; then
            set +e
            diff_output=$(diff -u "$stdout_expect" "$actual_out")
            local diff_status=$?
            set -e
            if [ $diff_status -ne 0 ]; then
                status="FAIL"
                if [ $diff_status -eq 1 ]; then
                    details+=("stdout mismatch:\n$diff_output")
                else
                    details+=("diff on stdout failed with status $diff_status")
                fi
            fi
        else
            if [ -s "$actual_out" ]; then
                status="FAIL"
                details+=("Unexpected stdout:\n$(cat "$actual_out")")
            fi
        fi

        if [ -f "$stderr_expect" ]; then
            set +e
            diff_output=$(diff -u "$stderr_expect" "$actual_err")
            local diff_status=$?
            set -e
            if [ $diff_status -ne 0 ]; then
                status="FAIL"
                if [ $diff_status -eq 1 ]; then
                    details+=("stderr mismatch:\n$diff_output")
                else
                    details+=("diff on stderr failed with status $diff_status")
                fi
            fi
        else
            if [ -s "$actual_err" ]; then
                status="FAIL"
                details+=("Unexpected stderr:\n$(cat "$actual_err")")
            fi
        fi

        if [ $run_status -ne 0 ]; then
            status="FAIL"
            details+=("Rea invocation exited with $run_status")
        fi
    fi

    rm -f "$actual_out" "$actual_err"

    if [ "$status" = "PASS" ]; then
        harness_report PASS "rea_${test_name}" "Rea fixture $test_name"
    else
        harness_report FAIL "rea_${test_name}" "Rea fixture $test_name" "${details[@]}"
    fi
}

rea_hangman_example() {
    local disasm=$(mktemp)
    set +e
    python3 "$RUNNER_PY" --timeout "$TEST_TIMEOUT" "$REA_BIN" --no-cache --dump-bytecode-only "$EX_DIR/base/hangman5" > /dev/null 2> "$disasm"
    local status=$?
    set -e

    normalise_rea_stderr "$disasm"

    if [ $status -ne 0 ]; then
        printf 'Hangman example failed to compile\n'
        printf '%s\n' "$(cat "$disasm")"
        rm -f "$disasm"
        return 1
    fi

    if python3 - "$disasm" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text().splitlines()
def_line = call_line = None
for idx, line in enumerate(text, 1):
    if def_line is None and "DEFINE_GLOBAL" in line and "'wordrepository_vtable'" in line:
        def_line = idx
    if call_line is None and "CALL_USER_PROC" in line and "'hangmangame" in line:
        call_line = idx
if def_line is None:
    print("Hangman example missing wordrepository vtable definition", file=sys.stderr)
    sys.exit(1)
if call_line is None:
    print("Hangman example missing hangmangame call", file=sys.stderr)
    sys.exit(1)
if def_line > call_line:
    print(
        f"wordrepository vtable defined after hangmangame call (def_line={def_line}, call_line={call_line})",
        file=sys.stderr,
    )
    sys.exit(1)
PY
    then
        rm -f "$disasm"
        return 0
    fi

    rm -f "$disasm"
    return 1
}

# Class-field defaults must be compile-time constants (parity with aether's
# FIELD-003 boundary): a default that calls a function, reads another field or
# `myself`, or type-mismatches the field must be rejected at parse time with a
# clear diagnostic and a nonzero exit. Bespoke (not a fixture) because
# run_rea_fixture treats any nonzero exit as a failure.
rea_field_default_rejects_test() {
    local src_dir
    src_dir=$(mktemp -d)
    local issues=()

    cat > "$src_dir/NonConst.rea" <<'EOF'
int g() { return 42; }
class A { int x = g(); }
A a = new A();
EOF
    cat > "$src_dir/FieldRef.rea" <<'EOF'
class B {
  int x = 5;
  int y = myself.x;
}
B b = new B();
EOF
    cat > "$src_dir/Mismatch.rea" <<'EOF'
class C { int x = "oops"; }
C c = new C();
EOF

    local name expect
    for name in NonConst FieldRef Mismatch; do
        case "$name" in
            Mismatch) expect="field default type mismatch" ;;
            *) expect="class field defaults must be compile-time constants" ;;
        esac
        set +e
        (cd "$src_dir" && "$REA_BIN" --no-cache "$name.rea" > "$src_dir/$name.out" 2> "$src_dir/$name.err")
        local status=$?
        set -e
        if [ $status -eq 0 ]; then
            issues+=("$name: expected nonzero exit for invalid field default")
        fi
        if ! grep -q "$expect" "$src_dir/$name.err"; then
            issues+=("$name: missing diagnostic '$expect'; stderr was: $(cat "$src_dir/$name.err")")
        fi
    done

    rm -rf "$src_dir"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

# A class/record type exported from a `module { }` block must stay resolvable
# -- for var-decl typing and for field access (p.x) -- while later units
# (including the importing program) are analyzed. Regression for a bug where
# the class table was freed right after each module's own analysis pass,
# leaving importers unable to resolve fields on an imported type. Bespoke
# (not a fixture) because it needs a second file to import.
rea_module_type_field_access_test() {
    local src_dir
    src_dir=$(mktemp -d)
    local issues=()

    cat > "$src_dir/TypeModule.rea" <<'EOF'
module TypeModule {
    export class Point {
        int x;
        int y;
    }

    export Point makeOrigin() {
        Point p = new Point();
        p.x = 7;
        p.y = 9;
        return p;
    }
}
EOF
    cat > "$src_dir/main.rea" <<'EOF'
#import "TypeModule.rea";

void run() {
    Point p = TypeModule.makeOrigin();
    writeln(p.x);
}

run();
EOF

    set +e
    (cd "$src_dir" && "$REA_BIN" --no-cache main.rea > "$src_dir/main.out" 2> "$src_dir/main.err")
    local status=$?
    set -e
    if [ $status -ne 0 ]; then
        issues+=("main.rea: expected exit 0, got $status; stderr was: $(cat "$src_dir/main.err")")
    fi
    if [ "$(cat "$src_dir/main.out")" != "7" ]; then
        issues+=("main.rea: expected stdout '7', got: $(cat "$src_dir/main.out")")
    fi

    rm -rf "$src_dir"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_module_type_global_var_decl_test() {
    local src_dir
    src_dir=$(mktemp -d)
    local issues=()

    cat > "$src_dir/TypeModule.rea" <<'EOF'
module TypeModule {
    export class Point {
        int x;
        int y;
    }

    export Point makeOrigin() {
        Point p = new Point();
        p.x = 7;
        p.y = 9;
        return p;
    }
}
EOF
    cat > "$src_dir/main.rea" <<'EOF'
#import "TypeModule.rea";

Point p = TypeModule.makeOrigin();
writeln(p.x);
EOF

    set +e
    (cd "$src_dir" && "$REA_BIN" --no-cache main.rea > "$src_dir/main.out" 2> "$src_dir/main.err")
    local status=$?
    set -e
    if [ $status -ne 0 ]; then
        issues+=("main.rea: expected exit 0, got $status; stderr was: $(cat "$src_dir/main.err")")
    fi
    if [ "$(cat "$src_dir/main.out")" != "7" ]; then
        issues+=("main.rea: expected stdout '7', got: $(cat "$src_dir/main.out")")
    fi

    rm -rf "$src_dir"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_module_self_qualified_call_test() {
    local src_dir
    src_dir=$(mktemp -d)
    local issues=()

    cat > "$src_dir/SelfCallModule.rea" <<'EOF'
module SelfCallModule {
    export int helperOne(int x) {
        return x * 2;
    }

    export int helperTwo(int x) {
        return SelfCallModule.helperOne(x);
    }
}
EOF
    cat > "$src_dir/main.rea" <<'EOF'
#import "SelfCallModule.rea";

writeln(SelfCallModule.helperTwo(3));
EOF

    set +e
    (cd "$src_dir" && "$REA_BIN" --no-cache main.rea > "$src_dir/main.out" 2> "$src_dir/main.err")
    local status=$?
    set -e
    if [ $status -ne 0 ]; then
        issues+=("main.rea: expected exit 0, got $status; stderr was: $(cat "$src_dir/main.err")")
    fi
    if [ "$(cat "$src_dir/main.out")" != "6" ]; then
        issues+=("main.rea: expected stdout '6', got: $(cat "$src_dir/main.out")")
    fi

    rm -rf "$src_dir"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_module_type_param_void_bare_call_test() {
    local src_dir
    src_dir=$(mktemp -d)
    local issues=()

    # Regression for https://github.com/emkey1/rea/issues/6: a Void-returning
    # function whose parameter is typed with a class exported from a different
    # module, called as a bare statement (return value discarded), must not
    # have its argument checked against the wrong (VOID) type. rea's own
    # parser always builds a parameter's bare-identifier type as a pointer
    # wrapper up front, so this exact call shape doesn't hit the bug through
    # rea syntax -- the bug needs a frontend (aether) whose parser leaves an
    # unresolved AST_TYPE_REFERENCE in place until a later fixup pass runs.
    # Keep this test anyway: it pins down the compileStatement()/typesMatch()
    # behavior for a cross-module record parameter in bare-statement call
    # position, which is exactly the code path the fix touches.
    cat > "$src_dir/TypeModule.rea" <<'EOF'
module TypeModule {
    export class Point {
        int x;
    }
}
EOF
    cat > "$src_dir/main.rea" <<'EOF'
#import "TypeModule.rea";

void useIt(Point p) {
    writeln(p.x);
}

void main() {
    Point p = new Point();
    p.x = 42;
    useIt(p);
}

main();
EOF

    set +e
    (cd "$src_dir" && "$REA_BIN" --no-cache main.rea > "$src_dir/main.out" 2> "$src_dir/main.err")
    local status=$?
    set -e
    if [ $status -ne 0 ]; then
        issues+=("main.rea: expected exit 0, got $status; stderr was: $(cat "$src_dir/main.err")")
    fi
    if [ "$(cat "$src_dir/main.out")" != "42" ]; then
        issues+=("main.rea: expected stdout '42', got: $(cat "$src_dir/main.out")")
    fi

    rm -rf "$src_dir"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_module_private_helper_collision_test() {
    local src_dir
    src_dir=$(mktemp -d)
    local issues=()

    # Regression for https://github.com/emkey1/rea/issues/5 (finding #8):
    # two modules each declaring their own private (non-exported) helper of
    # the same bare name must not collide. helper() is never exported by
    # either module, so this is purely an implementation-detail name clash.
    cat > "$src_dir/ModA.rea" <<'EOF'
module ModA {
    int helper(int n) { return n + 1; }
    export int viaA(int n) { return helper(n); }
}
EOF
    cat > "$src_dir/ModB.rea" <<'EOF'
module ModB {
    int helper(int n) { return n + 100; }
    export int viaB(int n) { return helper(n); }
}
EOF
    cat > "$src_dir/main.rea" <<'EOF'
#import "ModA.rea";
#import "ModB.rea";

int main() {
    writeln(viaA(1));
    writeln(viaB(1));
    return 0;
}
main();
EOF

    set +e
    (cd "$src_dir" && "$REA_BIN" --no-cache main.rea > "$src_dir/main.out" 2> "$src_dir/main.err")
    local status=$?
    set -e
    if [ $status -ne 0 ]; then
        issues+=("main.rea: expected exit 0, got $status; stderr was: $(cat "$src_dir/main.err")")
    fi
    if [ "$(cat "$src_dir/main.out")" != "$(printf '2\n101')" ]; then
        issues+=("main.rea: expected stdout '2\\n101', got: $(cat "$src_dir/main.out")")
    fi

    rm -rf "$src_dir"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_module_imported_main_not_entry_point_test() {
    local src_dir
    src_dir=$(mktemp -d)
    local issues=()

    # Regression for https://github.com/emkey1/rea/issues/5 (finding #8): a
    # #import'ed file's own top-level main() (declared outside any module
    # block, e.g. for that file's own standalone testing) must not shadow
    # the importer's own main() as the program's entry point.
    cat > "$src_dir/LibWithMain.rea" <<'EOF'
module LibWithMain {
    export int libDouble(int n) { return n * 2; }
}
int main() {
    writeln("lib self-test: ", libDouble(21));
    return 0;
}
main();
EOF
    cat > "$src_dir/consumer.rea" <<'EOF'
#import "LibWithMain.rea";
int main() {
    writeln("consumer: ", libDouble(4));
    return 0;
}
main();
EOF

    set +e
    (cd "$src_dir" && "$REA_BIN" --no-cache consumer.rea > "$src_dir/consumer.out" 2> "$src_dir/consumer.err")
    local status=$?
    set -e
    if [ $status -ne 0 ]; then
        issues+=("consumer.rea: expected exit 0, got $status; stderr was: $(cat "$src_dir/consumer.err")")
    fi
    if [ "$(cat "$src_dir/consumer.out")" != "consumer: 8" ]; then
        issues+=("consumer.rea: expected stdout 'consumer: 8', got: $(cat "$src_dir/consumer.out")")
    fi

    rm -rf "$src_dir"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_cache_reuse_test() {
    local tmp_home src_dir
    tmp_home=$(mktemp -d)
    src_dir=$(mktemp -d)
    cat > "$src_dir/CacheTest.rea" <<'EOF'
writeln("first");
EOF
    shift_mtime "$src_dir/CacheTest.rea" -5

    set +e
    (cd "$src_dir" && HOME="$tmp_home" "$REA_BIN" --verbose CacheTest.rea > "$tmp_home/out1" 2> "$tmp_home/err1")
    local status1=$?
    set -e

    local issues=()
    if [ $status1 -ne 0 ]; then
        issues+=("Initial compile exited with $status1")
    elif ! grep -q 'first' "$tmp_home/out1"; then
        issues+=("Initial compile missing expected stdout")
    else
        set +e
        (cd "$src_dir" && HOME="$tmp_home" "$REA_BIN" --verbose CacheTest.rea > "$tmp_home/out2" 2> "$tmp_home/err2")
        local status2=$?
        set -e
        if [ $status2 -ne 0 ]; then
            issues+=("Cached compile exited with $status2")
        elif ! grep -q 'Loaded cached bytecode' "$tmp_home/err2"; then
            issues+=("Expected cached bytecode notice missing")
        fi
    fi

    rm -rf "$tmp_home" "$src_dir"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

rea_cache_binary_staleness_test() {
    local tmp_home src_dir
    tmp_home=$(mktemp -d)
    src_dir=$(mktemp -d)
    cat > "$src_dir/BinaryTest.rea" <<'EOF'
writeln("first");
EOF
    shift_mtime "$src_dir/BinaryTest.rea" -5

    set +e
    (cd "$src_dir" && HOME="$tmp_home" "$REA_BIN" --verbose BinaryTest.rea > "$tmp_home/out1" 2> "$tmp_home/err1")
    local status1=$?
    set -e

    local issues=()
    if [ $status1 -ne 0 ]; then
        issues+=("Initial compile exited with $status1")
    elif ! grep -q 'first' "$tmp_home/out1"; then
        issues+=("Initial compile missing expected stdout")
    else
        shift_mtime "$REA_BIN" 5
        set +e
        (cd "$src_dir" && HOME="$tmp_home" "$REA_BIN" --verbose BinaryTest.rea > "$tmp_home/out2" 2> "$tmp_home/err2")
        local status2=$?
        set -e
        if [ $status2 -ne 0 ]; then
            issues+=("Recompile after binary touch exited with $status2")
        elif grep -q 'Loaded cached bytecode' "$tmp_home/err2"; then
            issues+=("Cache should have been invalidated after binary change")
        fi
    fi

    rm -rf "$tmp_home" "$src_dir"

    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${issues[@]}"
    return 1
}

if [ ! -x "$REA_BIN" ]; then
    echo "rea binary not found at $REA_BIN" >&2
    exit 1
fi

TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
trap 'rm -rf "$TEST_HOME"' EXIT

# Run from the tests dir so fixture paths like "rea/<name>.rea" resolve and the
# disassembler emits the two-segment "rea/<name>.rea" tail the .disasm fixtures
# pin. Example fixtures are referenced via the absolute $EX_DIR.
cd "$TESTS_DIR"

if details=$(run_rea_ext_builtin_dump rea); then
    harness_report PASS "rea_ext_builtin_dump" "rea --dump-ext-builtins validates structure"
else
    harness_report FAIL "rea_ext_builtin_dump" "rea --dump-ext-builtins validates structure" "$details"
fi

if details=$(rea_cli_version); then
    harness_report PASS "rea_cli_version" "rea -v reports latest tag"
else
    harness_report FAIL "rea_cli_version" "rea -v reports latest tag" "$details"
fi

if details=$(rea_cli_strict_dump); then
    harness_report PASS "rea_cli_strict_dump" "rea --strict --dump-bytecode-only prints banner"
else
    harness_report FAIL "rea_cli_strict_dump" "rea --strict --dump-bytecode-only prints banner" "$details"
fi

if details=$(rea_cli_no_run); then
    harness_report PASS "rea_cli_no_run" "rea --no-run compiles without executing"
else
    harness_report FAIL "rea_cli_no_run" "rea --no-run compiles without executing" "$details"
fi

if details=$(rea_cli_vm_trace); then
    harness_report PASS "rea_cli_vm_trace" "rea --vm-trace-head produces trace"
else
    harness_report FAIL "rea_cli_vm_trace" "rea --vm-trace-head produces trace" "$details"
fi

if has_ext_builtin_category "$REA_BIN" sqlite; then
    REA_SQLITE_AVAILABLE=1
else
    REA_SQLITE_AVAILABLE=0
fi

if has_ext_builtin_category "$REA_BIN" 3d; then
    REA_THREED_AVAILABLE=1
else
    REA_THREED_AVAILABLE=0
fi

shopt -s nullglob
for src in "$TESTS_DIR"/rea/*.rea; do
    test_name=$(basename "$src" .rea)
    run_rea_fixture "$test_name"
done
shopt -u nullglob

if details=$(rea_hangman_example); then
    harness_report PASS "rea_hangman_example" "Hangman example emits vtable before constructor"
else
    harness_report FAIL "rea_hangman_example" "Hangman example emits vtable before constructor" "$details"
fi

if details=$(rea_field_default_rejects_test); then
    harness_report PASS "rea_field_default_rejects" "Non-constant/mismatched class field defaults are rejected"
else
    harness_report FAIL "rea_field_default_rejects" "Non-constant/mismatched class field defaults are rejected" "$details"
fi

if details=$(rea_cache_reuse_test); then
    harness_report PASS "rea_cache_reuse" "Cache reuse surfaces bytecode reuse notice"
else
    harness_report FAIL "rea_cache_reuse" "Cache reuse surfaces bytecode reuse notice" "$details"
fi

if details=$(rea_module_type_field_access_test); then
    harness_report PASS "rea_module_type_field_access" "Imported module's class type stays resolvable for field access"
else
    harness_report FAIL "rea_module_type_field_access" "Imported module's class type stays resolvable for field access" "$details"
fi

if details=$(rea_module_type_global_var_decl_test); then
    harness_report PASS "rea_module_type_global_var_decl" "Imported module's class type resolves for a top-level (global-scope) var decl"
else
    harness_report FAIL "rea_module_type_global_var_decl" "Imported module's class type resolves for a top-level (global-scope) var decl" "$details"
fi

if details=$(rea_module_self_qualified_call_test); then
    harness_report PASS "rea_module_self_qualified_call" "A module function can call a sibling export through its own qualified name"
else
    harness_report FAIL "rea_module_self_qualified_call" "A module function can call a sibling export through its own qualified name" "$details"
fi

if details=$(rea_module_type_param_void_bare_call_test); then
    harness_report PASS "rea_module_type_param_void_bare_call" "A Void function's cross-module record parameter type-checks correctly when called as a bare statement"
else
    harness_report FAIL "rea_module_type_param_void_bare_call" "A Void function's cross-module record parameter type-checks correctly when called as a bare statement" "$details"
fi

if details=$(rea_cache_binary_staleness_test); then
    harness_report PASS "rea_cache_binary_staleness" "Binary timestamp invalidates cached bytecode"
else
    harness_report FAIL "rea_cache_binary_staleness" "Binary timestamp invalidates cached bytecode" "$details"
fi

if details=$(rea_module_private_helper_collision_test); then
    harness_report PASS "rea_module_private_helper_collision" "Two modules' same-named private helpers do not collide"
else
    harness_report FAIL "rea_module_private_helper_collision" "Two modules' same-named private helpers do not collide" "$details"
fi

if details=$(rea_module_imported_main_not_entry_point_test); then
    harness_report PASS "rea_module_imported_main_not_entry_point" "An imported file's own top-level main() does not shadow the importer's main()"
else
    harness_report FAIL "rea_module_imported_main_not_entry_point" "An imported file's own top-level main() does not shadow the importer's main()" "$details"
fi

harness_summary "Rea"
if harness_exit_code; then
    exit 0
fi
exit 1
