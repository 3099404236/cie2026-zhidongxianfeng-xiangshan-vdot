# 阶段三：NEMU 指令扩展、RTL-NEMU 协同仿真与延迟加速比分析报告

> **赛题名称**：面向边缘 AI 大语言模型推理的 RISC-V 自定义 `vdot` 指令设计——基于“香山”昆明湖 V2 处理器架构
> **赛事赛道**：2026 CIE 全国 RISC-V 高水平创新及应用大赛（CIE-香山社区·RISC-V 应用创新赛道）
> **覆盖评分项**：阶段三（25%）：`3.1.1` NEMU 指令扩展、`3.1.2` RTL 与 NEMU 协同仿真、`3.2` 基线实现、`3.3` 延迟加速比分析
> **文档版本**：v4（2026-11-05）。v3 起协同仿真在香山全芯片 `emu` 上以 DiffTest（NEMU 作为 REF）真实运行，延迟与加速比全部为 `mcycle` 实测值，并有更强的 RVV 基线与 GEMV 应用级对比。v4 的全部结果改为在最终 RTL（带累加行的融合 Dadda 树，同时实现 `vdot.vv` 与扩展指令 `vdota.vv`）的 emu 上重新测得，新增 `vdota.vv` 的协同仿真与 GEMV 实测（4.3、4.4 节），并在香山默认配置（`DefaultConfig`）上复测了全部程序与性能内核（2.7、4.5 节）。

---

## 1. NEMU 指令扩展（对应评分项 3.1.1）

### 1.1 修改文件（`nemu-vdot.patch`，基于 NEMU `a48a11f`）

| 文件 | 修改 |
| :--- | :--- |
| `src/isa/riscv64/include/isa-all-instr.h` | 在指令表宏中注册 `f(vdot) f(vdota)`，生成执行入口 `exec_vdot` / `exec_vdota` |
| `src/isa/riscv64/instr/rvv/decode.h` | `vopmvv` 译码表新增 `def_INSTR_TAB("001101 1 ????? ????? ??? ????? ????? ??", vdot)` 与扩展指令 `def_INSTR_TAB("001110 1 …", vdota)`（`vm` 位固定为 1，`vm = 0` 不匹配 → 非法指令） |
| `src/isa/riscv64/instr/rvv/vcompute.h` | 新增 `def_EHelper(vdot)` 与 `def_EHelper(vdota)` |

补丁对干净的上游树执行 `git apply --check` 通过（`logs/patch.log`）。同一份源码分别以 `riscv64-xs_defconfig`（独立解释器）和 `riscv64-xs-ref_defconfig`（DiffTest REF 动态库 `riscv64-nemu-interpreter-so`）构建；两者都包含 `exec_vdot` 与 `exec_vdota` 符号。

### 1.2 执行语义

```c
def_EHelper(vdot) {
  require_vector(true);                       // mstatus.VS == Off / vill → 非法指令
  if (vtype->vsew != 0 || vtype->vlmul != 0 || s->vm != 1 || vstart->val != 0) {
    longjmp_exception(EX_II);                 // 与 RTL VecExceptionGen 的判定一致
  }
  int32_t sum = 0;
  for (int i = 0; i < 8; i++)
    sum += (int32_t)(int8_t)vreg_b(id_src->reg, i) * (int32_t)(int8_t)vreg_b(id_src2->reg, i);
  vreg_l(id_dest->reg, 0) = (uint32_t)sum;    // vd[63:0]  = zext(sum[31:0])
  vreg_l(id_dest->reg, 1) = 0;                // vd[127:64] = 0
  vstart->val = 0;
  vp_set_dirty();
}
```

扩展指令 `vdota.vv`（阶段二 2.4 节）的合法性检查与 vdot 完全相同，只是先读 old `vd[31:0]` 作为累加初值，用无符号加法实现 int32 回绕：

```c
uint32_t acc = (uint32_t)vreg_l(id_dest->reg, 0);     // 只读 old vd[31:0]
for (int i = 0; i < 8; i++)
  acc += (uint32_t)((int32_t)(int8_t)vreg_b(id_src->reg, i) * (int32_t)(int8_t)vreg_b(id_src2->reg, i));
vreg_l(id_dest->reg, 0) = acc;                         // vd[63:0]  = zext(acc)
vreg_l(id_dest->reg, 1) = 0;                           // vd[127:64] = 0
```

---

## 2. RTL 与 NEMU 协同仿真（对应评分项 3.1.2）

### 2.1 DiffTest 机制

香山 `emu` 中，DUT（Verilator 编译的香山 RTL）每提交一条指令，`difftest` 模块就通过 DPI-C 把提交信息（PC、指令、写回寄存器、异常/中断、访存等）交给 C++ 框架；框架让 REF（以动态库形式加载的 NEMU）执行同一条指令，然后逐项比较两边的**全部架构状态**：通用/浮点寄存器、**32 个向量寄存器**、CSR（含 `vtype/vl/vstart/vxsat`）、PC。任何一位不一致都会立即报错并停止仿真。不可预测的状态（MMIO 读、`mcycle/minstret` 等计数器）由 DUT 同步给 REF。

