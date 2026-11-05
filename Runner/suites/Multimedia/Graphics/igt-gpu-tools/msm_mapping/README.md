# msm_mapping Test

<!-- Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries. -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

## Overview
Runs the IGT GPU tools `msm_mapping` test. Validates GPU address-space mappings and that invalid GPU accesses raise IOMMU faults.

This test deliberately makes the GPU access protected or invalid addresses.
`gpu fault` and `hangcheck recover!` kernel messages naming `msm_mapping` as
the offending task are expected and are reported as warnings only.

## Prerequisites
- `igt-gpu-tools` installed in the image. The default binary is
  `/usr/libexec/igt-gpu-tools/msm_mapping`. The test does not install packages.
- The GPU is driven by the upstream msm DRM driver. On images using the
  KGSL/Adreno overlay (`/dev/kgsl-3d0` present) the test reports SKIP.
- Root access, for DRM and kernel log access.

The test uses the GPU through DRM only and does not stop or restart Weston.

## Usage
```sh
cd <Path in device>/Runner
./run-test.sh msm_mapping
./run-test.sh msm_mapping --bin-path /custom/path/msm_mapping
./run-test.sh msm_mapping --subtest <subtest-name>
./run-test.sh msm_mapping --timeout 1200
```

Direct invocation:
```sh
cd Runner/suites/Multimedia/Graphics/igt-gpu-tools/msm_mapping
./run.sh --help
```

List the available subtests with:
```sh
/usr/libexec/igt-gpu-tools/msm_mapping --list-subtests
```

| Option | Default | Description |
|---|---|---|
| `--bin-path PATH` | `/usr/libexec/igt-gpu-tools/msm_mapping` | IGT binary to run |
| `--subtest NAME` | all subtests | Forwarded as `--run-subtest NAME` |
| `--timeout SECS` | `IGT_TIMEOUT` or 300 | Timeout for the IGT invocation |

Invalid or unknown arguments, or a non-positive timeout, report FAIL before
the test runs.

## Results and logs
Written to the test directory:
- `msm_mapping.res`: `msm_mapping PASS|FAIL|SKIP`
- `msm_mapping_log.txt`: full IGT output
- `msm_mapping_stdout_<timestamp>.log`: runner output (when launched via `run-test.sh`)
- `dmesg/dmesg_new_errors.log`: msm/adreno/drm kernel errors raised during this
  run (errors already present before the run are excluded). Reported as
  warnings only, they do not change the result.
- `dmesg/dmesg_snapshot.log`, `dmesg/pre/`: kernel log after and before the run.

## Result conditions
- **PASS**: IGT exits 0 and at least one subtest reports SUCCESS, with no
  failing subtest. Skipped subtests are allowed.
- **SKIP**: binary missing, GPU owned by KGSL, IGT exit code 77 (e.g. no msm GPU),
  or all subtests skipped.
- **FAIL**: any subtest reports FAIL, CRASH or TIMEOUT, the run exceeds the
  timeout, IGT exits non-zero (other than 77), invalid arguments, the binary name does
  not match the testcase name, or the run is interrupted.
