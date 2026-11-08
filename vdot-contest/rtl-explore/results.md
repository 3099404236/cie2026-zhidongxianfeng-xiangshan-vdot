# VDot128 datapath exploration (Yosys 0.33 + ABC, generic gates)

* Area: whole module (incl. flip-flops), `synth -noabc` + `abc -g <lib>` default script;
  transistors from `stat -tech cmos` (flip-flops are not counted by -tech cmos).
* Depth: each pipeline stage synthesized alone with a delay-oriented ABC script
  (`strash; dch; map -D 1; topo`), longest combinational path from `ltp -noff`.
  The default ABC script is NOT used for depth: it re-ripples carry-lookahead adders
  (a 19-bit a+b becomes depth 36 instead of 14).
* Equivalence: every variant matched the C++ reference on all streamed vectors:

```
v1_cpa           1131108 vectors, 0 mismatches
v2_csa           1131108 vectors, 0 mismatches
v3_dadda_c3      1131108 vectors, 0 mismatches
v3_dadda_c4      1131108 vectors, 0 mismatches
v3_dadda_c5      1131108 vectors, 0 mismatches
v3_dadda_c6      1131108 vectors, 0 mismatches
v3_dadda_c7      1131108 vectors, 0 mismatches
v3_dadda_c8      1131108 vectors, 0 mismatches
v3_dadda_c9      1131108 vectors, 0 mismatches
```

| variant | stage-1 FFs | cells (gates) | transistors (cmos3) | S1 depth gates | S2 depth gates | S1 depth cmos3 | S2 depth cmos3 | critical stage cmos3 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| v1_cpa | 36 | 4267 | 33518 | 35 | 14 | 30 | 11 | **30** |
| v2_csa | 76 | 4137 | 29810 | 29 | 19 | 26 | 18 | **26** |
| v3_dadda_c3 | 357 | 3394 | 22406 | 7 | 30 | 8 | 28 | **28** |
| v3_dadda_c4 | 266 | 3306 | 21798 | 10 | 28 | 11 | 25 | **25** |
| v3_dadda_c5 | 194 | 3230 | 21418 | 13 | 26 | 13 | 23 | **23** |
| v3_dadda_c6 | 142 | 3181 | 20948 | 15 | 23 | 15 | 20 | **20** |
| v3_dadda_c7 | 99 | 3139 | 21334 | 18 | 20 | 18 | 18 | **18** |
| v3_dadda_c8 | 69 | 3108 | 23356 | 21 | 18 | 20 | 15 | **20** |
| v3_dadda_c9 | 53 | 3094 | 23508 | 23 | 16 | 23 | 13 | **23** |

## Chisel/firtool-generated RTL (the code that goes into XiangShan)

`VDot128.sv` emitted by `mill -i xiangshan.test.runMain xiangshan.backend.fu.vector.VDotVerilog`
(v3) and taken from the XiangShan build of the previous VDot.scala (v2). Whole module,
`ltp -noff` = deeper of the two pipeline stages.

| Chisel-generated VDot128 | cells (gates) | transistors (cmos3) | FFs | critical stage gates | critical stage cmos3 |
|---|---:|---:|---:|---:|---:|
| v2 word-level CSA | 5147 | 39404 | 88 | 32 | 34 |
| v3 fused Dadda, cutLevel = 7 | 3143 | 21358 | 118 | 20 | 18 |