因此本节中“HIT GOOD TRAP”同时意味着两件事：程序自身的检查全部通过，**而且**每一条 `vdot.vv` / `vdota.vv`（以及其他指令）提交时，香山 RTL 写入 `vd` 的 128 位与 NEMU 计算的结果逐位一致；在 17 种非法配置（vdot 13 种、vdota 4 种）下，两边在同一条指令上产生相同的 `mcause = 2` 异常。

### 2.2 构建

| 组件 | 构建方式 |
| :--- | :--- |
| 香山 `emu` | XiangShan `f86f50b` + `xs-vdot-rtl.patch` + `VDot.scala`（最终 RTL：vdot + vdota，带累加行的 32 位融合 Dadda 树）；`CONFIG=MinimalConfig`、`--enable-difftest`、`EMU_TRACE=fst`（`vdot-build/build_emu_v4.sh`） |
| REF | 打上 `nemu-vdot.patch` 的 NEMU，`riscv64-xs-ref_defconfig` → `riscv64-nemu-interpreter-so` |

### 2.3 测试程序与结果

| 程序 | 内容 |
| :--- | :--- |
| `hello_xiangshan` | 阶段一 1.1 的环境验证输出（同一个 emu + DiffTest） |
| `vdot_nemu_test.S` | 正数 120、负数 -204、最大值 131072 |
| `vdot_full_test.S` | 61 组黄金模型向量（`vd` 预置 `0xff`、源高 64 位含噪声）、`vl = 1/8/0`、背靠背依赖链、寄存器重叠（含 `vd = v0`）、被其他功能单元消费、`vxsat` 不变 |
| `vdota_test.S` | `vdota.vv`：39 组黄金记录（含 int32 回绕）、64 步累加链、`vd == vs1 / vs2 / v0` 重叠、与 vdot 交替执行 |
| `vdot_illegal_test.S` | 17 种非法配置（vdot 13 种 + vdota 4 种）的精确异常，`vd` 保持不变 |
| `vdot_demo` | 打印正数 / 负数 / 边界用例的完整 128 位 `vd` |
| `vdot_bench` | 第 4 节的全部性能内核（结果同时与 C 参考比对） |

实测结果（`logs/emu.log`；每个程序的命令均为 `emu -i <程序>.bin --diff riscv64-nemu-interpreter-vdot-so`，由 `tools/run_emu_suite.sh` 运行）：

| 程序 | 结果 | 提交指令数 | 周期数 | 与 NEMU 独立运行的指令数 |
| :--- | :--- | ---: | ---: | :--- |
| `hello_xiangshan` | HIT GOOD TRAP | 332 | 4 843 | 一致（332） |
| `vdot_nemu_test` | HIT GOOD TRAP | 60 | 1 550 | 一致（60） |
| `vdot_full_test` | HIT GOOD TRAP | 1 891 | 6 501 | 一致（1 891） |
| `vdota_test` | HIT GOOD TRAP | 1 644 | 5 792 | 一致（1 644） |
| `vdot_illegal_test` | HIT GOOD TRAP | 497 | 4 158 | 一致（497） |
| `vadd_trace` | HIT GOOD TRAP | 28 | 1 510 | 一致（28） |
| `vdot_demo` | HIT GOOD TRAP，7 个用例全部 PASS | 14 852 | 71 532 | — |
| `vdot_bench` | HIT GOOD TRAP，全部内核结果与 C 参考一致 | 163 043 | 200 562 | — |

值得注意的三点：

- `vdot_full_test` 中 `vl = 0` 的用例也通过了 DiffTest：RTL 与 NEMU 都按“结果与 `vl` 无关”的语义写回了 `vd`，两边定义一致。
- `vdot_illegal_test` 的 17 种非法配置在 RTL 与 NEMU 中都在同一条指令上产生 `mcause = 2`（DiffTest 同时比对 `mcause/mepc/mtval`），并且 `vd` 未被修改。
- `vdota_test` 的 64 步累加链中每一步都读上一步写回的 `vd`：RTL 一侧这依赖于译码把 vdota 标记为 `isDependOldVd`（阶段二 2.1 节），否则 `vta = 1` 时发射队列的 `ignoreOldVd` 优化会去掉对 old vd 的等待。DiffTest 逐条比对通过，说明这条依赖在真实流水线中成立。

### 2.4 反例：DiffTest 确实在检查 vdot

为证明上面的“通过”不是因为比较被绕过，专门构建了两个“错误”的 REF（`vdot-build/build_negctl_refs.sh`），对同一个 `vdot_nemu_test` 运行：

**反例 1：REF 为不含 vdot 补丁的上游 NEMU。** REF 遇到 `0x36942557` 时按非法指令陷入，而 RTL 正常执行了 vdot。DiffTest 在第一条 `vdot.vv`（`pc = 0x80000082`）处立即终止（DiffTest 输出中 `right` 为 REF 的值，`wrong` 为 DUT 的值）：

