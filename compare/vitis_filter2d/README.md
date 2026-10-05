# Baseline: AMD Vitis Vision `xf::cv::filter2D`

A like-for-like baseline for the engine: AMD's own runtime-programmable 3×3
convolution from the Vitis Vision library, with the same external interface
class. It takes 8-bit AXI4-Stream video in and out, receives its coefficients
and shift over AXI4-Lite, processes one pixel per clock, and supports
1920×1080 frames. It targets the same part, clock and Vivado flow as the
engine.

* Library: `github.com/Xilinx/Vitis_Libraries`, `vision/L1/include`, commit
  `3ab1ecd20cf338b3f8f2824fdfeee115f3398889` (2026-09-03), Apache-2.0. Not
  redistributed here.
* Tools: Vitis HLS 2026.1 (`vitis-run --mode hls`) and Vivado 2026.1.

## Files

| File | Purpose |
|---|---|
| `filter2d_top.cpp` | HLS top: `AXIvideo2xfMat` → `filter2D<XF_BORDER_CONSTANT,3,3,XF_8UC1,XF_8UC1,1080,1920,XF_NPPC1>` → `xfMat2AXIvideo`; `coef[9]`, `shift`, `rows` and `cols` on AXI4-Lite |
| `run_hls.tcl` | C synthesis for xc7z020clg400-1 at 6.734 ns |
| `tb_filter2d.cpp` | C simulation against the engine's expected outputs (`tb/vectors/exp_<case>.hex`) |
| `ooc_impl.tcl`, `ooc.xdc` | Out-of-context implementation of the HLS RTL with the engine's constraints (`default_flow` or `extratiming`) |
| `reports/` | HLS csynth report and the Vivado utilization, timing and power reports |

## Run

    set VITIS_VISION_INC=<Vitis_Libraries>/vision/L1/include
    vitis-run --mode hls --tcl run_hls.tcl
    vivado -mode batch -source ooc_impl.tcl -tclargs default_flow

C simulation. `csim_design` works too; the direct compile below avoids the
HLS makefile flow, which fails on hosts where a stray `C:\dev\null` file
exists:

    g++ -std=c++14 -O2 -I<vision/L1/include> -I<Vitis>/include filter2d_top.cpp tb_filter2d.cpp -o csim
    ./csim sharpen

## Results (2026-09-30)

**Functional equivalence.** `filter2D` output equals the engine's
single-kernel signed mode (`CTRL.MODE = 1, SIGNED = 1`) on every interior
pixel: 0 mismatches over 18,644 pixels of the 160×120 test scene for
sharpen and for Gaussian. Border pixels differ by design: `filter2D` pads
with zeros, while the engine replicates edges.

**Implementation** (xc7z020clg400-1, 148.5 MHz, W = 1920, out of context,
default directives; `reports/filter2d_top_default_flow_*`):

| | LUT (logic + mem) | FF | BRAM tiles | DSP | WNS | Power total / dyn |
|---|---|---|---|---|---|---|
| Vitis Vision `filter2D` (1 kernel) | 956 (874 + 82) | 1,392 | 1.5 (3 × RAMB18) | 9 | +0.427 ns | 0.131 / 0.028 W |
| This engine (2 kernels + magnitude) | 1,916 (892 + 1,024) | 816 | 0 | 18 | +0.076 ns | 0.156 / 0.053 W |

The HLS core keeps its line buffers in block RAM and has no dual-kernel
magnitude mode. It also restarts per frame under HLS block-level control
(`ap_start`, or auto-restart). The engine stores its line buffers in
distributed RAM and computes two kernels per pixel.

`reports/csim_console.txt` holds the C-simulation output (0 mismatches on 18,644 interior pixels for sharpen and Gaussian), added 2026-10-05.
