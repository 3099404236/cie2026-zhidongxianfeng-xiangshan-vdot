# 面向边缘 AI 大语言模型推理的 RISC-V 自定义 `vdot` 指令设计——基于“香山”昆明湖 V2 处理器架构

> 2026 CIE 全国 RISC-V 高水平创新及应用大赛（CIE-香山社区·RISC-V 应用创新赛道）提交目录

## 1. 项目简介

在香山昆明湖 V2 的向量整数乘加单元 `VIMacU` 中实现自定义指令 **`vdot.vv`**（8 路有符号 INT8 点积 → `vd[31:0]`，`vd[127:32] = 0`，编码 `funct6 = 001101, vm = 1, OPMVV`，`vdot.vv v10, v8, v9 = 0x36942557`），并在 NEMU 中实现同一语义，用香山全芯片 `emu` + DiffTest 完成 RTL-NEMU 协同仿真。在不改变 `vdot.vv` 任何行为的前提下，另加一条累加形式的扩展指令 **`vdota.vv`**（`vd[31:0] += Σ`，`funct6 = 001110`，`0x3A942557`），与 vdot 共用同一个数据通路。

- **数据通路**：8 路修正 Baugh-Wooley 部分积（512 比特 + 共享常数）合并为一个比特矩阵，单棵 Dadda 树归约，全电路只有一个进位传播加法器。相对上一版（8 个乘法器 + 字级 CSA），Chisel 实际生成的 RTL 在 Yosys/ABC 通用门下**晶体管 -46%、关键流水级逻辑深度 -47%**（仅 vdot 的 19 位树，阶段二文档 4.2 节）；在 NanGate 45 nm / ASAP7 7 nm 真实单元库下，**最长一级延迟 -35% / -44%、面积 -38% / -40%**（阶段二 4.6 节）。`VIMacU` 中实例化的是多一行 32 位累加输入的同一棵树（切分于第 8 级，32 位 CPA），面积只多 4~6%；同一流程下它最长的一级比香山现有乘法器 `VIMac64b` 最短的一级还短 10~20%。
- **集成**：复用 `vimac` 的发射端口、2 拍固定延迟、写回与异常通路；vdot 不读 old vd（vdota 只读 old vd 的低 32 位），都不读 v0；旁路 `Mgu`；执行期间对两个 `VIMac64b` 做操作数隔离。
- **验证**：Python 黄金模型 15 个测试；1 131 108 组向量的数据通路等价性仿真；11 组 ChiselTest；8 个裸机程序在 NEMU 与**香山 emu + DiffTest** 上运行（正数/负数/边界、61 组黄金向量、vdota 的 39 组记录与 64 步累加链、17 种非法配置的精确异常、反例实验）。
- **性能（香山 emu 实测，`mcycle`）**：单次点积依赖链 **6.73 拍**，基线 `vwmul + vwredsum` 为 20.69~28.82 拍（**3.07~4.28×**）；吞吐 1.28 vs 3.19 拍/次（**2.49×**）；INT8 GEMV 比同功能基线快 1.14×，满宽 RVV 写法比 vdot 快 1.46×；改用 `vdota.vv` 后 GEMV **比 vdot 快 1.39×、比同功能基线快 1.59×**，达到满宽 RVV 的 95%（阶段三文档第 4 节）。
- **默认配置复测**：同一份 RTL 按香山 Makefile 默认的 `DefaultConfig`（ROB 160、64 KB L1D、1 MB L2、16 MB L3）重新构建 emu，全部程序与反例结果相同；单条指令的延迟与吞吐不变；GEMV 中 vdota 比 vdot 快 1.34×，并**超过满宽 RVV 写法 1.11×**（阶段三 2.7、4.5 节）。

## 2. 目录