```text
commit group [15]: pc 0080000082 cmtcnt 2 <--
[19] commit pc 0000000080000082 inst 36942557 wen 1 dst 10 ...
  mepc different at pc = 0x0080000036, right = 0x0000000080000082, wrong = 0x0000000000000000
 mcause different at pc = 0x0080000036, right = 0x0000000000000002, wrong = 0x0000000000000000
v10_low different at pc = 0x0080000036, right = 0xee9af3359585989c, wrong = 0x0000000000000078
Core 0: ABORT at pc = 0x80000036
```

（REF 一侧 `v10` 的值是它跳进异常处理后寄存器里的残留数据，每次构建不同；DUT 一侧 `0x78` 即正确结果 120。）

**反例 2：REF 的 vdot 故意写错（把 `vs1` 的字节当作无符号数）。** 正数用例两边结果相同，DiffTest 放行；到负数用例时 REF 算出 9012（`0x2334`），RTL 算出正确的 -204（`0xffffff34`），DiffTest 在该条 vdot 处终止：

```text
commit group [15]: pc 0080000082 cmtcnt 2 <--
v10_low different at pc = 0x0080000050, right = 0x0000000000002334, wrong = 0x00000000ffffff34
Core 0: ABORT at pc = 0x80000050
```

反例 2 说明 DiffTest 比较的是向量寄存器的**数值**，而不只是控制流或异常。另外，用仓库中 9 月构建的旧 REF 动态库运行同一程序会 HIT GOOD TRAP——经检查该库本身就包含 `exec_vdot`（上一轮已按 vdot 补丁构建），与结论一致。

### 2.5 vdot 在 `VIMacU` 中的波形

`emu … --dump-wave --wave-path vdot_nemu_test.fst`（`artifacts/waveforms/vdot_nemu_test.fst`，10 MB），用 `tools/trace_timeline.py --instr 0x36942557 --fu Vimac` 提取第一条 `vdot.vv`（正数用例）：

| 阶段 | 周期 | 信号（前缀 `TOP.SimTop.cpu.l_soc.core_with_l2.core.backend.`） |
| :--- | ---: | :--- |
| 译码输出 | 1460 | `inner_ctrlBlock.decode.io_out_0_valid = 1`，`bits_instr = 0x36942557` |
| 重命名输出 | 1461 | `inner_ctrlBlock.rename.io_out_0_valid = 1` |
| 进入 `VIMacU` | 1497 | `inner_vfExuBlock.exus.Vimac.io_in_valid = 1`（等待 `vle8.v` 的数据约 36 拍） |
| `VIMacU` 输出 | 1499 | `Vimac.io_out_valid = 1`，`io_out_bits_res_data = 0x78`（120） |
| 提交 | 1505 | `TOP.SimTop.endpoint.commit.io_bits_valid = 1`，`io_bits_instr = 0x36942557` |

| 信号（`…exus.Vimac.`） | 1496 | 1497 | 1498 | 1499 | 1500 |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `io_in_valid` | 0 | **1** | 0 | 0 | 0 |
| `io_in_bits_ctrl_fuOpType` | `0x1c1` | **`0x100`**（vdot） | `0x100` | `0x100` | `0x100` |
| `io_in_bits_data_src_0`（vs1） | — | `0xffffffffffffffff_0807060504030201` | 同左 | 同左 | 同左 |
| `io_in_bits_data_src_1`（vs2） | — | `0xffffffffffffffff_0102030405060708` | 同左 | 同左 | 同左 |
| `inIsVDot` | 0 | 1 | 1 | 1 | 1 |
| `vdot.io_en` | 0 | **1** | 0 | 0 | 0 |
| `vdot.stage1Valid` | 0 | 0 | **1** | 0 | 0 |
| `vdot.stage2` | `0xa56cb3d1` | `0xa56cb3d1` | `0xa56cb3d1` | **`0x78`** | `0x78` |
| `io_out_valid` | 0 | 0 | 0 | **1** | 0 |
| `io_out_bits_res_data` | 0 | 0 | 0 | **`0x78`** | `0x78` |

几点观察：

1. 进入 `VIMacU` 后正好 2 拍输出结果，与 `VimacCfg` 的固定延迟一致；
2. `vs1/vs2` 的高 64 位是 `vle8.v`（`vl = 8`、`ta`）留下的尾部全 1，结果不受影响，`vd[127:32]` 为 0；
3. 整个程序中 `Vimac.vimacs_0.io_fire` 始终为 0（`io_in_valid` 在 1497、1516、1525 三次脉冲都是 vdot），即操作数隔离生效，两个 `VIMac64b` 在 vdot 期间没有任何寄存器更新；
4. `vdot.stage2` 在 1497 之前的 `0xa56cb3d1` 是寄存器的随机初值（`RANDOMIZE_REG_INIT`），只有 `stage1Valid` 拉高后才被更新，输出由 `io_out_valid` 限定，不会被误用。

> 说明：上面的波形与本节全部结果来自最终提交的 RTL：`Vimac.vdot` 是带累加行的 32 位融合 Dadda 树（切分于第 8 级），有 84 个第一级寄存器比特和 32 位的 `stage2`；vdot 时累加输入为 0。前两版 emu（字级 CSA、无累加行的融合 Dadda）上同一组测试的结果完全相同，见 2.6 节。

