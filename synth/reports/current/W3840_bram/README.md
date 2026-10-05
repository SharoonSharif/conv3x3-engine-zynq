# conv3x3_engine, W = 3840 (4K), block-RAM line buffers (LB_BRAM = 1)

W = 3840, H = 2160, CW = 12 (line buffers 4096 x 8), default directives,
`synth/ooc_synth_param.tcl` with the optional 5th argument (generic
`LB_BRAM`), Vivado 2026.1, XC7Z020-1, 148.5 MHz:

    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 3840 2160 12 1

Reports: `conv3x3_engine_W3840_bram_{util_synth,util_impl,tim_impl,power}.rpt`
(host name and absolute paths redacted).

## Results (post-route)

| Build | LUT total | LUT logic | LUTRAM | FF | RAMB18 | RAMB36 | DSP | WNS (ns) | Power (W) total / dynamic |
|---|---|---|---|---|---|---|---|---|---|
| LB_BRAM = 0 (`../W3840/`) | 3,160 | 1,112 | 2,048 | 953 | 0 | 0 | 18 | -0.273 (fails) | 0.170 / 0.066 |
| **LB_BRAM = 1 (this directory)** | **688** | **688** | **0** | **631** | **0** | **2** | **18** | **+0.018 (met)** | 0.159 / 0.055 |

With block-RAM line buffers the engine closes 148.5 MHz at 4K (TNS 0,
0 failing endpoints) using 2 RAMB36E1 (one 4096 x 8 per buffer), 78 % fewer
LUTs and no LUTRAM. The worst path is `g_lb_bram.brow_q_reg -> LUT3 ->
pr2_reg[5]/A` (bottom-row tap select into an unregistered DSP48E1
multiplier input), 2.71 ns data path, the same path family as at W = 1920
(`../W1920_bram/`, +0.044 ns); the LUTRAM read-decode path that fails at
4K is gone.

## Line-buffer mapping (synthesis log)

    Block RAM: Final Mapping Report
    |conv3x3_engine | g_lb_bram.lb1_b_reg | 4 K x 8(READ_FIRST) | W |   | 4 K x 8(WRITE_FIRST) |   | R | Port A and B | 0 | 1 |
    |conv3x3_engine | g_lb_bram.lb2_b_reg | 4 K x 8(READ_FIRST) | W |   | 4 K x 8(WRITE_FIRST) |   | R | Port A and B | 0 | 1 |
    (RAMB36 column = 1 each -> 2 x RAMB36E1; util_synth: "RAMB36E1 | 2 | Block Memory")

No `Infeasible attribute ram_style` warning and no `Distributed RAM` entry
for the line buffers. The W = 3840 build was made with the same RTL as
`../W1920_bram/`; the simulations in `tb/logs_bram/` cover W = 160 and
W = 1920 (no 3840-wide vectors were generated).
