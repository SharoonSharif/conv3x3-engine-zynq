# conv3x3-engine-zynq

A runtime-programmable 3x3 convolution engine and a fixed Sobel reference
core for AMD/Xilinx Zynq-7020, with their testbenches, fixed-point golden
model, Vivado scripts and the implementation reports behind the manuscript's
resource/timing/power table.

> **Read before citing any number from this repository.**
>
> 1. **This RTL is a reconstruction.** The original design sources and Vivado
>    projects were lost. The files in `rtl/` were written in July 2026 from
>    the manuscript's own design description (engine microarchitecture,
>    register map, fixed Sobel core). They are not recovered original code.
> 2. **The published hardware numbers match a 160-pixel line-buffer build,
>    not 1920.** At a line width of 1920 the engine misses the 148.5 MHz
>    constraint by 86 ps. Both builds are included (see *Results*).
> 3. **The BSDS500 evaluation code is not included** and could not be
>    located; those numbers cannot be reproduced from here (see `eval/`).
> 4. **No board-level runtime campaigns were executed.** Every hardware
>    number here is post-route, out-of-context, from Vivado. Nothing was run
>    on a Zynq board.

## Target and tools

| | |
|---|---|
| Device | XC7Z020-1 (`xc7z020clg400-1`) |
| Tool | Vivado 2026.1 (build 6511674), free Standard edition |
| Flow | Out-of-context: `synth_design -mode out_of_context`, `opt_design`, `place_design`, `phys_opt_design`, `route_design` (default directives) |
| Clock | `aclk`, 6.734 ns period (148.5 MHz); 2.0 ns input/output delays (`synth/ooc.xdc`) |
| Line width | Parameter `W`. RTL default **160** (H = 120, CW = 9). The 1920 build uses W = 1920, H = 1080, CW = 11 (line buffers are `2**CW` deep, so 2048 x 8 each) |
| Simulator | Vivado xsim 2026.1 (Icarus Verilog also supported) |

## Layout

    rtl/conv3x3_engine.v    programmable engine: AXI4-Stream in/out + AXI4-Lite
                            (CTRL, STATUS, 18 signed 8-bit coefficients),
                            18 DSP48E1, two distributed-RAM line buffers
    rtl/sobel_fixed.v       hardwired Sobel (|Gx|+|Gy|)>>3, same streaming
                            front end, no AXI4-Lite
    tb/                     self-checking testbenches with random backpressure,
                            vectors, run script, logs            -> tb/README.md
    golden/                 fixed-point reference model           -> golden/README.md
    eval/                   BSDS500 evaluation: NOT INCLUDED       -> eval/README.md
    synth/                  Vivado Tcl + XDC + reports (evidence, not regenerated)
    docs/register_map.md    AXI4-Lite register map and known limitations
    docs/reproduce.md       step-by-step reproduction with expected values

There are no separate `line_buffer.v` or `axi_lite_regs.v` modules. The line
buffers (`lb1`, `lb2`) and the AXI4-Lite register file are inside
`conv3x3_engine.v`, and the line buffers are inside `sobel_fixed.v`.

## Results

All values are post-route, out-of-context, from the reports under
`synth/reports/`. Power figures are Vivado vectorless estimates (default
switching activity, confidence level "Medium").

| | Sobel, W=160 | Engine, W=160 | Sobel, W=1920 | Engine, W=1920 |
|---|---|---|---|---|
| Total LUTs | 575 | 931 | 1,532 | 1,930 |
| &nbsp;&nbsp;logic | 319 | 675 | 508 | 906 |
| &nbsp;&nbsp;memory (distributed RAM) | 256 | 256 | 1,024 | 1,024 |
| &nbsp;&nbsp;shift register | 0 | 0 | 0 | 0 |
| Flip-flops | 237 | 622 | 322 | 845 |
| Block RAM tiles | 0 | 0 | 0 | 0 |
| DSP48E1 | 0 | 18 | 0 | 18 |
| WNS @ 6.734 ns | +0.629 ns | +0.025 ns | +0.367 ns | **−0.086 ns (fails, 3 endpoints)** |
| Total / dynamic power | 0.114 / 0.012 W | 0.164 / 0.061 W | 0.118 / 0.015 W | 0.157 / 0.054 W |
| Reports | `W160_published/` | `W160_published/` | `W1920/` | `W1920/` |

The W = 1920 engine's failing paths all run from a line-buffer read
(`RAMD64E` → `MUXF7`/`MUXF8`) into the multiply stage.

### Relation to the manuscript's table

