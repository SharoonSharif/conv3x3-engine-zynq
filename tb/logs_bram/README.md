# xsim logs, conv3x3_engine with LB_BRAM = 1 (block-RAM line buffers)

Produced by `tb\run_xsim_bram.bat` (Vivado 2026.1 xsim), which repeats
every engine run of `run_xsim.bat`, `run_xsim_ext.bat` and
`run_xsim_1080p.bat` with `-d "TB_LB_BRAM=1"` (`tb_engine.v` and
`tb_engine_ext.v` pass `.LB_BRAM(`TB_LB_BRAM)` to the DUT). Run from the
repository root with Vivado's bin on PATH after regenerating the vectors:

    python golden/gen_vectors.py
    python golden/gen_vectors_wide.py 1920 16
    python golden/gen_vectors_wide.py 1920 1080
    tb\run_xsim_bram.bat

## Results (2026-10-05): 24 runs, all TB PASS

| Run | Log(s) | Result |
|---|---|---|
| `tb_engine.v`, 6 kernels, 160x120, random gaps + backpressure, kernel swap between frames | `engine_<kernel>.log` | 0 mismatches / 19,200 px on both frames, TLAST 240/240, swap = 76 cycles |
| `tb_engine_ext.v`, 6 kernels written mid-frame, 160x120 | `w160_<kernel>_midframe.log` | bit-exact, TLAST 240/240 |
| `tb_engine_ext.v`, 6 kernels written mid-frame, 1920x16 | `w1920_<kernel>_midframe.log` | bit-exact, TLAST 32/32 |
| full rate, 160x120 / 1920x16 / 1920x16 + mid-frame | `w160_scharr_fullrate.log`, `w1920_scharr_fullrate*.log` | 19,484 / 32,660 / 32,660 cycles per frame |
| EN pause (300 cycles), 160x120 and 1920x16 full rate | `w160_sobel_enpause.log`, `w1920_sobel_enpause_fullrate.log` | no input accepted while EN = 0; bit-exact |
| full 1920x1080 frame pair, full rate, Scharr written mid-frame | `w1920_h1080_scharr_fullrate_midframe.log` | bit-exact, TLAST 2160/2160, 2,076,604 cycles per frame |

Cycles per frame (first input beat to last output beat) are identical to
the LB_BRAM = 0 logs in `../logs_ext/`: 19,484 (160x120), 32,660 (1920x16)
and 2,076,604 (1920x1080), i.e. the one-cycle-early block-RAM read keeps
the W pixels per W + 1 cycles throughput. `sobel_fixed` has no LB_BRAM
parameter and is not repeated here.
