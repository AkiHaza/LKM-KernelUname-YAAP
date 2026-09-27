# YAAP KernelMask

[中文说明](README.zh-CN.md)

KernelMask is an experimental external module for the OnePlus 12 YAAP `seventeen` kernel. It changes only two fields in the initial UTS namespace:

| Parameter | Command | Example |
|---|---|---|
| `release` | `uname -r` | `6.1.174-g638ecc425319` |
| `version` | `uname -v` | `#1 SMP PREEMPT Wed Sep 16 23:10:11 CEST 2026` |

For `Linux localhost 6.1.174-g638ecc425319 #1 SMP PREEMPT Wed Sep 16 23:10:11 CEST 2026 aarch64 Android`, the module changes only the two fields between `localhost` and `aarch64`. It does not change `Linux`, `localhost`, `aarch64`, or `Android`. The default configuration is disabled, and an empty field preserves its original value.

## Build and install

Run **Build KernelMask for YAAP** in GitHub Actions. Install the resulting `yaap-seventeen_kernelmask-ksu.zip` through KernelSU Manager. Open the WebUI, enter the `release` and `version` values, enable the module, and choose **保存配置**. A changed `release` is saved for the next boot, so reboot the device. The status view displays the installed module version, `uname -a`, `uname -r/-v`, `/proc/version`, `/proc/sys/kernel/osrelease`, `/proc/sys/kernel/version`, and recent service logs. Run a new Duck Detector scan after reboot.

The output must match the running YAAP kernel's source revisions, ABI symbol CRCs, configuration, and toolchain. The workflow records the exact kernel and modules revisions. A successful CI build does not prove that the `.ko` can load on a device running a different YAAP commit. If loading fails, disable or remove the KernelSU module and inspect `/data/adb/kernelmask/service.log` and `dmesg`.

Configuration is stored in `/data/adb/kernelmask/config.conf` and preserved on uninstall. Each field accepts up to 64 printable ASCII characters except quotes and backslashes. `release` cannot contain spaces; `version` can. A failed WebUI reload restores the previous configuration and attempts to reload the prior module. Legacy `sysname`, `nodename`, `machine`, and `domainname` configuration keys are read but ignored, then removed on the next WebUI save.

## Duck Detector coverage

[Duck Detector Refactoring's Kernel Check](https://github.com/eltavine/Duck-Detector-Refactoring/tree/56bd5dc501a27c87a4c00cbf8ad9d5c58352ccfb/feature/kernelcheck) compares the raw `uname()` syscall, `uname -r`, `/proc/version`, `/proc/sys/kernel/osrelease`, `/proc/sys/kernel/version`, and `System.getProperty("os.version")`, which Zygote cached during startup. Updating the initial UTS `release` and `version` makes the live `uname` and corresponding `/proc` exports read the same pair of values. KernelSU's `post-fs-data.sh` loads the module early so Zygote normally caches the replacement `release`. A changed `release` is now saved for the next boot instead of being applied after Zygote starts. If a new post-reboot scan still diverges, inspect the service log for `phase=boot`, `zygote=absent`, and other modules that may change release later. Do not copy a stale value such as `6.1.177-@2ecbce56` from a report into the new identity: the `@` marker is separately suspicious.

The detector also scans identity text for community kernel keywords, unusual major versions, non-Latin characters, and `@` mentions. Supply complete, plausible values from the intended kernel build. This module does not generate or sanitize them, and it does not alter the detector's other checks.

Only the initial UTS namespace is changed. Namespaces created earlier may retain their original values; namespaces cloned while the module is active may retain replacements after unload. `/proc/version` still contains the compiler and build host baked into the kernel. The module does not change the kernel image, module ABI/vermagic, `/proc/modules`, `/proc/kallsyms`, mounts, SELinux, bootconfig, or historical `dmesg` lines.

## Implementation

`kernel/kernelmask.c` uses YAAP's exported `init_uts_ns` and `stop_machine` symbols to apply only `release` and `version`. On unload it restores each original field only if that field still contains the module's replacement. YAAP does not export its internal `uts_sem` to external modules, so `stop_machine` provides a best-effort update boundary; concurrent reads may still observe a short transition. Fully lock-consistent updates require an in-tree change using the UTS lock.

`ksu-module/` contains the KernelSU wrapper, persistent configuration, and offline WebUI. It loads the module from `post-fs-data.sh`, with `service.sh` as a fallback. `.github/workflows/build-yaap.yml` builds against the current `seventeen` kernel and modules tips with clang-r596125 and normal `modpost`.

## Local build

After building the matching kernel and producing `Module.symvers`:

```sh
make -C "$KERNEL_DIR" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  M="$PWD/kernel" src="$PWD/kernel" modules
./tools/validate.sh kernel/kernelmask.ko "$(cat "$KERNEL_OUT/include/config/kernel.release")"
./tools/package_ksu.sh kernel/kernelmask.ko out/yaap-kernelmask-ksu.zip
```

Do not apply LKM4YAAP's KernelSU-specific empty-`__versions` `modpost` patch. Normal `insmod` needs YAAP's non-empty symbol CRC section.
