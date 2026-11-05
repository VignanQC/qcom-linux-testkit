#!/bin/sh
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# Shared runner for IGT GPU tools msm_* suites.
# Source functestlib.sh before this file. The caller must call
# test_result_init before igt_msm_run_suite.

IGT_DEFAULT_BIN_DIR="/usr/libexec/igt-gpu-tools"

# igt_msm_usage <test-name> <default-timeout>
# Print the command-line usage of an IGT msm suite to stdout.
igt_msm_usage() {
    cat <<EOF
Usage: ./run.sh [options]

Options:
  --bin-path PATH   IGT binary to run (default: $IGT_DEFAULT_BIN_DIR/$1)
  --subtest NAME    Run only this subtest (forwarded as --run-subtest NAME)
  --timeout SECS    Timeout for the IGT invocation (default: \$IGT_TIMEOUT or $2)
  -h, --help        Show this help and exit

Environment:
  IGT_TIMEOUT       Same as --timeout. The option takes precedence.
EOF
}

# igt_msm_parse_args <test-name> <default-timeout> [args...]
# Set IGT_BIN, IGT_SUBTEST and IGT_RUN_TIMEOUT from the arguments.
# Invalid arguments finish the testcase with FAIL before any DUT state changes.
igt_msm_parse_args() {
    ipa_name="$1"
    ipa_default_timeout="$2"
    shift 2

    IGT_BIN="$IGT_DEFAULT_BIN_DIR/$ipa_name"
    IGT_SUBTEST=""
    IGT_RUN_TIMEOUT="${IGT_TIMEOUT:-$ipa_default_timeout}"

    while [ $# -gt 0 ]; do
        case "$1" in
            --bin-path|--subtest|--timeout)
                if [ $# -lt 2 ] || [ -z "$2" ]; then
                    test_result_finish "FAIL" "Missing value for $1"
                fi
                case "$1" in
                    --bin-path)
                        IGT_BIN="$2"
                        ;;
                    --subtest)
                        IGT_SUBTEST="$2"
                        ;;
                    --timeout)
                        IGT_RUN_TIMEOUT="$2"
                        ;;
                esac
                shift 2
                continue
                ;;
            -h|--help)
                igt_msm_usage "$ipa_name" "$ipa_default_timeout"
                exit 0
                ;;
            *)
                test_result_finish "FAIL" "Unknown argument: $1"
                ;;
        esac
    done

    case "$IGT_RUN_TIMEOUT" in
        ''|*[!0-9]*|0)
            test_result_finish "FAIL" "Timeout must be a positive integer, got: '$IGT_RUN_TIMEOUT'"
            ;;
    esac
}

# igt_count_subtests <log-file> <status-regex>
# Print the number of top-level IGT "Subtest <name>: <status>" lines.
# Dynamic subtests are not counted separately; their parent subtest reports
# the aggregate status.
igt_count_subtests() {
    ics_count=$(grep -Ec "^Subtest [^:]+: ($2)" "$1" 2>/dev/null)
    case "$ics_count" in
        ''|*[!0-9]*)
            ics_count=0
            ;;
    esac
    printf '%s\n' "$ics_count"
}