```text
vdot-submission/
├── README.md
├── xs-vdot-rtl.patch          # XiangShan f86f50b 上的改动（5 个文件）
├── xs-vdot-rtl-stat.txt       # 改动统计与基线 commit
├── nemu-vdot.patch            # NEMU a48a11f 上的改动（3 个文件，vdot + vdota）
├── new-files/
│   ├── VDot.scala             # → src/main/scala/xiangshan/backend/fu/vector/
│   ├── VDotSpec.scala         # → src/test/scala/xiangshan/backend/fu/vector/
│   └── VDotVerilog.scala      # → src/test/scala/xiangshan/backend/fu/vector/（导出独立 Verilog）
├── docs/                      # 阶段一 / 二 / 三 技术文档
└── logs/                      # 全部为脚本直接捕获的实测输出（见 logs/README.md）

../vdot-contest/
├── reference/vdot_model.py    # 黄金模型
├── tests/test_vdot_model.py   # 黄金模型单元测试
├── software/                  # 裸机程序：vdot_nemu_test / vdot_full_test / vdota_test / vdot_illegal_test /
│   │                          #   vadd_trace（.S）；bench/hello_xiangshan.c、vdot_demo.c、bench.c + bench_kernels.S
│   ├── gen_vdot_cases.py      # 由黄金模型生成 vdot_full_test 的 61 组向量（gen_vdota_cases.py 生成 vdota 的 39 组）
│   └── Makefile               # make / make run-nemu / make run-emu
├── rtl-explore/               # 数据通路 DSE：生成器、Verilator 等价性测试台、Yosys 脚本、results.md；
│                              #   pdk_ppa.py + results_pdk.md（NanGate45 / ASAP7 真实单元库时序）
├── tools/                     # fstdump（FST 波形提取）、trace_timeline.py、run_emu_suite.sh、collect_emu_log.sh、
│   │                          #   export_patch.sh、make_packages.py
│   └── build-scripts/         # 实际使用的 NEMU / emu（MinimalConfig、DefaultConfig）/ 反例 REF 构建脚本
├── artifacts/waveforms/       # vadd_e8.vcd、vdot128_unit_positive.vcd、全芯片 FST（最终 RTL）
└── run_all_checks.sh          # 重新运行全部检查并把输出写入 vdot-submission/logs/
```

## 3. 复现

```bash
# 1) XiangShan：打补丁并放入新文件
cd XiangShan            # commit f86f50b
git apply /path/to/vdot-submission/xs-vdot-rtl.patch
cp /path/to/vdot-submission/new-files/VDot.scala src/main/scala/xiangshan/backend/fu/vector/
cp /path/to/vdot-submission/new-files/VDotSpec.scala /path/to/vdot-submission/new-files/VDotVerilog.scala \
   src/test/scala/xiangshan/backend/fu/vector/
mill -i xiangshan.test.testOnly xiangshan.backend.fu.vector.VDotSpec

# 2) NEMU：独立解释器 + DiffTest REF
cd NEMU                 # commit a48a11f
git apply /path/to/vdot-submission/nemu-vdot.patch
make riscv64-xs_defconfig && make -j && cp build/riscv64-nemu-interpreter /somewhere/
make clean-all && make riscv64-xs-ref_defconfig && make -j   # build/riscv64-nemu-interpreter-so

# 3) 香山 emu（带 DiffTest 与 FST 波形）
make sim-verilog CONFIG=MinimalConfig NUM_CORES=1 WITH_CHISELDB=0 WITH_CONSTANTIN=0 DISABLE_PERF=1 JVM_XMX=6G
make -C difftest emu NUM_CORES=1 RTL_SUFFIX=sv EMU_THREADS=0 EMU_TRACE=fst -j6
#    默认配置：CONFIG=DefaultConfig JVM_XMX=9G（Verilog 生成约 10 GB、Verilator 约 11 GB 内存）；
#    大于 5 MB 的生成文件改用 -O1 并补 PCH 回退头文件，见 vdot-contest/tools/build-scripts/build_emu_default.sh

# 4) 裸机程序
cd vdot-contest/software && make
make run-nemu NEMU=/path/to/riscv64-nemu-interpreter
make run-emu  EMU=/path/to/XiangShan/build/emu NEMU_SO=/path/to/riscv64-nemu-interpreter-so

# 5) 一键重跑全部检查并刷新 logs/
cd vdot-contest && ./run_all_checks.sh all

# 6) 真实单元库时序（先把 OpenROAD-flow-scripts 中的 NanGate45 与 ASAP7 RVT TT 库文件放到 pdk/ 目录，见 logs/pdk.log）
python3 -I vdot-contest/rtl-explore/pdk_ppa.py --pdk /path/to/pdk
```

内存提示：本机只有 15.7 GB 物理内存（WSL2 分到 12 GB）。`sim-verilog` 与 Verilator 阶段放入有内存上限的 cgroup（MinimalConfig 用 6~7.5 GB），并另加 16 GB swap，才避免了 WSL2 虚拟机因宿主机内存耗尽被重启（阶段一文档 1.3 节）。
