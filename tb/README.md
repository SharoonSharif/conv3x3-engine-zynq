# Testbenches

Self-checking and bit-exact against vectors from `golden/gen_vectors.py`
(`tb/vectors/`, 160x120 scene) and `golden/gen_vectors_wide.py` (seeded
random images at any size). Six kernel cases: Sobel (dual, k=3), Scharr
(dual, k=5), Prewitt (dual, k=3), Gaussian (single, k=4), Laplacian
(single, rectified, k=0) and sharpen (single, **signed**, k=0).

Run **from the repository root**; the testbenches read `tb/vectors...`
relative to the working directory.

## `tb_engine.v` and `tb_sobel_fixed.v`

* `tb_engine.v` — two frames through `conv3x3_engine`. Frame 1 uses the
  reset Sobel kernels. Then comes a full 19-write AXI4-Lite kernel swap
  between frames (the cycle count is printed, and `STATUS.pending` is
  checked), then frame 2 with the new kernel. Every pixel and the TLAST
  count are checked.
* `tb_sobel_fixed.v` — one frame through `sobel_fixed`.

Both apply random AXI4-Stream backpressure (LFSR-driven `m_axis_tready`,
about 80% ready) and random input gaps. Note that this driver drops TVALID
for at least one cycle between pixels; `tb_engine_ext.v` covers full-rate
input.

    tb\run_xsim.bat          (Vivado bin on PATH; logs in tb/logs/)

Icarus Verilog:

    iverilog -g2012 -o eng.vvp rtl/conv3x3_engine.v tb/tb_engine.v
    vvp eng.vvp +CFG=tb/vectors/cfg_sharpen.hex +EXP2=tb/vectors/exp_sharpen.hex
    iverilog -g2012 -o sob.vvp rtl/sobel_fixed.v tb/tb_sobel_fixed.v && vvp sob.vvp

## `tb_engine_ext.v`

Frame size is set at compile time (`-d TB_W=... -d TB_H=... -d TB_CW=...`,
default 160 x 120, CW 9). Plusargs:

* `+VEC=<dir>`, `+CASE=<kernel>`: vector directory and the frame-2 kernel.
* `+FULLRATE`: TVALID back-to-back, TREADY always high.
* `+MIDFRAME`: write the new kernel while frame 1 is at input row H/2;
  frame 1 must stay pure Sobel.
* `+ENPAUSE`: clear CTRL.EN mid-frame for 300 cycles (no input may be
  accepted), then set it again; frame 1 must stay bit-exact.

It reports cycles per frame, input stall cycles and the frame-1 latency
(first accepted input beat to first output beat).

    tb\run_xsim_ext.bat      160x120 and 1920x16: 6 kernels mid-frame, full-rate and EN-pause runs
    tb\run_xsim_1080p.bat    1920x1080, Scharr, full rate + mid-frame
    tb\run_xsim_bram.bat     the engine runs of all three scripts again with the
                             block-RAM line buffers (-d "TB_LB_BRAM=1" -> DUT
                             parameter LB_BRAM = 1); logs in tb/logs_bram/

Both testbenches accept `-d TB_LB_BRAM=<0|1>` (default 0) and pass it to the
DUT's `LB_BRAM` parameter.

### Long-run and adversarial mode (`+FRAMES`)

* `+FRAMES=N`: stream N frames of the same image back to back. Frame 1 uses
  the reset Sobel configuration; frames 2..N cycle through scharr, prewitt,
  gaussian, laplacian, sharpen, sobel. The kernel of frame f+1 is written
  (19 AXI4-Lite writes) while frame f streams, at an LFSR-chosen input row
  (row 0 and row H-1 each with probability 1/8, otherwise uniform), and every
  frame is compared against the expected image of its own kernel. Only the
  expected images a run needs are loaded. `+CASE` is ignored.
* `+NOSWAP`: long-run mode without any kernel write (all frames Sobel).
* `+ADVERSARIAL`: around every commit point `m_axis_tready` is held low for an
  LFSR-chosen 1000..2000 cycles. Per frame the LFSR picks (A) hold the SOF beat
  until the engine is idle and present it with TREADY already low, so the stall
  starts in the very cycle the SOF beat is accepted, or (B) present the SOF
  back to back behind the previous frame, so it is accepted while the previous
  frame's tail is still in the pipe and the stall starts in the cycle after the
  accept edge. A second stall starts at the first EOL of every frame (in its
  accept cycle), and 2..4 input gaps (TVALID low) of 500..1499 cycles are
  inserted per frame at LFSR-chosen mid-line pixels. The usual random
  backpressure and input gaps apply elsewhere; kernel writes may land inside a
  stall (row-0 writes always do).
* `+VERBOSE`: one line per stall / gap event (never per cycle).

Protocol checks (TUSER on the first pixel only, TLAST on the last column) and
`STATUS.pending` checks stay active across all frames; a watchdog aborts after
200,000 cycles without any handshake.

    tb\run_xsim_long.bat [all|a|b|c|d|e|f]    runs and results: tb/logs_long/README.md

## Recorded results (xsim 2026.1, regenerated 2026-10-05): 55 runs, all TB PASS

| Run | Result |
|---|---|
| `tb_engine.v`, 6 kernels | 0 mismatches / 19,200 px on both frames, TLAST 240/240 |
| `tb_sobel_fixed.v` | 0 mismatches / 19,200 px, TLAST 120/120 |
| `tb_engine_ext.v`, 6 kernels mid-frame, 160x120 and 1920x16 | bit-exact; the frame in flight is unaffected |
| full rate, 160x120 / 1920x16 / 1920x1080 | 19,484 / 32,660 / 2,076,604 cycles per frame |
| EN pause, 160x120 and 1920x16 at full rate | no input accepted for 300 cycles; bit-exact |
| every kernel swap | 76 clock cycles for 19 AXI4-Lite writes |

The engine accepts W pixels per W + 1 cycles within a frame and needs a
(W + 1)-cycle bottom-border flush per frame. A full 1920x1080 frame fits
well inside the 2,475,000-cycle 1080p60 frame period at 148.5 MHz.