### 2.6 三版数据通路的全芯片验证

`VDot128` 先后在全芯片上构建过三版：v2（4 棵字级 CSA 树 + 4 个 CPA）、v3（融合 Baugh-Wooley 部分积 + 单棵 Dadda 树，只有 vdot）和最终的 v4（v3 的树多一行 32 位累加输入，同时实现 vdot 与 vdota）。每一版的端口时序结构都相同：异步复位、`RegEnable(…, io.en)` / `RegNext(io.en)` / `RegEnable(…, stage1Valid)` 两级流水（Chisel 源码与生成的 `VDot128.sv` 端口逐一核对）；v4 只多一个 32 位累加输入端口，由 `VIMacU` 接到 old vd 的低 32 位。验证分三层：

1. **数据通路等价性仿真**：v1/v2/v3 共 9 个变体在同一测试台中逐拍流水输入 1 131 108 组向量，0 失配（阶段二 §4.2）；
2. **ChiselTest**：全部 11 组 `VDotSpec` 通过，其中 3 组专门测累加树（累加值为 0 时与 vdot 逐位相同、1 000 组随机累加初值含回绕、32 位树的全部 11 个切分点，阶段二 §3.2）；
3. **全芯片**：三版 emu 运行 2.3 节的全部程序与两个反例（v2、v3 时还没有 vdota，非法配置为 13 种）：

| 程序（提交指令数 / 周期数） | v2 emu（字级 CSA） | v3 emu（融合 Dadda） | **v4 emu（最终：累加行 + vdota）** |
| :--- | :--- | :--- | :--- |
| `vdot_nemu_test` | GOOD TRAP，60 / 1 550 | GOOD TRAP，60 / 1 550 | **GOOD TRAP，60 / 1 550** |
| `vdot_full_test` | GOOD TRAP，1 891 / 6 501 | GOOD TRAP，1 891 / 6 501 | **GOOD TRAP，1 891 / 6 501** |
| `vadd_trace` | GOOD TRAP，28 / 1 510 | GOOD TRAP，28 / 1 510 | **GOOD TRAP，28 / 1 510** |
| `vdot_demo` | GOOD TRAP，7 个用例 PASS | 同左，输出逐字节相同 | **同左，输出逐字节相同** |
| `vdot_illegal_test` | 13 种，394 / 3 555 | 13 种，394 / 3 555 | **17 种，497 / 4 158** |
| `vdota_test` | — | — | **GOOD TRAP，1 644 / 5 792** |
| `vdot_bench` | 148 142 / 172 289 | 148 142 / 172 289 | **163 043 / 200 562（新增 vdota 内核）** |
| 反例 1 / 反例 2 | 均在 vdot 处 ABORT | 同一条 vdot 处 ABORT | **同一条 vdot 处 ABORT，差异项相同** |

对 vdot 本身，三版的指令数与周期数逐拍一致，`vdot_bench` 中三个 vdot 内核的周期数（1 725 / 328 / 3 508）在 v4 上也完全相同，说明数据通路替换和增加累加行都没有改变任何时序行为（两拍固定延迟、写回与唤醒均不变）。v4 的 bench 程序因为新增 vdota 内核而重新编译，内核在内存中的位置和 C 部分的代码都有变化，几个基线内核的周期数随之小幅变化（例如满宽 RVV 的 GEMV 由 2 492 拍变为 2 400 拍）；第 4 节全部采用 v4 同一次运行的数据。

构建记录（`logs/emu_build.log`）：v3 只替换了生成的 `VDot128.sv`，Verilator 1 h 25 min（峰值 7.8 GB）、C++ 编译 31 min（第 5 节）；v4 改了译码表，需要从 Chisel 重新生成：`sim-verilog` 14.5 min（6.6 GB）、Verilator 1 h 04 min（7.8 GB）、C++ 编译 29 min（第 6 节）。本节结果见 `logs/emu.log`，波形文件 `artifacts/waveforms/*.fst` 来自 v4 emu。

另外尝试了用 Yosys `sat -tempinduct` 对 v2 与 v3 做形式化时序等价证明：从全零初态出发的前 2 步被证明一致（此时两级流水线尚未输出任何算术结果），但涉及“任意 128 位输入下两种乘加树结构结果相同”的第 3 步及归纳步未收敛：复位固定为 0 的版本在 1.5 小时时限、复位不受约束的版本在 2 小时时限内均以 `timeout`（退出码 124）结束。这是 SAT 求解器处理乘法器等价的已知难点：两种结构之间没有共同的中间信号，通常需要代数方法。因此本项目对 v3/v4 的正确性依据是上面三层仿真验证，不声称形式化证明。

### 2.7 在默认配置（DefaultConfig）上复测

