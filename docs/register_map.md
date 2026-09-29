# AXI4-Lite register map — `conv3x3_engine`

8-bit address bus (`s_axil_awaddr` / `s_axil_araddr`), 32-bit data. One
outstanding write. All responses are OKAY (`2'b00`). Derived from
`rtl/conv3x3_engine.v`; where this document and the RTL disagree, the RTL wins.

| Offset | Name | Access | Bits | Reset | Description |
|---|---|---|---|---|---|
| `0x00` | CTRL | RW | `[0]` EN | 1 | Stream enable (see *Known limitations*) |
| | | | `[1]` MODE | 0 | 0 = dual, `y = clamp((\|acc1\| + \|acc2\|) >> K)`; 1 = single, `y = clamp(\|acc1\| >> K)` |
| | | | `[7:4]` K | 3 | Normalization right-shift |
| `0x04` | STATUS | RO | `[0]` BUSY | 0 | Frame in progress |
| | | | `[1]` PENDING | 0 | A config write is waiting for the next SOF commit |
| `0x08 + 4i` | K1[i], i = 0..8 | RW | `[7:0]` | Sobel Gx | Kernel 1 coefficient, signed 8-bit, row-major; reads sign-extend to 32 bits |
| `0x2C + 4i` | K2[i], i = 0..8 | RW | `[7:0]` | Sobel Gy | Kernel 2 coefficient, signed 8-bit, row-major; reads sign-extend to 32 bits |

That is 18 coefficient registers + CTRL + STATUS. Reads of any other address
return 0.

Reset kernels (the engine powers up as a drop-in replacement for `sobel_fixed`):

    K1 (Gx) = [-1 0 1; -2 0 2; -1 0 1]      K2 (Gy) = [-1 -2 -1; 0 0 0; 1 2 1]
    MODE = dual, K = 3

## Shadowing and commit

Every write goes to a shadow copy and sets STATUS.PENDING. The shadow copy
is committed to the active datapath registers on the next *accepted*
start-of-frame beat (`s_axis_tvalid && s_axis_tready && s_axis_tuser`),
which clears PENDING. A frame therefore never mixes two kernels. A full kernel
swap is 19 writes (18 coefficients + CTRL); the testbench measures it at
76 `aclk` cycles (see `tb/logs/`).

## Known limitations (as-built RTL, not fixed in this release)

* **EN = 0 is sticky until reset.** `s_axis_tready` is gated by the *active*
  EN, and the active EN only updates on an accepted SOF. Once EN = 0 has
  committed, no SOF can be accepted, so a later write of EN = 1 stays pending
  forever. Only `aresetn` recovers. Do not write EN = 0 in practice.
* Writes to STATUS or unmapped addresses are acknowledged and also set PENDING.
* The comment at the top of `rtl/conv3x3_engine.v` gives the K field as
  `[6:4]`; the RTL decodes and reads back `[7:4]`. The table above follows the RTL.
