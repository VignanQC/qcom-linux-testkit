#!/bin/sh
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# Shared runner for IGT GPU tools msm_* tests.
# Requires functestlib.sh and lib_module_reload.sh to be sourced first.
#
# POSIX sh has no local variables, so each function prefixes its variables
# (igt_arg_, igt_cnt_, igt_run_) to avoid overwriting the caller's variables.

IGT_DEFAULT_BIN_DIR="/usr/libexec/igt-gpu-tools"

# igt_msm_usage <test-name> <default-timeout>
# Print the command-line usage.
igt_msm_usage() {
    cat <<EOF
Usage: ./run.sh [options]

Options:
  --bin-path PATH   IGT binary to run (default: $IGT_DEFAULT_BIN_DIR/$1)
  --subtest NAME    Run only this subtest
  --timeout SECS    Timeout in seconds (default: \$IGT_TIMEOUT or $2)
  -h, --help        Show this help and exit
EOF
}

# igt_msm_finish <test-name> <PASS|FAIL|SKIP> <reason>
# Log the final verdict with its reason and write the result file.
igt_msm_finish() {
    test_result_finish "$2" "$1 $2 - $3"
}

# igt_msm_parse_args <test-name> <default-timeout> [args...]
# Set IGT_BIN, IGT_SUBTEST and IGT_RUN_TIMEOUT. Invalid arguments FAIL.
igt_msm_parse_args() {
    igt_arg_name="$1"
    igt_arg_default_timeout="$2"
    shift 2

    IGT_BIN="$IGT_DEFAULT_BIN_DIR/$igt_arg_name"
    IGT_SUBTEST=""
    IGT_RUN_TIMEOUT="${IGT_TIMEOUT:-$igt_arg_default_timeout}"

    while [ $# -gt 0 ]; do
        case "$1" in
            --bin-path|--subtest|--timeout)
                if [ $# -lt 2 ] || [ -z "$2" ]; then
                    igt_msm_finish "$igt_arg_name" FAIL "missing value for $1"
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
                ;;
            -h|--help)
                igt_msm_usage "$igt_arg_name" "$igt_arg_default_timeout"
                exit 0
                ;;
            *)
                igt_msm_finish "$igt_arg_name" FAIL "unknown argument: $1"
                ;;
        esac
    done

    case "$IGT_RUN_TIMEOUT" in
        ''|*[!0-9]*|0)
            igt_msm_finish "$igt_arg_name" FAIL "timeout must be a positive integer, value=$IGT_RUN_TIMEOUT"
            ;;
    esac
}

# igt_count_subtests <log-file> <status-regex>
# Print the number of "Subtest <name>: <status>" lines in the IGT log.
igt_count_subtests() {
    igt_cnt_count=$(grep -Ec "^Subtest [^:]+: ($2)" "$1" 2>/dev/null)
    case "$igt_cnt_count" in
        ''|*[!0-9]*)
            igt_cnt_count=0
            ;;
    esac
    printf '%s\n' "$igt_cnt_count"
}