The W = 160 columns reproduce the manuscript's flip-flop, BRAM, DSP, WNS and
power figures exactly. The manuscript's LUT figures do **not** match any
report:

| | Manuscript | Reports (W = 160) |
|---|---|---|
| Fixed Sobel | 575 logic + 595 memory = 1,170 | 575 **total** = 319 logic + 256 memory |
| Engine | 931 logic + 595 memory = 1,526 | 931 **total** = 675 logic + 256 memory |

The manuscript's "logic" values equal the reports' *total* LUTs, which
already include the memory LUTs, and the value 595 appears in no report or
log. The manuscript also states 1920-pixel line buffers, but these reports
were built at W = 160.

### Provenance of the reports

* `synth/reports/W160_published/` — the July 2026 reports the manuscript
  table was drawn from: `sobel_fixed_*` (2026-07-09 10:23) and
  `conv3x3_engine_*` (2026-07-09 10:44). `rtl/` is byte-identical to the
  sources of both runs.
* `synth/reports/W1920/` — produced on 2026-09-29 with
  `synth/ooc_synth_param.tcl` from the same `rtl/`.
* A W = 160 rerun on 2026-09-29 with `ooc_synth_param.tcl` produced reports
  identical to `W160_published/` apart from the date and file name.
* The build host name is redacted (`<redacted>`) in every report header and
  log. Nothing else has been edited.

## Reproducing

Full details and expected values: `docs/reproduce.md`. From the repository
root, with Vivado 2026.1's `bin` directory on PATH:

    # 1. Golden model self-check and vector regeneration (Python 3 + NumPy)
    python golden/rtl_model.py
    python golden/gen_vectors.py          # tb/vectors/ regenerates byte-identically

    # 2. RTL simulation — every run must print "TB PASS"
    tb\run_xsim.bat                       # (see tb/README.md for Icarus)

    # 3. Implementation, W = 160 (the manuscript table)
    vivado -mode batch -source synth/ooc_synth.tcl -tclargs sobel_fixed
    vivado -mode batch -source synth/ooc_synth.tcl -tclargs conv3x3_engine
    #    -> <top>_util_impl.rpt, <top>_tim_impl.rpt, <top>_power.rpt

    # 4. Implementation, W = 1920
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs sobel_fixed    1920 1080 11
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 1920 1080 11
    #    -> <top>_W1920_{util_synth,util_impl,tim_impl,power}.rpt

Each implementation run takes a few minutes. Compare against
`synth/reports/`. Resource counts come from `report_utilization`: the
hierarchical `*_util_impl.rpt` gives Total/Logic/LUTRAM/FF/DSP, and
`*_util_synth.rpt` gives the LUT-as-Logic / LUT-as-Memory breakdown.

## BSDS500 evaluation protocol

**The code for this evaluation is not in this repository** (see `eval/`).
The manuscript describes the protocol as follows:

* Data: a **20-image subset** of the BSDS500 test set, with the dataset's
  human ground truth.
* The fixed-point pipeline (`>> 3` normalization) is compared with a
  float64 reference.
* Edges are thinned by non-maximum suppression and swept over **99
  thresholds**. ODS and OIS F-measures and Pratt's figure of merit are
  reported.
* **Relaxed matching:** a detected edge pixel counts as correct if it lies
  within **0.0075 of the image diagonal** of any ground-truth edge pixel,
  **without a one-to-one correspondence constraint**. This is more lenient
  than the standard BSDS benchmark, which enforces one-to-one matching.

**These are internal-comparison numbers (fixed point vs. float64 under one
protocol), not BSDS500 leaderboard results, and they are not comparable
with published benchmark scores.** The values reported in the manuscript
are ODS F = 0.619 (P = 0.508, R = 0.793), OIS F = 0.646, Pratt
0.310 ± 0.111 for fixed point, and 0.618 / 0.648 / 0.309 ± 0.110 for
float64. They cannot be regenerated from this repository.

## Scope and limitations

* **No hardware execution.** No bitstream, board design or runtime software
  is included, and none of the runtime board-level campaigns were executed.
  Throughput, latency on hardware, DDR bandwidth and real power are not
  measured anywhere here.
* **The DDR bandwidth-feasibility model is not included.**
* **Simulation covers W = 160, H = 120 only.** The W = 1920 build has been
  implemented but not simulated.
* **Power is a vectorless estimate**, not a measurement.
* **The W = 1920 engine does not meet 148.5 MHz** with the default
  implementation flow.
* **EN = 0 is sticky until reset** (see `docs/register_map.md`).

## Citation

See `CITATION.cff`.

## License

MIT, see `LICENSE`.
