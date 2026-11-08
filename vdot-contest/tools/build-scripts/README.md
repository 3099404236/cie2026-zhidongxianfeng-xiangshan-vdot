# 构建脚本（WSL2 Ubuntu 24.04 上实际使用的版本）

这些脚本原样复制自 `/root/codex-work/vdot-build/`，路径按该机器写死：XiangShan 在 `/root/codex-work/xiangshan-vdot-2026/XiangShan`（已打 `xs-vdot-rtl.patch` 并放入新文件），NEMU 在 `/root/codex-work/vdot-build/NEMU`（已打 `nemu-vdot.patch`）。换机器时改脚本开头的路径即可。

| 脚本 | 作用 | 本机耗时 / 峰值内存 |
| :--- | :--- | :--- |
| `build_nemu.sh` | 构建 vdot 版 NEMU：DiffTest REF 动态库（`riscv64-xs-ref_defconfig`）与独立解释器（`riscv64-xs_defconfig`） | 几分钟 |
| `build_negctl_refs.sh` | 构建反例用的两个错误 REF：不含 vdot 的上游 NEMU、把 vs1 字节当无符号数的 vdot | 几分钟 |
| `build_emu_v4.sh` | MinimalConfig 全芯片 emu（最终 RTL）：`sim-verilog` → Verilator → C++ 编译 | 14.5 min / 6.6 GB；1 h 04 min / 7.8 GB；29 min |
| `build_emu_default.sh` | DefaultConfig（香山 Makefile 的默认配置）全芯片 emu，步骤同上 | 24 min / 9.8 GB；4 h 38 min / 11.0 GB；编译见 `logs/emu_build.log` |
| `compile_emu_default.sh` | 从 C++ 编译这一步续跑 DefaultConfig 构建（补上 PCH 回退头文件后） | — |
| `ppa_acc.sh` | 用 `VDotVerilog` 导出带累加 / 不带累加、不同切分点的 `VDot128.sv`，并做 Yosys 通用门 PPA | 几分钟 |
| `run_capped.sh` | 把命令放进有内存上限的 cgroup 运行 | — |

两个本机特有的处理：

1. **内存上限**：宿主机 15.7 GB，WSL2 分到 12 GB。构建脚本把自己放进 cgroup v1（`/sys/fs/cgroup/memory/xsbuild`）并挂上 16 GB swap，否则 JVM 或 Verilator 吃满内存时 WSL2 虚拟机会被整体重启。
2. **超大生成文件**：Verilator 生成的部分 `.cpp` 超过 5 MB，以 `-O3` 编译单个文件就要约 17 GB 内存，脚本把这些文件改为 `-O1`（在 `VSimTop.mk` 末尾追加 `override OPT_FAST := -O1`）。这些文件用不了以 `-O3` 生成的预编译头 `VSimTop__pch.h.fast.gch`，GCC 会转而寻找名为 `VSimTop__pch.h.fast` 的普通头文件，而 Verilator 不生成它；脚本复制 `VSimTop__pch.h` 作为这个文件，并把时间戳设为 2000 年，避免 make 因它而重编其他目标。