# igt_msm_run_suite <test-name> <test-dir> <default-timeout> [args...]
# Run one IGT msm_* binary and write the testcase result.
igt_msm_run_suite() {
    igt_run_name="$1"
    igt_run_dir="$2"
    igt_run_default_timeout="$3"
    shift 3

    igt_msm_parse_args "$igt_run_name" "$igt_run_default_timeout" "$@"

    if ! cd "$igt_run_dir" || [ ! -w "$igt_run_dir" ]; then
        igt_msm_finish "$igt_run_name" FAIL "test directory is not writable: $igt_run_dir"
    fi

    igt_run_os_id="unknown"
    if [ -r /etc/os-release ]; then
        igt_run_os_id="$(sed -n 's/^ID=//p' /etc/os-release | head -n 1 | tr -d '"')"
        [ -n "$igt_run_os_id" ] || igt_run_os_id="unknown"
    fi

    igt_run_gpu_mode="unknown"
    if command -v mrv_qcom_gpu_boot_mode >/dev/null 2>&1; then
        igt_run_gpu_mode="$(mrv_qcom_gpu_boot_mode 2>/dev/null || true)"
        [ -n "$igt_run_gpu_mode" ] || igt_run_gpu_mode="unknown"
    fi

    log_info "--------------------------------------------------------------------------"
    log_info "------------------- Starting $igt_run_name Testcase --------------------------"
    log_info "Detected OS, $igt_run_os_id"
    log_info "Kernel, $(uname -r)"
    log_info "GPU boot mode, $igt_run_gpu_mode"
    log_info "Config, BIN=$IGT_BIN SUBTEST=${IGT_SUBTEST:-all} TIMEOUT=${IGT_RUN_TIMEOUT}s"

    if [ ! -x "$IGT_BIN" ]; then
        igt_msm_finish "$igt_run_name" SKIP "IGT binary is unavailable: $IGT_BIN"
    fi

    if [ "$(basename "$IGT_BIN")" != "$igt_run_name" ]; then
        igt_msm_finish "$igt_run_name" FAIL "binary $(basename "$IGT_BIN") does not match testcase $igt_run_name"
    fi

    if [ "$igt_run_gpu_mode" = "kgsl" ] || [ -e /dev/kgsl-3d0 ]; then
        igt_msm_finish "$igt_run_name" SKIP "GPU is owned by KGSL, msm GPU driver is required"
    fi

    igt_run_log="$igt_run_dir/${igt_run_name}_log.txt"
    set -- "$IGT_BIN"
    if [ -n "$IGT_SUBTEST" ]; then
        set -- "$@" --run-subtest "$IGT_SUBTEST"
    fi

    # Baseline the kernel log so only errors raised by this run are reported.
    igt_run_dmesg_dir="$igt_run_dir/dmesg"
    igt_run_dmesg_modules='msm[^:]*|adreno[^:]*|\[drm'
    igt_run_dmesg_exclude="dummy regulator|supply [^ ]+ not found|using dummy regulator"
    scan_dmesg_errors "$igt_run_dmesg_dir/pre" "$igt_run_dmesg_modules" "$igt_run_dmesg_exclude" >/dev/null 2>&1 || true

    trap 'managed_timeout_cancel_bounded 5 || true; igt_msm_finish "$igt_run_name" FAIL "interrupted by signal"' INT TERM HUP

    log_info "Using IGT binary, $IGT_BIN"
    log_info "Launching $* with timeout ${IGT_RUN_TIMEOUT}s"
    run_with_managed_timeout "$IGT_RUN_TIMEOUT" "$igt_run_dir" "$igt_run_name" "$@" >"$igt_run_log" 2>&1
    igt_run_rc=$?

    trap - INT TERM HUP

    igt_run_version="$(sed -n 's/^IGT-Version: //p' "$igt_run_log" 2>/dev/null | head -n 1)"
    log_info "IGT version, ${igt_run_version:-unknown}"
    log_info "IGT log, $igt_run_log"

    scan_dmesg_errors "$igt_run_dmesg_dir" "$igt_run_dmesg_modules" "$igt_run_dmesg_exclude" >/dev/null 2>&1 || true
    igt_run_new_errors="$igt_run_dmesg_dir/dmesg_new_errors.log"
    if [ -s "$igt_run_dmesg_dir/pre/dmesg_errors.log" ]; then
        grep -vxF -f "$igt_run_dmesg_dir/pre/dmesg_errors.log" \
            "$igt_run_dmesg_dir/dmesg_errors.log" >"$igt_run_new_errors" 2>/dev/null || true
    else
        cp "$igt_run_dmesg_dir/dmesg_errors.log" "$igt_run_new_errors" 2>/dev/null || : >"$igt_run_new_errors"
    fi
    if [ -s "$igt_run_new_errors" ]; then
        igt_run_err_count=$(wc -l <"$igt_run_new_errors" | tr -d '[:space:]')
        log_warn "Kernel errors raised during $igt_run_name, count=$igt_run_err_count (capped at 20 lines), $igt_run_new_errors"
        head -n 20 "$igt_run_new_errors" | while IFS= read -r igt_run_line; do
            log_warn "[dmesg] $igt_run_line"
        done
    else
        log_info "No new msm/adreno/drm kernel errors"
    fi

    igt_run_pass=$(igt_count_subtests "$igt_run_log" "SUCCESS")
    igt_run_fail=$(igt_count_subtests "$igt_run_log" "FAIL|CRASH|TIMEOUT")
    igt_run_skip=$(igt_count_subtests "$igt_run_log" "SKIP")
    igt_run_total=$((igt_run_pass + igt_run_fail + igt_run_skip))
    log_info "Subtest results, SUCCESS=$igt_run_pass FAIL=$igt_run_fail SKIP=$igt_run_skip TOTAL=$igt_run_total rc=$igt_run_rc"

    grep -E "^Subtest [^:]+: (FAIL|CRASH|TIMEOUT)" "$igt_run_log" 2>/dev/null | while IFS= read -r igt_run_line; do
        log_fail "$igt_run_line"
    done
    grep -E "^Subtest [^:]+: SKIP" "$igt_run_log" 2>/dev/null | while IFS= read -r igt_run_line; do
        log_skip "$igt_run_line"
    done

    igt_run_final="PASS"
    igt_run_reason="$igt_run_pass subtest(s) passed, $igt_run_skip skipped"
    if [ "$igt_run_rc" -eq 124 ]; then
        igt_run_final="FAIL"
        igt_run_reason="timed out after ${IGT_RUN_TIMEOUT}s"
    elif [ "$igt_run_fail" -gt 0 ]; then
        igt_run_final="FAIL"
        igt_run_reason="$igt_run_fail of $igt_run_total subtest(s) failed"
    elif [ "$igt_run_rc" -eq 77 ]; then
        igt_run_final="SKIP"
        igt_run_reason="IGT reported SKIP, exit code 77"
    elif [ "$igt_run_rc" -ne 0 ]; then
        igt_run_final="FAIL"
        igt_run_reason="IGT exited with code $igt_run_rc"
    elif [ "$igt_run_pass" -eq 0 ] && [ "$igt_run_skip" -gt 0 ]; then
        igt_run_final="SKIP"
        igt_run_reason="all $igt_run_skip subtest(s) skipped"
    fi

    if [ "$igt_run_final" = "FAIL" ]; then
        log_info "----- Last 200 IGT log lines -----"
        tail -n 200 "$igt_run_log" 2>/dev/null | while IFS= read -r igt_run_line; do
            log_info "[igt] $igt_run_line"
        done
        log_info "----- End IGT log -----"
    fi

    log_info "------------------- Completed $igt_run_name Testcase -------------------------"
    igt_msm_finish "$igt_run_name" "$igt_run_final" "$igt_run_reason"
}
