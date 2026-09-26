# YAAP KernelMask

这是面向一加 12 YAAP `seventeen` 内核的实验性外部模块，用于修改**初始 UTS 命名空间**对外显示的内核名称、发布版本、构建版本字符串和构建时间等字段。默认关闭，所有字段留空时保持原值。

它不是完整的 SUSFS 替代品：不会隐藏 `/proc/modules`、`/proc/kallsyms`、挂载信息、SELinux 状态、bootconfig 或既有 `dmesg` 记录；也不会修改真实内核镜像和模块 ABI。加载前已创建的其他 UTS 命名空间可能继续显示原值；模块生效期间新创建的命名空间可能在卸载后仍保留伪装值。

## 使用

1. 在 GitHub Actions 手动运行 **Build KernelMask for YAAP**。
2. 下载产物中的 `yaap-seventeen_kernelmask-ksu.zip`，通过 KernelSU 管理器安装。
3. 打开模块 WebUI，填写需要覆盖的字段，开启开关并点击“保存并重载”。
4. 用 WebUI 中的 `uname -a`、`/proc/version` 和模块状态检查结果。

必须使用与设备当前 YAAP 内核匹配的提交、配置与工具链。工作流会记录 YAAP 内核和 modules 的实际提交；“Actions 构建成功”不等于“任意 YAAP 版本均可加载”。建议在有恢复手段的设备上测试。加载失败可关闭开关或卸载 KernelSU 模块，并查看 `/data/adb/kernelmask/service.log`、`dmesg`。

配置位于 `/data/adb/kernelmask/config.conf`，卸载时保留。WebUI 每个字段最多 64 个可打印 ASCII 字符，不接受引号和反斜杠；版本字符串可以包含空格。重载失败时 WebUI 会恢复旧配置并尝试重新加载旧模块。

## 实现边界

模块使用 YAAP 导出的 `init_uts_ns` 和 `stop_machine`，修改初始 UTS 命名空间中的 `sysname`、`nodename`、`release`、`version`、`machine`、`domainname`。`uname(2)`、部分 `/proc/sys/kernel/*` 节点及 `/proc/version` 会读取这些字段，但 `/proc/version` 中编译主机/编译器部分不会因此改变。卸载时仅恢复仍等于本模块写入值的字段。

YAAP 内部的 `uts_sem` 没有导出给外部模块，因此模块不能在不改内核的前提下安全地直接持有该锁；当前使用 `stop_machine` 提供尽可能一致的更新边界。若更新同时发生 `uname(2)` 或主机名写入，仍可能观察到过渡状态；要完全解决需要在内核树内配合导出并使用相应 UTS 锁。

这是普通 `insmod` 外部模块，必须保留 YAAP `Module.symvers` 生成的非空 `__versions`。不要套用针对 KernelSU LKM 加载器的空 `__versions`/`modpost` 补丁。