以上结果都来自 `MinimalConfig`（香山 README 中编译 emu 的示例配置，队列与缓存缩小、执行单元不变）。为确认结论不依赖这个缩小配置，用同一份最终 RTL 按香山 Makefile 的默认配置 `CONFIG=DefaultConfig` 重新构建 emu（`tools/build-scripts/build_emu_default.sh`），运行同一组程序与反例（`logs/emu_default.log`）。两种配置的主要差别：

| 参数 | MinimalConfig | DefaultConfig |
| :--- | ---: | ---: |
| ROB / 每个发射队列 | 48 / 10 | 160 / 24 |
| 读队列 / 写队列 | 24 / 20 | 72 / 56 |
| 整数 / 向量物理寄存器 | 64 / 160 | 224 / 128 |
| L1 数据缓存 / L2 / L3 | 32 KB / 128 KB / 小 | 64 KB / 1 MB / 16 MB |
| 预取器 | 关闭 | 开启 |
| 译码、重命名宽度，向量执行单元（含 `VIMacU`） | 相同 | 相同 |

| 程序（提交指令数 / 周期数） | MinimalConfig | **DefaultConfig** |
| :--- | :--- | :--- |
| `hello_xiangshan` | GOOD TRAP，332 / 4 843 | **GOOD TRAP，332 / 11 710** |
| `vdot_nemu_test` | GOOD TRAP，60 / 1 550 | **GOOD TRAP，60 / 8 408** |
| `vdot_full_test` | GOOD TRAP，1 891 / 6 501 | **GOOD TRAP，1 891 / 12 843** |
| `vdota_test` | GOOD TRAP，1 644 / 5 792 | **GOOD TRAP，1 644 / 11 775** |
| `vdot_illegal_test` | GOOD TRAP，497 / 4 158 | **GOOD TRAP，497 / 10 993** |
| `vadd_trace` | GOOD TRAP，28 / 1 510 | **GOOD TRAP，28 / 8 377** |
| `vdot_demo` | GOOD TRAP，7 个用例 PASS，14 852 / 71 532 | **GOOD TRAP，7 个用例 PASS，14 852 / 77 491** |
| `vdot_bench` | GOOD TRAP，163 043 / 200 562 | **GOOD TRAP，163 031 / 173 366** |
| 反例 1 / 反例 2 | 在同一条 vdot 处 ABORT | **在同一条 vdot 处 ABORT，差异项相同** |

- 全部程序在默认配置上通过 DiffTest，提交指令数与 MinimalConfig、与 NEMU 独立运行一致。`vdot_bench` 差 12 条是因为它打印的周期数不同，`printf` 的执行路径随之不同（DiffTest 把 `mcycle` 读数同步给 NEMU，两边仍逐条一致）。
- 默认配置从复位到程序开始执行多出约 6 860 拍（各程序的增量基本相同），所以短程序的周期数显著变大。
- 波形中第一条 `vdot.vv` 的时序与 MinimalConfig 完全相同，只是整体后移：译码 8318 → 重命名 8319 → 进入 `VIMacU` 8355 → 输出 8357（`0x78`，2 拍）→ 提交 8363，对应 MinimalConfig 的 1460 / 1461 / 1497 / 1499 / 1505。

构建记录（`logs/emu_build.log` 第 7 节）：`sim-verilog` 24 min（峰值 9.8 GB，生成的 RTL 1.6 GB，MinimalConfig 为 1.0 GB），Verilator 4 h 38 min（11.0 GB），C++ 编译共约 58 min；emu 可执行文件 254 MB。

---

## 3. 标准 RVV 基线实现（对应评分项 3.2）

源码：`vdot-contest/software/bench/bench_kernels.S`（汇编内核）与 `bench.c`（C 参考模型与结果校验）。

### 3.1 单次 8 元素点积：相同功能的三种实现

```asm
# (a) vdot.vv：1 条指令（vtype 已是 e8/m1）
    vdot.vv     v10, v8, v9                 # .word 0x36942557

# (b) 基线 m1：vwmul 产生 EMUL=2 的 16 位乘积，再在 e16/m2 下扩位归约
    vsetivli    zero, 8, e8, m1, ta, ma
    vwmul.vv    v12, v8, v9                 # v12..v13 = 8 × int16
    vsetivli    zero, 8, e16, m2, tu, ma
    vwredsum.vs v10, v12, v14               # v10[31:0] = v14[0] + Σ v12[i]（v14 = 0 已在循环外清零）

# (c) 基线 mf2（调优版）：e8/mf2 使 vwmul 的结果只占 1 个寄存器
    vsetivli    zero, 8, e8, mf2, ta, ma
    vwmul.vv    v12, v8, v9
    vsetivli    zero, 8, e16, m1, tu, ma
    vwredsum.vs v10, v12, v14
```

按 `UopInfoGen` 的拆分规则（`VSET` 2 uop；`VEC_VVW` 在 m1 时 2 uop、分数 LMUL 时 1 uop；`VEC_VWW` 为 2×LMUL uop），一次点积的 uop 数：(a) **1**；(b) 2 + 2 + 2 + 4 = **10**；(c) 2 + 1 + 2 + 2 = **7**。

### 3.2 应用级内核：INT8 GEMV（LLM 线性层内循环）

