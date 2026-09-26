# YAAP KernelMask

[中文说明](README.zh-CN.md)

KernelMask is an experimental external kernel module for the OnePlus 12 YAAP
`seventeen` kernel. It changes the *init UTS namespace*'s public `sysname`,
`nodename`, kernel `release`, `version` (including the displayed build date),
`machine`, and `domainname` while loaded. Empty values leave the original field
alone. The default configuration is **disabled**.

The module is intentionally narrower than SUSFS. It does not hide modules,
`/proc/kallsyms`, mounts, bootconfig, SELinux state, or historical `dmesg`
lines. The built-in compiler/host portion of `/proc/version` and the real
module ABI/vermagic also remain unchanged. Existing non-init UTS namespaces may
retain their original values; this module does not hook syscalls to cover them.

## Components

- `kernel/kernelmask.c`: a normal GPL external module using YAAP's exported
  `init_uts_ns` and `stop_machine` symbols. It saves the original fields,
  applies selected replacements while CPUs are stopped, and restores only fields that still
  contain its replacement on unload.
- `ksu-module/`: KernelSU module wrapper, persistent configuration, and offline
  WebUI. The module is loaded from `post-fs-data.sh` when available and
  `service.sh` as a fallback.
- `.github/workflows/build-yaap.yml`: a manually triggered YAAP build. It uses
  the latest `seventeen` tips from AkiHaza's kernel and modules repositories,
  clang-r596125, a complete YAAP kernel symbol build, and normal `modpost`.

## Build and install

Run **Build KernelMask for YAAP** in GitHub Actions. Download the artifact; it
contains `yaap-seventeen_kernelmask.ko`, `yaap-seventeen_kernelmask-ksu.zip`, a checksum list, and
the exact kernel/modules revisions used. Install the zip through KernelSU
Manager. Open its WebUI, enter only the fields you want to override, enable the
module, and choose **保存并重载**. `uname -a` and `/proc/version` in the WebUI show
the resulting view.

The output is **not a generic GKI module**. It must match the running YAAP
kernel's release, ABI symbol CRCs, configuration, and toolchain. A successful
CI build cannot prove that the resulting `.ko` will load on a device running a
different YAAP commit. Test on a device with recovery access. If loading fails,
disable the module in WebUI or remove its KernelSU module and inspect
`/data/adb/kernelmask/service.log` and `dmesg`.

The config is stored at `/data/adb/kernelmask/config.conf` and is preserved on
uninstall. The WebUI accepts printable ASCII, up to 64 characters per field,
excluding quotes and backslashes. These limits keep `insmod` parameters
unambiguous, including a `version` containing spaces. A WebUI reload unloads
the prior module before loading the new values. It is best to change names on
a test device first: system services may assume a particular kernel release.

## What changes

The init UTS namespace feeds `uname(2)` and related `/proc/sys/kernel/*`
nodes. `/proc/version` also reads the UTS name, release, and version fields,
although it still prints the compile host/compiler baked into the kernel.
Existing UTS namespaces created before KernelMask loads are not modified.
Namespaces cloned while KernelMask is active can inherit the replacement and
may retain it after this module is unloaded.

The external module cannot take YAAP's internal `uts_sem`: that semaphore is
not exported to out-of-tree modules. Updates therefore use `stop_machine` as a
best-effort consistency boundary. A concurrent `uname(2)` or hostname writer
can still observe a transition; making this fully lock-consistent requires a
small in-tree kernel change to export/use the appropriate UTS lock.
Unloading the module restores the original values if no other writer changed
them in the meantime. The underlying kernel image, `Module.symvers`, and boot
partitions are never modified by the module.

## Local build

Use the workflow as the reference for the YAAP source and config assembly.
After building the matching kernel and producing `Module.symvers`:

```sh
make -C "$KERNEL_DIR" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  M="$PWD/kernel" src="$PWD/kernel" modules
./tools/validate.sh kernel/kernelmask.ko "$(cat "$KERNEL_OUT/include/config/kernel.release")"
./tools/package_ksu.sh kernel/kernelmask.ko out/yaap-kernelmask-ksu.zip
```

Do not apply LKM4YAAP's KernelSU-specific empty-`__versions` `modpost` patch.
KernelMask uses standard `insmod`, so it needs YAAP's normal non-empty symbol
CRC section.
