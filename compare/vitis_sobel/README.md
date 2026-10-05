# Baseline: AMD Vitis Vision `xf::cv::Sobel`

A like-for-like vendor baseline for `rtl/sobel_fixed.v`: AMD's own 3×3 Sobel
from the Vitis Vision library, wrapped so that it has the same external
interface class and computes the same output,
`y = clamp((|Gx| + |Gy|) >> 3, 0, 255)` on 8-bit pixels. It takes 8-bit
AXI4-Stream video in and out, receives `rows`/`cols` over AXI4-Lite,
processes one pixel per clock, and supports 1920×1080 frames. It targets the
same part, clock and Vivado flow as the engine and as the
[`filter2D` baseline](../vitis_filter2d/).

* Library: `github.com/Xilinx/Vitis_Libraries`, `vision/L1/include`, commit
  `3ab1ecd20cf338b3f8f2824fdfeee115f3398889` (2026-09-03), Apache-2.0. Not
  redistributed here.
* Tools: Vitis HLS 2026.1 (`vitis-run --mode hls`) and Vivado 2026.1.

## Files

| File | Purpose |
|---|---|
| `sobel_top.cpp` | HLS top: `AXIvideo2xfMat` → `Sobel<XF_BORDER_CONSTANT, XF_FILTER_3X3, XF_8UC1, XF_16SC1, 1080, 1920, XF_NPPC1>` → `sobel_combine` → `xfMat2AXIvideo`; `rows` and `cols` on AXI4-Lite; `#pragma HLS DATAFLOW` |
| `run_hls.tcl` | C synthesis for xc7z020clg400-1 at 6.734 ns |
| `tb_sobel.cpp` | C simulation against `sobel_fixed`'s expected output (`tb/vectors/exp_sobel.hex`) |
| `run_csim.tcl` | HLS-managed C simulation (`csim_design`); fails on this host, see below |
| `ooc_impl.tcl`, `ooc.xdc` | Out-of-context implementation of the HLS RTL with the engine's constraints (`default_flow` or `extratiming`) |
| `reports/` | HLS csynth reports and the Vivado utilization, timing and power reports (host name and paths redacted) |

## Run

    set VITIS_VISION_INC=<Vitis_Libraries>/vision/L1/include
    vitis-run --mode hls --tcl run_hls.tcl
    vivado -mode batch -source ooc_impl.tcl -tclargs default_flow

C simulation. `csim_design` (`run_csim.tcl`) fails on hosts where a stray
`C:\dev\null` file exists (`/dev/null:1: *** missing separator`); the direct
compile below uses the MinGW g++ bundled with Vivado and gives the same
result:

    g++ -std=c++14 -O2 -w -I<vision/L1/include> -I<Vitis>/include sobel_top.cpp tb_sobel.cpp -o csim
    ./csim            # reads ../../tb/vectors/{image,exp_sobel}.hex (160x120)

## What the library computes, and what was added

* `xf::cv::Sobel` with `DST_T = XF_16SC1` writes two `ap_int<16>` images
  holding the raw gradients, with the same kernel polarity as
  `sobel_fixed.v`: `gx = (t2 + 2·m2 + b2) − (t0 + 2·m0 + b0)` and
  `gy = (b0 + 2·b1 + b2) − (t0 + 2·t1 + t2)`. There is no normalization or
  scaling in the 16-bit path (`xFGradientX3x3`/`xFGradientY3x3` in
  `imgproc/xf_sobel.hpp`). With an 8-bit output type (`XF_8UC1`) the same
  functions instead clamp each gradient to `[0, 255]`, so every negative
  gradient becomes 0 and the sign is lost; that is why the 16-bit signed
  output was used.
* Borders: the library accepts only `XF_BORDER_CONSTANT` (it asserts on
  anything else) and pads the frame with zeros on all four sides.
  `sobel_fixed.v` replicates edge pixels. Border pixels therefore differ by
  design and are excluded from the comparison.
* `xf::cv::magnitude` with `XF_L1NORM` computes `|gx| + |gy|` into an `int16`
  with neither the `>> 3` nor the 8-bit clamp, so it is not bit-identical to
  the `sobel_fixed` formula on its own. A ten-line `sobel_combine` stage
  (II = 1) computes `clamp((|gx| + |gy|) >> 3, 0, 255)` exactly as the RTL.
* `sobel_combine` uses `#pragma HLS LOOP_FLATTEN off` on its row loop, like
  the library's own per-row kernels (`xFMagnitudeKernel`, `ProcessSobel3x3`).
  A first version without it let HLS flatten the row/column loops and build an
  11×11-bit `rows × cols` multiplier for the trip count, costing one DSP48
  that has nothing to do with the filter (HLS estimate 3,049 LUT, 2,158 FF,
  3 BRAM_18K, 1 DSP; kept as
  `reports/sobel_top_csynth_v0_flattened_combine.rpt`). The corrected version
  estimates 3,046 LUT, 2,090 FF, 3 BRAM_18K, 0 DSP.