$y[M] = W[M \times K] \cdot x[K]$，`M = 16`、`K = 256`（4096 次 INT8 乘加），三种标准向量实现、两种 vdota 实现 + 标量 C：

| 内核 | 每 32 个元素的指令 | 特点 |
| :--- | :--- | :--- |
| `k_gemv_vdot` | 8× `vle8`(8B) + 4× `vdot.vv` + 2× `vsetivli` + 4× `vadd.vv@e32` | 4 个独立 int32 累加器；vdot 只用到寄存器的低 64 位 |
| `k_gemv_base` | 8× `vle8` + 4× `vwmul@mf2` + 2× `vsetivli` + 4× `vwredsum`（经 `vs1` 累加） | 与 vdot 版逐块对应的“相同功能”基线 |
| `k_gemv_rvv` | 4× `vle8`(16B) + 2× `vwmul@m1` + 2× `vsetivli` + 2× `vwadd.wv@e16/m2` | 满宽 128 位，逐元素累加到 e32/m4，每行末尾一次 `vredsum` |
| `k_gemv_vdota` | 8× `vle8`(8B) + 4× `vdota.vv` | 4 个累加器整行常驻 `v24..v27`，循环内没有 `vsetvli` 和 `vadd` |
| `k_gemv_vdota16` | 4× `vle8`(16B) + 4× `vslidedown.vi` + 4× `vdota.vv` | 每个加载的字节都被使用；vdota 只读低 64 位，高 8 字节用 `vslidedown` 移到低半部分 |

---

## 4. 延迟与加速比分析（对应评分项 3.3）

### 4.1 测量方法

每个内核在计时区间前后用 `csrr mcycle / minstret` 读计数器（香山中 CSR 读不推测执行，计数器严格括住区间内的指令）；每个内核先运行一次预热 I-Cache/TLB，报告第二次的结果；所有内核的输出都与 C 参考模型比对，DiffTest 同时逐条比对 NEMU。平台：香山 `emu`（MinimalConfig），vimac 延迟 2、vipu 延迟 2、vialu 延迟 1（`FuConfig.scala`）；在默认配置上的复测见 4.5 节。

原始输出（`vdot_bench` 在最终 RTL 的香山 emu + DiffTest 上，`logs/emu.log`）：

```text
latency (dependent chain, 8 per iteration):
  vdot.vv                cycles=1725  instret=339  cycles/dot=    6.73  instr/dot=    1.32
  vwmul(m1)+vwredsum     cycles=7380  instret=1109  cycles/dot=   28.82  instr/dot=    4.33
  vwmul(mf2)+vwredsum    cycles=5299  instret=1109  cycles/dot=   20.69  instr/dot=    4.33
  vdota.vv (accumulate)  cycles=1724  instret=340  cycles/dot=    6.73  instr/dot=    1.32
throughput (independent, 8 per iteration):
  vdot.vv                cycles=328  instret=325  cycles/dot=    1.28  instr/dot=    1.26
  vwmul(mf2)+vwredsum    cycles=818  instret=642  cycles/dot=    3.19  instr/dot=    2.50
INT8 GEMV M=16 K=256 (4096 MACs):
  scalar C (-O2)         cycles=14637  instret=28821  cycles/8MAC=   28.58  instr/8MAC=   56.29
  vdot.vv                cycles=3508  instret=3820  cycles/8MAC=    6.85  instr/8MAC=    7.46
  vwmul+vwredsum (x8)    cycles=4007  instret=3835  cycles/8MAC=    7.82  instr/8MAC=    7.49
  RVV full-width         cycles=2400  instret=2275  cycles/8MAC=    4.68  instr/8MAC=    4.44
  vdota.vv (8B loads)    cycles=2825  instret=3090  cycles/8MAC=    5.51  instr/8MAC=    6.03
  vdota.vv (16B+slide)   cycles=2517  instret=2556  cycles/8MAC=    4.91  instr/8MAC=    4.99
[vdot-bench] all results match the scalar reference
```

（`instret` 由香山的 `minstret` 读出，按提交组计数，与 NEMU 的精确指令数相差几条；准确的指令数以 NEMU 为准：vdot 链 1.25 条/点积、基线 4.25 条/点积。）

### 4.2 单次 8 元素点积：延迟与吞吐

| 指标 | 基线 m1 | 基线 mf2（调优） | **vdot.vv** | 加速比 |
| :--- | ---: | ---: | ---: | :--- |
| 每次点积的指令数（不含循环开销） | 4 | 4 | **1** | 4× |
| 每次点积的 uop 数（`UopInfoGen`） | 10 | 7 | **1** | 7~10× |
| 每次点积需要的 `vtype` 切换 | 2 | 2 | **0** | — |
| **依赖链延迟（周期/次）** | 28.82 | 20.69 | **6.73** | **4.28× / 3.07×** |
| **吞吐（周期/次）** | — | 3.19 | **1.28** | **2.49×** |

