# AXI4-Lite register map — `conv3x3_engine`

8-bit address bus (`s_axil_awaddr` / `s_axil_araddr`), 32-bit data. One
outstanding write. All responses are OKAY (`2'b00`). Derived from
`rtl/conv3x3_engine.v`; where this document and the RTL disagree, the RTL wins.

| Offset | Name | Access | Bits | Reset | Description |
|---|---|---|---|---|---|
| `0x00` | CTRL | RW | `[0]` EN | 1 | Stream enable, **immediate**: 0 pauses input acceptance (`s_axis_tready` low), 1 resumes |
| | | | `[1]` MODE | 0 | 0 = dual, `y = clamp((\|acc1\| + \|acc2\|) >> K)`; 1 = single-kernel |
| | | | `[2]` SIGNED | 0 | Single-kernel output: 0 = rectified, `y = clamp(\|acc1\| >> K)`; 1 = signed, `y = clamp(acc1 >> K)` (negative results clamp to 0, as for sharpening). Ignored in dual mode |
| | | | `[7:4]` K | 3 | Normalization right-shift |
| `0x04` | STATUS | RO | `[0]` BUSY | 0 | Frame in progress |
| | | | `[1]` PENDING | 0 | A config write is waiting for the next SOF commit |
| `0x08 + 4i` | K1[i], i = 0..8 | RW | `[7:0]` | Sobel Gx | Kernel 1 coefficient, signed 8-bit, row-major; reads sign-extend to 32 bits |
| `0x2C + 4i` | K2[i], i = 0..8 | RW | `[7:0]` | Sobel Gy | Kernel 2 coefficient, signed 8-bit, row-major; reads sign-extend to 32 bits |

That is 18 coefficient registers + CTRL + STATUS. Reads of any other address
return 0. In all modes `clamp` saturates to [0, 255].

Reset kernels (the engine powers up as a drop-in replacement for `sobel_fixed`):

    K1 (Gx) = [-1 0 1; -2 0 2; -1 0 1]      K2 (Gy) = [-1 -2 -1; 0 0 0; 1 2 1]
    MODE = dual, SIGNED = 0, K = 3

## Shadowing and commit

MODE, SIGNED, K and the coefficients are written to a shadow copy, and each
write sets STATUS.PENDING. The shadow copy is committed to the active
datapath registers on the next *accepted* start-of-frame beat
(`s_axis_tvalid && s_axis_tready && s_axis_tuser`), which clears PENDING. A
frame therefore never mixes two kernels, even when the writes arrive
mid-frame. EN is not shadowed. A full kernel swap is 19 writes (18
coefficients + CTRL); the testbenches measure it at 76 `aclk` cycles (see
`tb/logs/`).

## Notes

* Writes to STATUS or unmapped addresses are acknowledged and also set PENDING.
* Release v1.1.0 and earlier had no SIGNED bit, and EN = 0 was sticky
  until reset (EN was shadowed like the other fields, so input could never
  resume). Both were changed on 2026-09-30.
* A CTRL write updates all four fields at once; to change EN alone, read
  CTRL back (it returns the shadow values) and rewrite it with the other
  fields unchanged. Any write, including such an EN toggle, sets PENDING.
* Corner case: PENDING is cleared one cycle after the SOF-accept edge. A
  write whose response lands in the SOF-accept cycle or the cycle after it
  is applied at the *next* SOF (no frame is torn) but PENDING reads 0 in the
  meantime. Poll BUSY as well if a strict handshake is needed.
