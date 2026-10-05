# Long-run and adversarial simulation logs (`tb/run_xsim_long.bat`)

Multi-frame, mid-frame-reprogramming and adversarial-backpressure runs of
`conv3x3_engine` with `tb/tb_engine_ext.v` in long-run mode (`+FRAMES`).
xsim 2026.1, RTL at the v1.2 state of `rtl/conv3x3_engine.v` (unchanged by
this experiment).

## Commands

From the repository root, with Vivado's `bin` on PATH:

    python golden/gen_vectors_wide.py 1920 16
    python golden/gen_vectors_wide.py 1920 1080      (tb/vectors_w1920_h1080/ is gitignored, ~37 MB)
    tb\run_xsim_long.bat                              (all six runs, about 6 minutes on a 12-core desktop)
    tb\run_xsim_long.bat c                            (a single run: a, b, c, d, e or f)

The script compiles three snapshots (160x120 CW 9, 1920x16 CW 11,
1920x1080 CW 11) and runs:

| run | size | plusargs | pixels |
|---|---|---|---|
| a | 1920x16 | `+FRAMES=60 +ADVERSARIAL` | 1,843,200 |
| b | 160x120 | `+FRAMES=120 +ADVERSARIAL` | 2,304,000 |
| c | 1920x1080 | `+FRAMES=4 +FULLRATE` | 8,294,400 |
| d | 1920x1080 | `+FRAMES=3 +ADVERSARIAL` | 6,220,800 |
| e | 1920x1080 | `+FRAMES=2 +FULLRATE +NOSWAP` | 4,147,200 |
| f | 1920x1080 | `+FRAMES=2 +FULLRATE` (one mid-frame swap) | 4,147,200 |

## What the runs do

* Frame 1 always uses the reset Sobel configuration. For frames 2..N the
  kernel rotates through scharr, prewitt, gaussian, laplacian, sharpen, sobel.
  The kernel of frame f+1 is written with 19 AXI4-Lite writes while frame f is
  streaming, at an LFSR-chosen input row (row 0 and the last row each with
  probability 1/8, otherwise uniform). Every frame is compared pixel by pixel
  with the expected image of the kernel that is active for that frame;
  `STATUS.pending` is checked after every write burst (set) and after every
  start of frame (cleared).
* `+ADVERSARIAL`: around every commit point `m_axis_tready` is held low for an
  LFSR-chosen 1000..2000 cycles. Per frame the LFSR picks (A) hold the SOF beat
  until the engine is idle and present it with TREADY already low, so the stall
  starts in the very cycle the SOF beat is accepted, or (B) present the SOF
  back to back behind the previous frame, so it is accepted while the previous
  frame's tail is still in the pipe and the stall starts in the cycle after the
  accept edge. A second stall starts at the first EOL of every frame (in its
  accept cycle, since row 0 produces no output; when the SOF stall is still
  running it is extended). 2..4 input gaps (TVALID low) of 500..1499 cycles are
  inserted per frame at LFSR-chosen mid-line pixels. The usual random
  backpressure (TREADY high about 87% of cycles) and random input gaps (about
  25%) apply everywhere else. Kernel writes issued at row 0 land inside the
  SOF stall.
* Protocol checks (TUSER on the first pixel of every frame only, TLAST on the
  last column of every line, no extra beats after the last frame) stay active
  across all frames. A watchdog aborts after 200,000 cycles without any
  handshake.
* Measurements: latency from the first accepted input beat to the first output
  beat of frame 1, cycles per frame (first accepted input beat to last output
  beat of that frame), pixels checked, mismatches, kernel swaps, longest
  TREADY-low stretch, number and length of input gaps.

## Results

All six runs: **TB PASS**, 0 mismatches, 0 TUSER / TLAST errors, 0 extra
beats, 0 `STATUS` errors. Recorded 2026-10-05 with xsim 2026.1; wall time is
xsim's own `elapsed` figure (after loading the vectors).

