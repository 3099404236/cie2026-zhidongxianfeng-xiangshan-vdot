# 实测日志索引

本目录中的 `*.log` 全部由脚本直接捕获工具输出（仅去除了终端颜色控制符），可用
`vdot-contest/run_all_checks.sh <step>` 在同一台机器上重新生成。

| 文件 | 生成方式 | 内容 |
| :--- | :--- | :--- |
| `hello_xiangshan.log` | `emu -i hello_xiangshan.bin --diff …`、`nemu -b hello_xiangshan.bin` | 阶段一 1.1：`hello xiangshan, I am 曾俊翔, from 电子科技大学, in 192.168.31.250`（香山 RTL + DiffTest 与 NEMU 各运行一次，含执行命令） |
| `env.log` | `run_all_checks.sh env` | 操作系统、工具链版本、XiangShan / NEMU 基线 commit |
| `patch.log` | `run_all_checks.sh patch` | 两个补丁在干净上游 worktree 上 `git apply --check -v` |
| `python.log` | `run_all_checks.sh python` | 黄金模型 15 个 unittest（vdot 10 个、vdota 5 个） |
| `nemu.log` | `run_all_checks.sh nemu` | 8 个裸机程序在 vdot 版 NEMU 解释器上的完整输出 |
| `explore.log` | `rtl-explore/run_explore.py` | 9 个数据通路变体的 Verilator 等价性仿真与 Yosys 综合 |
| `pdk.log` | `rtl-explore/pdk_ppa.py` | 单元库来源（OpenROAD-flow-scripts commit、文件大小与 sha256）、各网表的流水级划分、NanGate45 / ASAP7 下每级延迟与面积（两种 ABC 脚本）、`VIMac64b` 第二级关键路径摘录 |
| `chisel.log` | `mill -i xiangshan.test.testOnly xiangshan.backend.fu.vector.VDotSpec` | ChiselTest 11 组用例（其中 3 组针对累加树） |
| `emu_build.log` | `vdot-build/build_emu.sh`、`build_emu_v3.sh`、`build_emu_v4.sh`、`build_emu_default.sh` | 香山 emu（MinimalConfig 三次、DefaultConfig 一次，均带 DiffTest）构建的过程摘录、耗时与峰值内存 |
| `emu.log` | `tools/run_emu_suite.sh` + `tools/collect_emu_log.sh` | 8 个程序在最终 RTL（vdot + vdota）的香山 emu（MinimalConfig）+ DiffTest（NEMU REF）上的完整输出、两个反例实验、vdot 在 `VIMacU` 中的波形时序，以及前两版 emu 的逐程序对照 |
| `emu_default.log` | 同上，emu 按 `CONFIG=DefaultConfig` 构建 | 同一组程序、反例与波形时序在香山默认配置上的完整输出 |

