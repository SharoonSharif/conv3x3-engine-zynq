# Golden model

Python 3 + NumPy. Run from anywhere; paths are resolved relative to this file.

| File | Purpose |
|---|---|
| `gen_vectors.py` | Bit-exact reference for both cores. Edge-replicated 3x3 window, signed 8-bit coefficients, `acc = sum(coef * pix)` in int64, `y = clamp((\|acc1\| + \|acc2\|) >> k, 0, 255)` (k = 3 for Sobel). Writes `tb/vectors/` (160x120 synthetic scene, 4 kernel cases). |
| `rtl_model.py` | Transaction-level replica of the RTL's streaming push pipeline; checks it against `gen_vectors.engine_golden` on the scene, 24 random cases and degenerate heights. |

    python golden/gen_vectors.py   # regenerates tb/vectors/ byte-identically
    python golden/rtl_model.py     # prints PASS per case

**Precision:** this model is fixed-point (integer) only. There is **no**
double-precision edge-magnitude model in this repository; the float64
comparison reported in the manuscript cannot be regenerated from here.
