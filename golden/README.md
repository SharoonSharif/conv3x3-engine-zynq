# Reference model

Python 3 + NumPy. Run from anywhere; paths are resolved relative to this file.

| File | Purpose |
|---|---|
| `gen_vectors.py` | Bit-exact reference for both cores: edge-replicated 3x3 window, signed 8-bit coefficients, `acc = sum(coef * pix)` in int64. Dual: `clamp((\|acc1\| + \|acc2\|) >> k)`; single: `clamp(\|acc1\| >> k)`, or `clamp(acc1 >> k)` with CTRL.SIGNED; saturation to [0, 255]. Writes `tb/vectors/` (160x120 synthetic scene, 6 kernel cases). |
| `gen_vectors_wide.py` | Same contract, seeded random image at any size (e.g. 1920x16, 1920x1080). |
| `rtl_model.py` | Transaction-level replica of the RTL's streaming push pipeline. Checks it against `gen_vectors.engine_golden` on the scene (6 cases), 24 random cases, degenerate heights and 12 random signed-mode cases. |

    python golden/gen_vectors.py   # regenerates tb/vectors/
    python golden/rtl_model.py     # prints PASS per case

**Precision:** this model is fixed-point (integer) and is what the RTL is
verified against. The float64 edge-magnitude reference used for the BSDS500
comparison lives in `eval/bsds_eval.py`.
