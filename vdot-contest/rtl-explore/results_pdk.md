# VDot128 in real standard-cell libraries (Yosys 0.33 + ABC, synthesis-level STA)

Combinational delay per pipeline segment in ps (ABC `stime`: NLDM tables, fanout loads, no wire load, inputs driven by a X2 buffer, D-pin load), for two ABC scripts: `struct` maps the structure Yosys built (Dadda tree, Brent-Kung adders) as is, `restructure` is Yosys' default liberty script (AIG rewriting first). `cycle` = clk->q + worst register-to-register segment + setup of the library DFF. Area: whole module incl. flip-flops (default area-recovering mapping), um^2.

## NanGate 45 nm (FreePDK45, typical)

126 cells after dont_use; DFF DFF_X1: clk->q 110.9 ps, setup 39.8 ps, D cap 1.140 fF.

### ABC script: struct

| design | S1 | S2 | out | worst reg-to-reg | cycle | area | FFs |
|---|---|---|---|---|---|---|---|---|
| v2: 4 CSA trees + 4 CPAs (old) | 1158 | 549 | 0 | 1158 | 1309 | 6662 | 88 |
| v3: fused Dadda, vdot only, cut 6 | 627 | 826 | 0 | 826 | 977 | 4363 | 161 |
| v3: fused Dadda, vdot only, cut 7 | 720 | 747 | 0 | 747 | 898 | 4120 | 118 |
| v3: fused Dadda, vdot only, cut 8 | 793 | 610 | 0 | 793 | 944 | 3973 | 88 |
| v3: fused Dadda, vdot only, cut 9 | 905 | 567 | 0 | 905 | 1056 | 4000 | 72 |
| v3: fused Dadda, vdot only, cut 10 | 1014 | 385 | 0 | 1014 | 1165 | 3911 | 56 |
| v3: fused Dadda + acc, cut 6 | 604 | 956 | 0 | 956 | 1107 | 4795 | 193 |
| v3: fused Dadda + acc, cut 7 | 750 | 800 | 0 | 800 | 951 | 4521 | 148 |
| v3: fused Dadda + acc, cut 8 (shipped) | 841 | 672 | 0 | 841 | 992 | 4287 | 117 |
| v3: fused Dadda + acc, cut 9 | 924 | 646 | 0 | 924 | 1075 | 4215 | 101 |
| v3: fused Dadda + acc, cut 10 | 1043 | 534 | 0 | 1043 | 1193 | 4188 | 97 |
| XiangShan VIMac64b (existing multiplier) | 938 | 1964 | 1003 | 1964 | 2114 | 35243 | 838 |

### ABC script: restructure

| design | S1 | S2 | out | worst reg-to-reg | cycle | area | FFs |
|---|---|---|---|---|---|---|---|---|
| v2: 4 CSA trees + 4 CPAs (old) | 1060 | 795 | 0 | 1060 | 1211 | 6662 | 88 |
| v3: fused Dadda, vdot only, cut 6 | 571 | 973 | 0 | 973 | 1123 | 4363 | 161 |
| v3: fused Dadda, vdot only, cut 7 | 678 | 860 | 0 | 860 | 1011 | 4120 | 118 |
| v3: fused Dadda, vdot only, cut 8 | 780 | 740 | 0 | 780 | 931 | 3973 | 88 |
| v3: fused Dadda, vdot only, cut 9 | 872 | 692 | 0 | 872 | 1023 | 4000 | 72 |
| v3: fused Dadda, vdot only, cut 10 | 971 | 533 | 0 | 971 | 1122 | 3911 | 56 |
| v3: fused Dadda + acc, cut 6 | 572 | 1236 | 0 | 1236 | 1387 | 4795 | 193 |
| v3: fused Dadda + acc, cut 7 | 677 | 1216 | 0 | 1216 | 1366 | 4521 | 148 |
| v3: fused Dadda + acc, cut 8 (shipped) | 792 | 1076 | 0 | 1076 | 1227 | 4287 | 117 |
| v3: fused Dadda + acc, cut 9 | 894 | 989 | 0 | 989 | 1140 | 4215 | 101 |
| v3: fused Dadda + acc, cut 10 | 979 | 1000 | 0 | 1000 | 1151 | 4188 | 97 |
| XiangShan VIMac64b (existing multiplier) | 867 | 4757 | 988 | 4757 | 4908 | 35243 | 838 |