## Results (2026-10-05)

**Functional equivalence.** The Vitis Sobel pipeline equals `sobel_fixed`'s
expected output on every interior pixel of the 160×120 test scene:
**0 mismatches / 18,644 interior pixels** (rows 1..H−2, cols 1..W−2).
All 556 / 556 border pixels differ (zero padding vs edge replication;
mean |diff| 56.3, max 112 grey levels on this scene). A NumPy model of the
same formula with edge replication reproduces `exp_sobel.hex` exactly, and
with zero padding reproduces the library's border values.

**HLS C synthesis** (`reports/*_csynth.rpt`, xc7z020-1, 6.734 ns target,
1920×1080 maximum):

| | Latency (cycles) min / max | Interval (cycles) min / max | Pixel-loop II / iteration latency | HLS estimate LUT / FF / BRAM_18K / DSP |
|---|---|---|---|---|
| Vitis Vision `Sobel` + combine (`sobel_top`) | 2,090,653 / 2,090,653 (14.078 ms) | 2,090,649 / 2,090,649 | Sobel `Col_Loop` 1 / 8; combine 1 / 4 | 3,046 / 2,090 / 3 / 0 |
| Vitis Vision `filter2D` (`filter2d_top`, [`../vitis_filter2d`](../vitis_filter2d/)) | 173 / 2,108,184 | 162 / 2,108,173 | `COL_LOOP` 1 / 17 | 3,057 / 3,358 / 3 / 9 |

The Sobel latency has min = max because the library fixes its loop trip
counts with `LOOP_TRIPCOUNT min=max` (1080 rows × 1920 columns); it is the
1080p worst case, not a true minimum. The kernel's `Row_Loop` takes
1,934 cycles per 1,920-pixel row (the pipelined `Col_Loop` plus a per-row
restart), i.e. 0.993 pixel/clock sustained, versus W/(W+1) = 0.9995 for
`sobel_fixed` at W = 1920. `filter2D`'s frame-level numbers vary with the
runtime `rows`/`cols` (its loops are not fixed), so its minimum is one tiny
frame.

**Implementation** (xc7z020clg400-1, 148.5 MHz, W = 1920, out of context,
default directives; `reports/sobel_top_default_flow_*`):

| | LUT (logic + mem) | LUTRAM / SRL | FF | BRAM tiles | DSP | WNS | Power total / dyn |
|---|---|---|---|---|---|---|---|
| `sobel_fixed` (this work; `synth/reports/current/W1920/`) | 1,532 (508 + 1,024) | 1,024 / 0 | 322 | 0 | 0 | +0.367 ns | 0.118 / 0.015 W |
| Vitis Vision `Sobel` + combine (this baseline) | 845 (842 + 3) | 0 / 3 | 1,163 | 1.5 (3 × RAMB18) | 0 | +0.926 ns | 0.124 / 0.021 W |
| Vitis Vision `filter2D` (1 kernel; `../vitis_filter2d`) | 956 (874 + 82) | 44 / 38 | 1,392 | 1.5 (3 × RAMB18) | 9 | +0.427 ns | 0.131 / 0.028 W |
| `conv3x3_engine` (this work, 2 kernels + magnitude) | 1,916 (892 + 1,024) | 1,024 / 0 | 816 | 0 | 18 | +0.076 ns | 0.156 / 0.053 W |

Timing: WNS +0.926 ns, TNS 0.000 ns, WHS +0.116 ns over 2,660 endpoints
(`reports/sobel_top_default_flow_tim_impl.rpt`). Power: 0.124 W total =
0.021 W dynamic + 0.103 W static (`reports/sobel_top_default_flow_power.rpt`).

**Where the line buffers went.** The HLS core keeps the library's three 1920×8-bit line buffers (`buf`, `buf_1`, `buf_2`, bound by `bind_storage type=RAM_S2P impl=BRAM` in `xFSobelFilter3x3`) in block RAM: 3 × RAMB18 (1.5 BRAM tiles) inside `Sobel_…_U0/grp_xFSobelFilter3x3_…` (`reports/sobel_top_default_flow_util_impl.rpt`), with 0 LUTRAM in the whole design and only 3 SRLs (window shift registers in the kernel's `Col_Loop`). `sobel_fixed` keeps its two
1920×8-bit line buffers in distributed RAM (1,024 LUTRAM), which is where its
LUT count comes from; the HLS core's logic is spread over the AXI4-Stream
adapters, the AXI4-Lite control block, the dataflow FIFOs and the kernel.

Like the `filter2D` baseline, the HLS core restarts per frame under HLS
block-level control (`ap_start`, or auto-restart) and carries an AXI4-Lite
control block that `sobel_fixed` does not have (`sobel_fixed` has no
programmable state at all).