| run | size | frames | pixels checked | kernel swaps | mismatches | latency frame 1 | cycles / frame (first in .. last out) | wall |
|---|---|---|---|---|---|---|---|---|
| a | 1920x16, adversarial | 60 | 1,843,200 | 59 | 0 | 5,122 cyc (34.49 us) | 49,798 .. 56,233, mean 53,082 | 17 s |
| b | 160x120, adversarial | 120 | 2,304,000 | 119 | 0 | 1,900 cyc (12.80 us) | 31,483 .. 38,019, mean 34,648 | 18 s |
| c | 1920x1080, full rate | 4 | 8,294,400 | 3 | 0 | 1,926 cyc (12.97 us) | 2,076,604 (all four frames) | 60 s |
| d | 1920x1080, adversarial | 3 | 6,220,800 | 2 | 0 | 4,211 cyc (28.36 us) | 3,058,052 / 3,059,399 / 3,059,511 | 50 s |
| e | 1920x1080, full rate, no swap | 2 | 4,147,200 | 0 | 0 | 1,926 cyc (12.97 us) | 2,076,604 / 2,076,604 | 31 s |
| f | 1920x1080, full rate, one mid-frame swap | 2 | 4,147,200 | 1 | 0 | 1,926 cyc (12.97 us) | 2,076,604 / 2,076,604 | 31 s |
| **total** | | **191** | **26,956,800** | **184** | **0** | | | |

Latency = first accepted input beat to first output beat of frame 1 (the
engine needs row 0 and the first pixels of row 1 before it can emit the first
window); microseconds at 148.5 MHz. At full rate it is W + 6 = 1,926 cycles
(12.97 us) for W = 1920 and 166 cycles for W = 160 (`+FULLRATE +NOSWAP` at
160x120, not part of the batch). In the adversarial runs the first output beat
is held back by the start-of-frame stall, so the figure is larger.

Adversarial statistics (from the `adversarial:` line of each log):

| run | long TREADY stalls (planned length) | longest TREADY-low stretch | SOF held until idle / back-to-back | TREADY low in the accept cycle: SOF, first EOL | input gaps >= 500 cycles (longest) | kernel writes that finished during an output stall | swaps at row 0 / last row |
|---|---|---|---|---|---|---|---|
| a | 120 (1001 .. 2000) | 2,003 cycles (1,992 with an output beat pending) | 35 / 24 | 36 of 60, 60 of 60 | 183 (1,499) | 21 of 59 | 14 / 13 |
| b | 182 (1004 .. 1998) | 2,513 cycles (1,998 with an output beat pending) | 57 / 62 | 58 of 120, 120 of 120 | 351 (1,496) | 38 of 119 | 27 / 15 |
| d | 6 (1081 .. 1916) | 1,919 cycles (1,912 with an output beat pending) | 1 / 1 | 2 of 3, 3 of 3 | 11 (1,283) | 2 of 2 | 0 / 0 (rows 2 and 348) |

The longest contiguous TREADY-low stretch across all runs is 2,513 cycles
(run b): when the first-EOL trigger fires while the start-of-frame stall is
still running, the stall is extended to a fresh 1000..2000-cycle stretch from
that point, so one stretch can exceed 2,000 cycles.

**Does a kernel commit add a bubble?** No. Runs e (no kernel write at all) and
f (Scharr written mid-frame, committed at the start of frame 2) report the
identical 2,076,604 cycles for every frame and the identical 1,926-cycle
latency; run c shows the same 2,076,604 cycles for all four frames with three
mid-frame writes (rows 2, 348 and 0). 2,076,604 = 1080 x (1920 + 1) + 1921 + 3:
W + 1 cycles per row, a (W + 1)-cycle bottom-border flush and the pipeline
depth.

## Notes

* Every frame of every run is compared against the expected image of the
  kernel that is active for that frame (the kernel written during the previous
  frame commits at the start of frame, the frame in flight is never affected).
  184 swaps were performed in all; in runs a and b 41 of them were written at
  input row 0 (inside the start-of-frame output stall) and 28 at the last row.
* The 25 existing runs (`tb\run_xsim.bat`, `tb\run_xsim_ext.bat`,
  `tb\run_xsim_1080p.bat`) were re-run with the extended testbench on the
  same day: all TB PASS with the numbers recorded in `tb/README.md`; the
  `tb/logs_ext` logs were regenerated (they now also carry the latency line).
* Memory: xsim peaked at about 230 MB for the 1920x1080 runs (the testbench
  loads only the expected images a run needs: four for run c, three for d,
  two for f, one for e).
* Logs are redacted (host name and absolute paths replaced).