## ASAP7 7 nm predictive (RVT, TT)

121 cells after dont_use; DFF DFFHQNx1_ASAP7_75t_R: clk->q 83.4 ps, setup 10.9 ps, D cap 0.559 fF.

### ABC script: struct

| design | S1 | S2 | out | worst reg-to-reg | cycle | area | FFs |
|---|---|---|---|---|---|---|---|---|
| v2: 4 CSA trees + 4 CPAs (old) | 718 | 375 | 0 | 718 | 813 | 578 | 88 |
| v3: fused Dadda, vdot only, cut 6 | 343 | 459 | 0 | 459 | 553 | 365 | 161 |
| v3: fused Dadda, vdot only, cut 7 | 394 | 405 | 0 | 405 | 499 | 348 | 118 |
| v3: fused Dadda, vdot only, cut 8 | 451 | 356 | 0 | 451 | 546 | 339 | 88 |
| v3: fused Dadda, vdot only, cut 9 | 510 | 310 | 0 | 510 | 605 | 331 | 72 |
| v3: fused Dadda, vdot only, cut 10 | 560 | 264 | 0 | 560 | 654 | 325 | 56 |
| v3: fused Dadda + acc, cut 6 | 344 | 546 | 0 | 546 | 641 | 398 | 193 |
| v3: fused Dadda + acc, cut 7 | 391 | 501 | 0 | 501 | 596 | 378 | 148 |
| v3: fused Dadda + acc, cut 8 (shipped) | 446 | 421 | 0 | 446 | 541 | 369 | 117 |
| v3: fused Dadda + acc, cut 9 | 503 | 385 | 0 | 503 | 597 | 359 | 101 |
| v3: fused Dadda + acc, cut 10 | 561 | 331 | 0 | 561 | 656 | 356 | 97 |
| XiangShan VIMac64b (existing multiplier) | 554 | 1569 | 661 | 1569 | 1663 | 3060 | 838 |

### ABC script: restructure

| design | S1 | S2 | out | worst reg-to-reg | cycle | area | FFs |
|---|---|---|---|---|---|---|---|---|
| v2: 4 CSA trees + 4 CPAs (old) | 760 | 639 | 0 | 760 | 855 | 578 | 88 |
| v3: fused Dadda, vdot only, cut 6 | 357 | 706 | 0 | 706 | 800 | 365 | 161 |
| v3: fused Dadda, vdot only, cut 7 | 428 | 652 | 0 | 652 | 747 | 348 | 118 |
| v3: fused Dadda, vdot only, cut 8 | 475 | 591 | 0 | 591 | 686 | 339 | 88 |
| v3: fused Dadda, vdot only, cut 9 | 548 | 552 | 0 | 552 | 646 | 331 | 72 |
| v3: fused Dadda, vdot only, cut 10 | 606 | 599 | 0 | 606 | 700 | 325 | 56 |
| v3: fused Dadda + acc, cut 6 | 354 | 868 | 0 | 868 | 962 | 398 | 193 |
| v3: fused Dadda + acc, cut 7 | 429 | 875 | 0 | 875 | 969 | 378 | 148 |
| v3: fused Dadda + acc, cut 8 (shipped) | 475 | 826 | 0 | 826 | 920 | 369 | 117 |
| v3: fused Dadda + acc, cut 9 | 538 | 757 | 0 | 757 | 851 | 359 | 101 |
| v3: fused Dadda + acc, cut 10 | 589 | 1060 | 0 | 1060 | 1154 | 356 | 97 |
| XiangShan VIMac64b (existing multiplier) | 573 | 3671 | 649 | 3671 | 3765 | 3060 | 838 |