`vdota.vv` 经 `vd` 串成的累加链同样是 6.73 拍/次：累加值作为部分积矩阵中的一行进入同一棵树，old vd 与 vs1/vs2 在同一个读寄存器堆阶段读出，累加没有增加延迟。

**延迟为什么是 6.7 拍而不是 2 拍**：`VIMacU` 本身只占 2 拍（2.5 节波形），其余约 4.7 拍是向量流水线中“发射 → 读寄存器堆（og0/og1）→ 执行 → 写回 → 唤醒下一条”的固定开销，任何相互依赖的向量 uop 之间都要付出。上一版文档按“vdot 2 拍 vs 基线 8 拍”给出 4.00×，既没有计入这部分开销，基线的 uop 数也少算了。实测数据可以按“依赖链上串行的 uop 跳数”来解释：

- vdot：每次 1 跳（约 6.7 拍）；
- 基线 mf2：`vwmul`（1 uop）→ `vwredsum`（2 个串行 uop），约 3 跳 ≈ 20.7 拍；
- 基线 m1：`vwmul` 2 uop + `vwredsum` 4 个串行 uop，约 4.3 跳 ≈ 28.8 拍。

**吞吐**：只有 VFEX0 有 `vimac`，vdot 最多每拍 1 条，实测 1.28 拍/次（含循环开销）；基线的 `vwredsum` 只能在 VFEX1 的 `vipu` 上执行，每次点积 2 个 uop，因此至少 2 拍/次，实测 3.19。

### 4.3 应用级：INT8 GEMV（M = 16，K = 256）

| 内核 | 周期 | 周期 / 8 MAC | 指令 / 8 MAC | 加载字节 / 拍 | 相对 vdot |
| :--- | ---: | ---: | ---: | ---: | :--- |
| 标量 C（`-O2`） | 14 637 | 28.58 | 56.29 | 0.56 | vdot 快 4.17× |
| 同功能基线（每 8 元素 `vwmul + vwredsum`） | 4 007 | 7.82 | 7.49 | 2.04 | vdot 快 1.14× |
| **vdot.vv** | **3 508** | **6.85** | 7.46 | 2.34 | — |
| 满宽 RVV（16 B/次加载，逐元素累加，末尾一次归约） | 2 400 | 4.68 | 4.44 | 3.41 | 比 vdot 快 1.46× |
| vdota.vv（8 B 加载） | 2 825 | 5.51 | 6.03 | 2.90 | 比 vdot 快 1.24× |
| **vdota.vv（16 B 加载 + `vslidedown`）** | **2 517** | **4.91** | 4.99 | 3.25 | **比 vdot 快 1.39×，比同功能基线快 1.59×** |

“加载字节/拍”按每个内核实际读入的字节数计算：矩阵 4 096 B，加上每行重新读一遍的 x（16 × 256 = 4 096 B），共 8 192 B，除以周期数。

这一组数据给出了单条指令加速比之外的结论：

1. 与“相同功能”的基线相比，vdot 在 GEMV 中只快 1.14×。点积本身已不是瓶颈，瓶颈在访存（vdot 版每 32 个元素要 8 次 8 字节加载）、`vtype` 切换（累加需要切到 e32）与累加用的 `vadd`。
2. 用满 128 位、把归约推迟到行末的 RVV 写法比 vdot 版快 1.46×，因为 vdot 按赛题定义**只使用寄存器的低 64 位、只产生一个 int32、不带累加**。
3. 扩展指令 `vdota.vv` 正是针对第 1 条：内循环去掉 `vsetivli` 与 `vadd` 后快 1.24×；再改用 16 字节加载、让每个读入的字节都被使用，比 vdot 版快 1.39×，比同功能基线快 1.59×，达到满宽 RVV 写法的 95%（4.91 对 4.68 拍/8 MAC）。
4. 两个使用 16 字节加载的内核做的其他工作差别很大：满宽 RVV 每 32 个元素约 20 个向量 uop（含扩位乘和扩位加），vdota16 只有 12 个（4 次加载、4 次 `vslidedown`、4 条 vdota），但两者都跑在 3.25~3.41 B/拍。由此推断，在 MinimalConfig 中这个 GEMV 已经接近向量加载的吞吐上限，再减少计算指令对周期数帮助有限（推断，未单独测量向量加载带宽）。默认配置的加载队列等结构更大，实测这个上限提高到约 4 B/拍，各内核的排名也随之变化（4.5 节）。

### 4.4 由实测得到的扩展建议