# igt_msm_run_suite <test-name> <test-dir> <default-timeout> [args...]
# Validate prerequisites, run one IGT msm_* binary and finish the testcase.
# The GPU must be driven by the upstream msm DRM driver. A KGSL-owned GPU or
# a missing binary reports SKIP. A missing msm DRM device is reported by IGT
# itself with exit code 77 (SKIP).
igt_msm_run_suite() {
    irs_name="$1"
    irs_dir="$2"
    irs_default_timeout="$3"
    shift 3

    igt_msm_parse_args "$irs_name" "$irs_default_timeout" "$@"

    if ! cd "$irs_dir"; then
        test_result_finish "FAIL" "cd failed: $irs_dir"
    fi
    if [ ! -w "$irs_dir" ]; then
        test_result_finish "FAIL" "Cannot write to test directory: $irs_dir"
    fi

    log_info "-------------------Starting $irs_name Testcase-----------------------------"

    if [ ! -x "$IGT_BIN" ]; then
        log_info "Install igt-gpu-tools in the image or pass --bin-path"
        test_result_finish "SKIP" "$irs_name binary not found or not executable at: $IGT_BIN"
    fi
    log_info "Using IGT binary: $IGT_BIN"

    # Results are published under the suite name, so running a different
    # IGT binary would report its verdict under the wrong testcase.
    irs_bin_name="$(basename "$IGT_BIN")"
    if [ "$irs_bin_name" != "$irs_name" ]; then
        test_result_finish "FAIL" "Binary name '$irs_bin_name' does not match testcase '$irs_name' ($IGT_BIN)"
    fi

    if [ -e /dev/kgsl-3d0 ]; then
        test_result_finish "SKIP" "GPU is owned by KGSL (/dev/kgsl-3d0), msm_* tests need the upstream msm GPU driver"
    fi

    irs_log="$irs_dir/${irs_name}_log.txt"
    set -- "$IGT_BIN"
    if [ -n "$IGT_SUBTEST" ]; then
        set -- "$@" --run-subtest "$IGT_SUBTEST"
    fi

    # Baseline of pre-existing kernel errors, so only errors raised during
    # this run are reported. Its log output is suppressed to avoid printing
    # errors left behind by earlier tests.
    irs_dmesg_dir="$irs_dir/dmesg"
    irs_dmesg_modules='msm[^:]*|adreno[^:]*|\[drm'
    irs_dmesg_exclude="dummy regulator|supply [^ ]+ not found|using dummy regulator"
    scan_dmesg_errors "$irs_dmesg_dir/pre" "$irs_dmesg_modules" "$irs_dmesg_exclude" >/dev/null 2>&1 || true

    trap 'managed_timeout_cancel_bounded 5 || true; test_result_finish "FAIL" "$irs_name interrupted by signal"' INT TERM HUP

    log_info "Running: $* (timeout: ${IGT_RUN_TIMEOUT}s)"
    run_with_managed_timeout "$IGT_RUN_TIMEOUT" "$irs_dir" "$irs_name" "$@" >"$irs_log" 2>&1
    irs_rc=$?

    trap - INT TERM HUP
    log_info "IGT output written to: $irs_log"

    scan_dmesg_errors "$irs_dmesg_dir" "$irs_dmesg_modules" "$irs_dmesg_exclude" >/dev/null 2>&1 || true
    irs_new_errors="$irs_dmesg_dir/dmesg_new_errors.log"
    if [ -s "$irs_dmesg_dir/pre/dmesg_errors.log" ]; then
        grep -vxF -f "$irs_dmesg_dir/pre/dmesg_errors.log" \
            "$irs_dmesg_dir/dmesg_errors.log" >"$irs_new_errors" 2>/dev/null || true
    else
        cp "$irs_dmesg_dir/dmesg_errors.log" "$irs_new_errors" 2>/dev/null || : >"$irs_new_errors"
    fi
    if [ -s "$irs_new_errors" ]; then
        log_warn "msm/adreno/drm kernel errors raised during $irs_name (see $irs_new_errors):"
        while IFS= read -r irs_line; do
            log_warn "[dmesg] $irs_line"
        done <"$irs_new_errors"
    else
        log_info "No new msm/adreno/drm kernel errors during $irs_name"
    fi

    irs_pass=$(igt_count_subtests "$irs_log" "SUCCESS")
    irs_fail=$(igt_count_subtests "$irs_log" "FAIL|CRASH|TIMEOUT")
    irs_skip=$(igt_count_subtests "$irs_log" "SKIP")
    irs_total=$((irs_pass + irs_fail + irs_skip))
    log_info "Subtest results: SUCCESS=$irs_pass FAIL=$irs_fail SKIP=$irs_skip TOTAL=$irs_total rc=$irs_rc"

    if [ "$irs_fail" -gt 0 ]; then
        grep -E "^Subtest [^:]+: (FAIL|CRASH|TIMEOUT)" "$irs_log" | while IFS= read -r irs_line; do
            log_fail "$irs_line"
        done
    fi

    log_info "-------------------Completed $irs_name Testcase----------------------------"

    if [ "$irs_rc" -eq 124 ]; then
        test_result_finish "FAIL" "$irs_name timed out after ${IGT_RUN_TIMEOUT}s"
    elif [ "$irs_fail" -gt 0 ]; then
        test_result_finish "FAIL" "$irs_name: $irs_fail of $irs_total subtest(s) failed"
    elif [ "$irs_rc" -eq 77 ]; then
        test_result_finish "SKIP" "$irs_name skipped by IGT (exit code 77)"
    elif [ "$irs_rc" -ne 0 ]; then
        test_result_finish "FAIL" "$irs_name exited with code $irs_rc"
    elif [ "$irs_pass" -gt 0 ]; then
        test_result_finish "PASS" "$irs_name: $irs_pass subtest(s) passed, $irs_skip skipped"
    elif [ "$irs_skip" -gt 0 ]; then
        test_result_finish "SKIP" "$irs_name: all $irs_skip subtest(s) skipped"
    fi
    test_result_finish "PASS" "$irs_name exited with code 0"
}
