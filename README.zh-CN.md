# YAAP KernelMask

这是面向一加 12 YAAP `seventeen` 内核的实验性外部模块，只修改初始 UTS 命名空间的两个字段：

| 配置项 | 对应命令 | 示例值 |
|---|---|---|
| `release` | `uname -r` | `6.1.174-g638ecc425319` |
| `version` | `uname -v` | `#1 SMP PREEMPT Wed Sep 16 23:10:11 CEST 2026` |

对于 `Linux localhost 6.1.174-g638ecc425319 #1 SMP PREEMPT Wed Sep 16 23:10:11 CEST 2026 aarch64 Android`，模块仅修改从 `6.1.174-g638ecc425319` 到 `2026` 的两个字段。`Linux`、`localhost`、`aarch64` 和 `Android` 不变。开关默认关闭；任一字段留空时保持该字段原值。

## 使用

1. 在 GitHub Actions 手动运行 **Build KernelMask for YAAP**。
2. 下载 `yaap-seventeen_kernelmask-ksu.zip`，通过 KernelSU 管理器安装。
3. 打开模块 WebUI，填写要覆盖的 `release` 和 `version`，开启开关并点击“保存并重载”。
4. 在 WebUI 的状态区检查 `uname -r/-v`、`/proc/version`、`/proc/sys/kernel/osrelease` 和 `/proc/sys/kernel/version`。

必须使用与设备当前 YAAP 内核匹配的提交、配置与工具链。工作流会记录 YAAP 内核和 modules 的实际提交；Actions 构建成功不代表能加载到任意 YAAP 版本。加载失败时可关闭开关或卸载 KernelSU 模块，并查看 `/data/adb/kernelmask/service.log` 和 `dmesg`。

配置位于 `/data/adb/kernelmask/config.conf`，卸载时保留。WebUI 每个字段最多 64 个可打印 ASCII 字符，不接受引号和反斜杠；`release` 不能包含空格，`version` 可以包含空格。重载失败时会恢复旧配置并尝试重新加载旧模块。旧版配置中的 `sysname`、`nodename`、`machine` 和 `domainname` 会被读取但忽略；WebUI 下次保存时会移除它们。

## 检测器对应范围

[Duck Detector Refactoring 的 Kernel Check](https://github.com/eltavine/Duck-Detector-Refactoring/tree/56bd5dc501a27c87a4c00cbf8ad9d5c58352ccfb/feature/kernelcheck) 会对比原始 `uname()` 系统调用、`uname -r`、`/proc/version`、`/proc/sys/kernel/osrelease`、`/proc/sys/kernel/version`，以及 Zygote 启动时缓存的 `System.getProperty("os.version")`。本模块直接修改初始 UTS 命名空间的 `release` 和 `version`，使实时 `uname` 与相应 `/proc` 导出读取同一对值。KernelSU 的 `post-fs-data.sh` 尽早加载模块，通常能让随后启动的 Zygote 缓存新 `release`；若仅在 Zygote 启动后加载或在 WebUI 重载，旧的 JVM 缓存值仍可能与实时结果不同，需重启设备才能更新该缓存。

检测器还会扫描内核身份文本中的自定义内核关键词、非正常主版本号、非拉丁字符和 `@` 等标记。请填写来自真实目标版本的完整、格式合理的值；本模块不会自动推断、净化或生成这些文本，也不改变检测器的其他检查项目。

模块只调整初始 UTS 命名空间。此前创建的其他 UTS 命名空间可能继续显示原值；模块生效期间新创建的命名空间可能在卸载后仍保留修改值。`/proc/version` 中编译主机和编译器部分仍由内核构建决定。模块也不改变真实内核镜像、模块 ABI/vermagic、`/proc/modules`、`/proc/kallsyms`、挂载、SELinux、bootconfig 或已有 `dmesg` 记录。

## 实现说明

模块使用 YAAP 导出的 `init_uts_ns` 和 `stop_machine`，只写入 `release` 与 `version`；卸载时仅恢复仍等于本模块写入值的字段。YAAP 内部的 `uts_sem` 没有导出给外部模块，因此 `stop_machine` 仅提供尽可能一致的更新边界，并发读取时仍可能观察到短暂过渡。完全锁一致的更新需要修改内核树并使用相应 UTS 锁。

这是普通 `insmod` 外部模块，必须保留 YAAP `Module.symvers` 生成的非空 `__versions`。不要套用针对 KernelSU LKM 加载器的空 `__versions`/`modpost` 补丁。
