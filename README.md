# conv3x3-engine-zynq

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23047577.svg)](https://doi.org/10.5281/zenodo.23047577)

A runtime-programmable 3x3 convolution engine and a fixed Sobel reference
core for AMD/Xilinx Zynq-7020, with testbenches, a fixed-point reference
model, Vivado scripts and reports (1920- and 3840-pixel lines, distributed-
and block-RAM line buffers), AMD Vitis Vision `filter2D` and `Sobel`
baselines, the BSDS500 evaluation with its k/kernel sensitivity study, and
the DDR feasibility-model script behind the TCAS-II brief.

> **Read before citing any number from this repository.**
>
> 1. **This RTL is a reconstruction.** The original design sources and Vivado
>    projects were lost. The files in `rtl/` were written in July 2026 from
>    the manuscript's own design description and revised on 2026-09-30
>    (signed single-kernel mode, immediate EN, one timing register) and
>    2026-10-05 (`LB_BRAM` parameter). They are not recovered original code.
> 2. **No board-level runtime campaigns were executed.** Every hardware
>    number here is post-route, out-of-context, from Vivado; power is a
>    vectorless estimate. Nothing was run on a Zynq board.
> 3. **The BSDS500 evaluation was re-implemented** on 2026-09-30 (`eval/`);
>    the original scripts were lost, and the numbers from earlier drafts are
>    superseded.

## Target and tools

| | |
|---|---|
| Device | XC7Z020-1 (`xc7z020clg400-1`) |
| Tools | Vivado 2026.1 (build 6511674), Vitis HLS 2026.1; free Standard edition |
| Flow | Out-of-context: `synth_design -mode out_of_context`, `opt_design`, `place_design`, `phys_opt_design`, `route_design`, **default directives** (`synth/ooc_synth.tcl`, `synth/ooc_synth_param.tcl`). `synth/ooc_synth_strategy.tcl` runs named directive sets |
| Clock | `aclk`, 6.734 ns period (148.5 MHz); 2.0 ns input/output delays (`synth/ooc.xdc`) |
| Line width | Parameter `W`. RTL default 160 (H = 120, CW = 9). 1920-pixel builds use W = 1920, H = 1080, CW = 11 (buffers `2**CW` = 2048 deep); 3840-pixel builds use CW = 12 (4096 deep) |
| Line-buffer style | Engine parameter `LB_BRAM`: 0 (default) distributed RAM, 1 block RAM. `sobel_fixed` is distributed RAM only |
| Simulator | Vivado xsim 2026.1 (Icarus Verilog also supported) |

## Layout

    rtl/conv3x3_engine.v    programmable engine: AXI4-Stream in/out + AXI4-Lite
                            (CTRL, STATUS, 18 signed 8-bit coefficients),
                            18 DSP48E1, two line buffers (LUTRAM or BRAM)
    rtl/sobel_fixed.v       hardwired Sobel (|Gx|+|Gy|)>>3, same streaming
                            front end, no AXI4-Lite
    tb/                     self-checking testbenches (random and adversarial
                            backpressure, full-rate input, mid-frame
                            reprogramming, EN pause, N-frame runs, any W/H),
                            vectors, run scripts, logs            -> tb/README.md
    golden/                 fixed-point (integer) reference model -> golden/README.md
    compare/vitis_filter2d/ Vitis Vision filter2D baseline (HLS)  -> its README.md
    compare/vitis_sobel/    Vitis Vision Sobel baseline (HLS)     -> its README.md
    model/ddr_model.py      DDR feasibility model: reproduces Tables I and II
    eval/                   BSDS500 evaluation + k/kernel sensitivity -> eval/README.md
    synth/                  Vivado Tcl + XDC + reports (evidence, not regenerated)
    docs/register_map.md    AXI4-Lite register map
    docs/reproduce.md       step-by-step reproduction with expected values

There are no separate `line_buffer.v` or `axi_lite_regs.v` modules. The line
buffers (`lb1`, `lb2`) and the AXI4-Lite register file are inside
`conv3x3_engine.v`, and the line buffers are inside `sobel_fixed.v`.

## Results

Post-route, out-of-context, default directives, from
`synth/reports/current/` and `compare/*/reports/`. Power figures are Vivado
vectorless estimates (confidence level "Medium"). "mem" = LUTs used as
distributed RAM or shift registers.

**Brief, Table IV: W = 1920 (H = 1080)**

| | LUT (logic + mem) | FF | BRAM tiles | DSP | WNS @ 6.734 ns | Power total / dyn |
|---|---|---|---|---|---|---|
| Sobel (fixed) | 1,532 (508 + 1,024) | 322 | 0 | 0 | +0.367 ns | 0.118 / 0.015 W |
| Programmable engine, `LB_BRAM = 0` | 1,916 (892 + 1,024) | 816 | 0 | 18 | +0.076 ns | 0.156 / 0.053 W |
| Programmable engine, `LB_BRAM = 1` | 702 (702 + 0) | 624 | 1 (2 x RAMB18) | 18 | +0.044 ns | 0.156 / 0.053 W |
| Vitis Vision `filter2D`, 1 kernel | 956 (874 + 82) | 1,392 | 1.5 (3 x RAMB18) | 9 | +0.427 ns | 0.131 / 0.028 W |
| Vitis Vision `Sobel` + `(\|Gx\|+\|Gy\|)>>3` | 845 (842 + 3) | 1,163 | 1.5 (3 x RAMB18) | 0 | +0.926 ns | 0.124 / 0.021 W |

**W = 3840 (4K, H = 2160, CW = 12)**

| | LUT (logic + mem) | FF | BRAM tiles | DSP | WNS @ 6.734 ns |
|---|---|---|---|---|---|
| Sobel (fixed), distributed RAM | 2,742 (694 + 2,048) | 420 | 0 | 0 | **−0.150 ns (fails)** |
| Engine, `LB_BRAM = 0` | 3,160 (1,112 + 2,048) | 953 | 0 | 18 | **−0.273 ns (fails)** |
| Engine, `LB_BRAM = 1` | 688 (688 + 0) | 631 | 2 (2 x RAMB36) | 18 | +0.018 ns |

At 4K the distributed-RAM read decode (4096-deep LUTRAM through two MUXF7
levels) is the critical path in both cores; the block-RAM engine closes.

**W = 160 (RTL default width)**: Sobel 575 LUT (319 + 256), 237 FF, +0.629 ns;
engine 953 LUT (697 + 256), 636 FF, 18 DSP, +0.064 ns.

**Latency and throughput (simulation):** first accepted input beat to first
output beat is W + 6 cycles (1,926 cycles = 12.97 µs at 1080p and 148.5 MHz;
166 cycles at W = 160); W pixels per W + 1 cycles within a frame plus a
(W + 1)-cycle bottom-border flush, i.e. 2,076,604 cycles per 1920x1080 frame
(1080p60 frame period: 2,475,000 cycles). The Vitis Vision Sobel kernel
sustains 0.993 pixel/clock (1,934 cycles per 1920-pixel row).

### Provenance of the reports

* `synth/reports/current/W1920/`, `W160/` — reports for the RTL in this
  commit with `LB_BRAM = 0`. `conv3x3_engine_W*` from 2026-09-30;
  `sobel_fixed_W1920_*` from 2026-09-29; `sobel_fixed_*` (W = 160) from
  2026-07-09 (`sobel_fixed.v` is unchanged since July).
* `synth/reports/current/W1920_gate/` — the engine rebuilt on 2026-10-05
  after the `LB_BRAM` parameter was added: line-identical to `W1920/`
  except the date, which shows the `LB_BRAM = 0` netlist is unchanged.
* `synth/reports/current/W1920_bram/`, `W3840/`, `W3840_bram/` — 2026-10-05.
* `synth/reports/history/` — engine reports for the RTL of release v1.1.0
  and earlier. At W = 1920 that RTL failed timing with default directives
  (−0.086 ns) and closed only with the ExtraTimingOpt directive set
  (+0.066 ns); registering the left-border flag `lrep` removed the critical
  compare, so the current RTL closes with default directives.
* `compare/vitis_filter2d/reports/`, `compare/vitis_sobel/reports/` — Vitis
  HLS csynth reports and Vivado implementation reports for the baselines.
* The build host name is redacted (`<redacted>`) in every report header and
  log. Nothing else has been edited.

## Verification (55 xsim runs, all TB PASS; logs in `tb/logs*/`)

| Suite | Runs | Pixels | Result |
|---|---|---|---|
| `tb_engine.v`: 6 kernels (Sobel, Scharr k=5, Prewitt k=3, Gaussian single k=4, Laplacian single k=0, sharpen single **signed** k=0), random gaps + backpressure, swap between frames, 160x120 | 6 | 0.23 M | bit-exact |
| `tb_sobel_fixed.v`, 160x120 | 1 | 0.02 M | bit-exact |
| `tb_engine_ext.v`: 6 kernels written **mid-frame**; full-rate input; **EN pause**; 160x120, 1920x16, 1920x1080 | 18 | 5.0 M | bit-exact; frame in flight unaffected; no input accepted while EN = 0 |
| `tb_engine_ext.v` **long runs** (`tb/logs_long/`): 60 x 1920x16 and 120 x 160x120 frames with the next kernel written at a random row of every frame under **adversarial** stalls (TREADY low for 1,000–2,513 cycles from the SOF accept cycle and at the first EOL; 500–1,499-cycle input gaps); 4 x 1920x1080 at full rate; 3 x 1920x1080 adversarial; 2 x 1920x1080 with and without a swap | 6 | 27.0 M | bit-exact, 184 swaps, 0 TUSER/TLAST/STATUS errors; a swap adds no bubble (2,076,604 cycles/frame either way) |
| The engine suites above repeated with `LB_BRAM = 1` (`tb/logs_bram/`) | 24 | 5.2 M | bit-exact; identical cycle counts |
| `compare/vitis_filter2d` and `compare/vitis_sobel` C simulation vs the engine's signed single-kernel output / the fixed core | 2 | — | 0 mismatches on all interior pixels (borders differ by design: zero padding vs edge replication) |

A kernel swap (19 AXI4-Lite writes) takes 76 clock cycles in every run.

## Reproducing

Full details and expected values: `docs/reproduce.md`. From the repository
root, with Vivado 2026.1's `bin` directory on PATH:

    # 1. Reference model self-check and vector regeneration (Python 3 + NumPy)
    python golden/rtl_model.py
    python golden/gen_vectors.py                 # tb/vectors/
    python golden/gen_vectors_wide.py 1920 16    # tb/vectors_w1920_h16/
    python golden/gen_vectors_wide.py 1920 1080  # tb/vectors_w1920_h1080/ (not archived, ~30 MB)

    # 2. RTL simulation — every run must print "TB PASS"
    tb\run_xsim.bat          # original testbenches, 160x120, 6 kernels
    tb\run_xsim_ext.bat      # mid-frame, full rate, EN pause; 160x120 and 1920x16
    tb\run_xsim_1080p.bat    # one 1920x1080 frame pair
    tb\run_xsim_long.bat     # long and adversarial runs (a-f)
    tb\run_xsim_bram.bat     # the engine suites with LB_BRAM = 1

    # 3. Implementation, W = 1920 (Table IV), default directives
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs sobel_fixed    1920 1080 11
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 1920 1080 11
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 1920 1080 11 1   # LB_BRAM = 1

    # 4. W = 3840 (4K) and W = 160
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 3840 2160 12
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 3840 2160 12 1
    vivado -mode batch -source synth/ooc_synth.tcl -tclargs conv3x3_engine

    # 5. Vitis Vision baselines: compare/vitis_filter2d/README.md, compare/vitis_sobel/README.md

Each implementation run takes a few minutes (longer at 4K). Compare against
`synth/reports/current/`.

## BSDS500 evaluation protocol

Script and results: `eval/` (see `eval/README.md`; BSDS500 itself is
downloaded separately).

* Data: all **200 images of the BSDS500 test split**, with the dataset's
  human ground truth (a 20-image subset option is also provided).
* The fixed-point pipeline (`>> k` normalization, bit-exact to the RTL) is
  compared with a float64 reference without truncation or saturation.
* Edges are thinned by four-direction non-maximum suppression, normalized
  per image, and swept over **99 thresholds**. ODS and OIS F-measures and
  Pratt's figure of merit are reported.
* **Relaxed matching:** a detected edge pixel counts as correct if it lies
  within **0.0075 of the image diagonal** of any ground-truth edge pixel,
  **without a one-to-one correspondence constraint**. This is more lenient
  than the standard BSDS benchmark, which enforces one-to-one matching.

**These are internal-comparison numbers (fixed point vs. float64 under one
protocol), not BSDS500 leaderboard results, and they are not comparable
with published benchmark scores.**

| 200 test images, Sobel k = 3 | ODS F (P, R) | OIS F | Pratt FOM |
|---|---|---|---|
| Fixed point | 0.589 (0.476, 0.775) | 0.599 | 0.304 ± 0.108 |
| Float64 | 0.589 (0.480, 0.761) | 0.600 | 0.291 ± 0.106 |

**Sensitivity** (`eval/results/sensitivity.md`; Sobel k = 0–5, Prewitt
k = 2–3, Scharr k = 4–5): the float64 scores are exactly k-invariant; at each
kernel's natural scale the fixed-minus-float64 ODS gap is ≤ 0.0006 and the
kernel family moves ODS by ≤ 0.006 (Prewitt 0.592, Sobel 0.589, Scharr
0.586). Shifts below the natural scale clip up to 9.1 % of magnitudes
(Sobel k = 0) and *raise* the fixed scores (ODS 0.617), an artifact of
saturated plateaus passing NMS as bands that the relaxed matching accepts;
it is not a quality gain.

## Scope and limitations

* **No hardware execution.** No bitstream, board design or runtime software
  is included, and none of the runtime board-level campaigns were executed.
  Throughput, latency on hardware, DDR bandwidth and real power are not
  measured anywhere here; the latency and throughput above are simulation.
* **The DDR bandwidth-feasibility model** is included as equations only
  (`model/ddr_model.py` reproduces the brief's Tables I and II); its inputs
  from the conference system are not re-measured.
* **Power is a vectorless estimate**, not a measurement.
* **4K needs block-RAM line buffers** (`LB_BRAM = 1`); the distributed-RAM
  builds fail 148.5 MHz at W = 3840. No 3840-wide simulation vectors exist;
  the 4K builds are synthesis/implementation evidence only.
* The Vitis Vision baselines zero-pad borders and run under HLS block-level
  control; the RTL cores replicate edges and free-run. See the `compare/*`
  READMEs.

## Citation

Cite the archive as doi:[10.5281/zenodo.23047577](https://doi.org/10.5281/zenodo.23047577)
(concept DOI; resolves to the latest version). See `CITATION.cff`.

## License

MIT, see `LICENSE`.
