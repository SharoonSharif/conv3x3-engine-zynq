# conv3x3_engine, W = 1920, block-RAM line buffers (LB_BRAM = 1)

Default directives, `synth/ooc_synth_param.tcl` with the optional 5th
argument (generic `LB_BRAM`), Vivado 2026.1, XC7Z020-1, 148.5 MHz:

    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 1920 1080 11 1

Reports: `conv3x3_engine_W1920_bram_{util_synth,util_impl,tim_impl,power}.rpt`
(host name and absolute paths redacted).

## Results (post-route)

| Build | LUT total | LUT logic | LUTRAM | FF | RAMB18 | RAMB36 | DSP | WNS (ns) | Power (W) total / dynamic |
|---|---|---|---|---|---|---|---|---|---|
| LB_BRAM = 0 (`../W1920/`, baseline) | 1,916 | 892 | 1,024 | 816 | 0 | 0 | 18 | +0.076 | 0.156 / 0.053 |
| **LB_BRAM = 1 (this directory)** | **702** | **702** | **0** | **624** | **2** | **0** | **18** | **+0.044** | 0.156 / 0.053 |

Timing is met (TNS 0, 0 failing endpoints). The worst path is now
`g_lb_bram.brow_q_reg -> LUT3 -> pr1_reg[8]/A` (the bottom-row tap select
in front of a DSP48E1 whose multiplier is unregistered on the A input),
2.68 ns data path; the column-counter-to-LUTRAM-decode path of the LUTRAM
build is gone. 192 FFs disappear because the two 8-bit read registers are
absorbed into the block RAMs and the LUTRAM write-enable/decode fan-out
replication is no longer needed.

## Line-buffer mapping (synthesis log)

    Block RAM: Final Mapping Report
    |conv3x3_engine | g_lb_bram.lb1_b_reg | 2 K x 8(READ_FIRST) | W |   | 2 K x 8(WRITE_FIRST) |   | R | Port A and B | 1 | 0 |
    |conv3x3_engine | g_lb_bram.lb2_b_reg | 2 K x 8(READ_FIRST) | W |   | 2 K x 8(WRITE_FIRST) |   | R | Port A and B | 1 | 0 |
    (RAMB18 column = 1 each -> 2 x RAMB18E1; util_synth: "RAMB18E1 | 2 | Block Memory")

No `Infeasible attribute ram_style` warning and no `Distributed RAM` entry
for the line buffers.

## Design note (why the bottom-row taps are permuted)

The first LB_BRAM = 1 drafts read `lb1_rd` into the bottom tap `t2_b`
during the synthetic bottom row, i.e. `t2_b`'s input was a mux of
`s_axis_tdata` (lb1's write data) and `lb1_rd` (lb1's read data), and the
middle tap `t2_m` was an enabled register fed only by `lb1_rd`. Vivado
2026.1 then reported `[Synth 8-6849] Infeasible attribute ram_style =
"block" set for RAM ".../lb1_b_reg", trying to implement using LUTRAM` for
lb1 only (lb2 was fine), and the W = 1920 build came out at 1,180 LUT
(796 + 384 LUTRAM) / 1 RAMB18 / WNS -0.734 ns. Synthesis-only probes
isolated the trigger: a tap register whose sole data source is the
block-RAM read register (Vivado tries to absorb it as the RAM's optional
output register, cannot because `lb1_rd` has other loads, and gives up on
block RAM). The committed RTL therefore pushes the bottom row as
`t_t <- lb1`, `t_m <- lb2`, `t_b` held, and a registered flag `brow_q`
re-routes the nine taps (`q0..q8`) in the MAC stage; every tap register
now has at least two data sources and both buffers infer as RAMB18.