| 方向 | 做法 | 实测或预期效果 | 在本设计中的硬件代价 |
| :--- | :--- | :--- | :--- |
| 累加形式 `vdota.vv`（**已实现**） | `vd[31:0] += Σ`（读 old vd） | 实测：GEMV 比 vdot 快 1.39×，依赖链延迟不变（4.2、4.3 节） | 在融合矩阵中多加一行 32 比特，树宽 19 → 32 列，晶体管约 +4%，仍然只有一个 CPA；译码改为 `vdRen = T` 并加入 `vmaInsts`（阶段二 2.4 节） |
| 用满 128 位 | 2 组 × 8 字节 → 2 个 int32，或 4 组 × 4 字节 → 4 个 int32（类似 ARM `SDOT`） | 去掉 vdota16 中的 4 次 `vslidedown`，点积指令减半（每 32 个元素 12 → 6 个向量 uop）。按第 4 条，GEMV 已接近加载上限，周期收益有限；收益主要在数据在寄存器中复用、受计算吞吐限制的内核（如 prefill 阶段的 GEMM），吞吐测试中 vdot 已比基线快 2.49×，分组后每条指令的乘加数翻倍 | 部分积矩阵已经有 16 lane 的参数化版本（`VDot128(vlen = 256, lanes = 16)`）；分组时把矩阵按组拆成 2~4 棵独立的 Dadda 树 |
| 去掉 `vl` 依赖 | `DecodeUnit` 中 vdot 的 `srcType(4) = no` | vdot 不必等前一条 `vsetvli` 写回 `vl` | 仅译码改动 |

分组形式的效果是按指令数与上面的带宽推断估算的，未经 RTL 实测，列为后续工作。

### 4.5 默认配置（DefaultConfig）下的复测：哪些结论不变，哪些变了

同一个 `vdot_bench` 在默认配置 emu 上的输出（`logs/emu_default.log`）与 MinimalConfig 对比：

| 指标 | MinimalConfig | **DefaultConfig** |
| :--- | ---: | ---: |
| vdot 依赖链（拍/次） | 6.73 | **6.67** |
| vdota 累加链（拍/次） | 6.73 | **6.66** |
| 基线 m1 / mf2 依赖链（拍/次） | 28.82 / 20.69 | **28.82 / 20.69** |
| vdot 吞吐 / 基线 mf2 吞吐（拍/次） | 1.28 / 3.19 | **1.28 / 3.19** |

| GEMV 内核 | MinimalConfig 周期（拍/8 MAC，B/拍） | **DefaultConfig 周期（拍/8 MAC，B/拍）** | 默认配置下相对 vdot |
| :--- | ---: | ---: | :--- |
| 标量 C（`-O2`） | 14 637（28.58，0.56） | **8 173（15.96，1.00）** | vdot 快 2.99× |
| 同功能基线 | 4 007（7.82，2.04） | **3 179（6.20，2.58）** | vdot 快 1.16× |
| vdot.vv | 3 508（6.85，2.34） | **2 729（5.33，3.00）** | — |
| 满宽 RVV | 2 400（4.68，3.41） | **2 255（4.40，3.63）** | 比 vdot 快 1.21× |
| vdota.vv（8 B 加载） | 2 825（5.51，2.90） | **2 035（3.97，4.03）** | **比 vdot 快 1.34×，比同功能基线快 1.56×，比满宽 RVV 快 1.11×** |
| vdota.vv（16 B 加载 + `vslidedown`） | 2 517（4.91，3.25） | **2 091（4.08，3.92）** | 比 vdot 快 1.31×，比满宽 RVV 快 1.08× |

**不变的结论**

1. **正确性**：全部程序与反例的结果相同（2.7 节）。
2. **单条指令的延迟与吞吐**：vdot 与基线的依赖链、吞吐几乎完全相同（vdot 链 6.73 → 6.67，差 1%），即 3.07~4.28× 的延迟加速比与 2.49× 的吞吐加速比与配置无关。这符合预期：它们由向量流水线的级数和 `vimac` / `vipu` 单元的个数决定，而两种配置的向量执行部分相同。
3. **vdot 相对同功能基线的 GEMV 加速比**：1.14× → 1.16×，基本不变。
4. **数据通路的 PPA 对比**：`VDot128` 在两种配置中是同一份 RTL，阶段二第 4 节的综合结果不受配置影响。

**变了的结论**

1. **所有 GEMV 内核都变快了，但幅度差别很大**：标量 C 快了 1.79×（IPC 1.97 → 3.54，ROB 与读队列变大后能同时在途的标量加载多得多）；向量内核只快 1.06~1.39×。
2. **排名变了**：MinimalConfig 中满宽 RVV 写法最快、vdota 只达到它的 95%；默认配置中两种 vdota 写法都**超过**满宽 RVV（1.08~1.11×）。
3. **vdota 的最佳写法变了**：MinimalConfig 中“16 字节加载 + `vslidedown`”更快；默认配置中直接用 8 字节加载的写法更快（2 035 对 2 091 拍）。一个可能的解释（未单独验证）：读队列从 24 项增大到 72 项后，多发几条 8 字节加载已不是负担，而 4 条 `vslidedown` 带来的额外 uop 与依赖反而更贵。
4. **加载上限提高了**：最快内核从约 3.4 B/拍升到约 4.0 B/拍，4.3 节“接近向量加载上限”的推断在两种配置下都成立，但上限本身取决于配置。

因此，**电路和单条指令层面的结论与配置无关**；而“哪种软件写法最快、扩展指令比标准写法快多少”这类应用层结论会随配置变化，应以目标配置的实测为准。本项目两套数字都给出：vdota 在 MinimalConfig 中达到满宽 RVV 的 95%，在默认配置中比它快 11%。
