# 面向边缘 AI 大语言模型推理的 RISC-V 自定义 `vdot` 指令设计——基于“香山”昆明湖 V2

> 2026 CIE 全国 RISC-V 高水平创新及应用大赛 · CIE-香山社区 RISC-V 应用创新赛道
> 参赛者：曾俊翔（电子科技大学）

在香山昆明湖 V2 的向量整数乘加单元 `VIMacU` 中实现赛题规定的 INT8 点积指令 **`vdot.vv`**（`vd[31:0] = Σ₈ sext(vs1)·sext(vs2)`，`vd[127:32] = 0`，编码 `0x36942557`），在 NEMU 中实现同一语义，并在香山全芯片仿真器 `emu` 上用 DiffTest 完成 RTL 与 NEMU 的协同仿真。在不改变 `vdot.vv` 任何行为的前提下，另加一条与它共用同一个数据通路的累加扩展指令 **`vdota.vv`**（`vd[31:0] += Σ`，`0x3A942557`）。

## 主要结果

| 项目 | 结果 | 出处 |
| :--- | :--- | :--- |
| 单次点积延迟（依赖链） | 6.73 周期；RVV 基线 `vwmul + vwredsum` 为 20.69~28.82 周期，**快 3.07~4.28×** | 阶段三 §4.2 |
| 吞吐 | 1.28 周期/条；基线 3.19，**快 2.49×** | 阶段三 §4.2 |
| INT8 GEMV（16 × 256） | vdot 比同功能基线快 1.14×；改用 vdota 后比 vdot 快 1.39×（MinimalConfig），在默认配置中快 1.34× 并**超过满宽 RVV 写法 1.11×** | 阶段三 §4.3、§4.5 |
| 数据通路 | 8 路修正 Baugh-Wooley 部分积融合为一个比特矩阵，单棵 Dadda 树，全电路只有一个进位传播加法器；相对上一版，NanGate 45 nm / ASAP7 7 nm 单元库下最长一级 **-35% / -44%**、面积 **-38% / -40%** | 阶段二 §2.3、§4.6 |
| 时序余量 | 同一综合流程下，`VDot128` 最长的一级比香山现有乘法器 `VIMac64b` 最短的一级还短 10~20% | 阶段二 §4.6 |
| 验证 | 黄金模型 15 项；1 131 108 组向量的数据通路等价性仿真；ChiselTest 11 组；8 个裸机程序与 2 个反例实验在 **MinimalConfig 与默认配置 DefaultConfig** 两种全芯片 emu + DiffTest 上全部符合预期 | 阶段二 §3、阶段三 §2 |

## 赛题交付物对照

| 交付物 | 位置 |
| :--- | :--- |
| 1.1 环境部署验证（hello xiangshan） | `vdot-submission/logs/hello_xiangshan.log`，阶段一文档 §1.2 |
| 1.2 操作日志 | 阶段一文档 §1.3；`vdot-submission/logs/emu_build.log`、`env.log` |
| 1.3 向量加法指令执行过程 | 阶段一文档 §2（全芯片波形 `vdot-contest/artifacts/waveforms/vadd_trace.fst`） |
| 2.1 vdot.vv 设计文档 | 阶段二文档 §1、§2、§4 |
| 2.2 RTL 实现 | `vdot-submission/xs-vdot-rtl.patch` + `vdot-submission/new-files/` |
| 2.3 正数 / 负数 / 边界测试 | 阶段二文档 §3；`vdot-submission/logs/chisel.log`、`emu.log` |
| 3.1.1 NEMU 指令扩展 | `vdot-submission/nemu-vdot.patch`，阶段三文档 §1 |
| 3.1.2 协同仿真 | 阶段三文档 §2；`vdot-submission/logs/emu.log`、`emu_default.log` |
| 3.2 基线实现 | `vdot-contest/software/bench/bench_kernels.S`，阶段三文档 §3 |
| 3.3 延迟加速比分析 | 阶段三文档 §4 |

文档在 `vdot-submission/docs/`：

- [阶段一：环境部署与向量加法指令执行过程分析](vdot-submission/docs/阶段一_环境部署与向量加法指令执行过程分析文档.md)
- [阶段二：vdot 自定义指令设计文档与基础功能测试报告](vdot-submission/docs/阶段二_vdot自定义指令设计文档与基础功能测试报告.md)
- [阶段三：NEMU 指令扩展、协同仿真与延迟加速比分析报告](vdot-submission/docs/阶段三_NEMU指令扩展与协同仿真及延迟加速比分析报告.md)

## 仓库结构

```text
vdot-submission/
├── docs/                 三个阶段的技术文档与插图
├── xs-vdot-rtl.patch     XiangShan f86f50b 上的 RTL 改动（5 个文件）
├── nemu-vdot.patch       NEMU a48a11f 上的改动（vdot + vdota）
├── new-files/            VDot.scala（数据通路生成器）、VDotSpec.scala（ChiselTest）、VDotVerilog.scala
├── logs/                 全部实测输出（由脚本直接捕获，见 logs/README.md）
└── README.md             改动说明与复现步骤
vdot-contest/
├── reference/ tests/     Python 黄金模型与单元测试
├── software/             裸机测试程序与性能内核（make 生成 .bin）
├── rtl-explore/          数据通路设计空间探索、Verilator 等价性测试台、真实单元库时序分析
├── tools/                波形分析、测试套件、构建脚本（tools/build-scripts/）
├── artifacts/waveforms/  vadd / vdot 的单元级 VCD 与全芯片 FST 波形
└── run_all_checks.sh     重新运行全部检查并刷新 logs/
```

## 复现

基线：XiangShan `f86f50b834c26597426b5ede7c25afaff84d11ce`、NEMU `a48a11f208ff81ad765591d83271d1b339fb3861`；环境：WSL2 Ubuntu 24.04、Verilator 5.020、Yosys 0.33、mill。打补丁、构建 NEMU 与香山 emu、运行全部测试的命令见 [vdot-submission/README.md](vdot-submission/README.md) 第 3 节，实际使用的构建脚本在 `vdot-contest/tools/build-scripts/`。

## 版权

比赛期间，本仓库的原创内容保留所有权利（All rights reserved），未经许可请勿复制、修改或再发布。基于香山（XiangShan）与 NEMU 修改的部分遵循其原始许可证木兰宽松许可证第 2 版（Mulan PSL v2）。
