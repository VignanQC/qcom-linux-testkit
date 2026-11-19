# msm_bo Test

<!-- Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries. -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

## Overview
The msm_bo test is an IGT (Intel GPU Tools) test that validates msm GEM buffer object handling on the Adreno GPU.

## Test Description
This test validates:
- Buffer object allocation with valid and invalid flags
- Buffer object mmap and CPU access
- Buffer object info queries

## Prerequisites
- IGT GPU tools must be installed on the target device
- The GPU must be driven by the upstream msm DRM driver

## Usage

### Basic Usage (Default)
```bash
./run-test.sh msm_bo
```
The test will automatically use the binary at `/usr/libexec/igt-gpu-tools/msm_bo`

### With Custom Binary Path
```bash
./run-test.sh msm_bo --bin-path /custom/path/to/msm_bo
```

### Run a Single Subtest
```bash
./run-test.sh msm_bo --subtest <subtest-name>
```
List the available subtests with `/usr/libexec/igt-gpu-tools/msm_bo --list-subtests`.

### Custom Timeout
```bash
./run-test.sh msm_bo --timeout <seconds>
```
The default timeout is 300 seconds. It can also be set with the `IGT_TIMEOUT` environment variable.

### Help
```bash
cd Runner/suites/Multimedia/Graphics/igt-gpu-tools/msm_bo
./run.sh --help
```

## Test Results
The test generates:
- **Result file**: `msm_bo.res` - Contains PASS/FAIL/SKIP status
- **Log file**: `msm_bo_log.txt` - Contains detailed test output
- **Kernel log**: `dmesg/dmesg_new_errors.log` - msm/adreno/drm kernel errors raised during the run

## Expected Behavior
- **PASS**: All subtests succeed or some subtests succeed with others skipped
- **SKIP**: The binary is missing, KGSL owns the GPU, IGT exits with code 77, or all subtests are skipped
- **FAIL**: One or more subtests fail, the test times out, the test exits with a non-zero code, or an invalid argument is given

## Common Issues
1. **Binary Not Found**: Ensure IGT GPU tools are installed:
   ```bash
   ls -l /usr/libexec/igt-gpu-tools/msm_bo
   ```

2. **Test Skipped on KGSL images**: The msm_* tests need the upstream msm GPU driver. Check the GPU owner:
   ```bash
   ls /dev/kgsl-3d0
   cat /sys/module/msm/parameters/skip_gpu
   ```

## Notes
- Weston is not stopped, the test uses the GPU only.
- Exit code 77 indicates a SKIP condition (standard IGT behavior)
- Test output is parsed for per-subtest SUCCESS, FAIL and SKIP results
