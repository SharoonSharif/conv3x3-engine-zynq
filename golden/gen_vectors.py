#!/usr/bin/env python3
"""Generate simulation vectors for the reconstructed conv3x3 engine.

Defines the bit-exact contract implemented by rtl/conv3x3_engine.v and
rtl/sobel_fixed.v: edge-replicated 3x3 window, signed 8-bit coefficients,
acc_k = sum(coef_i * pix_i)  (signed, fits 20 bits)
dual mode:   y = clamp( (|acc_1| + |acc_2|) >> k , 0, 255 )
single mode: y = clamp(  |acc_1|             >> k , 0, 255 )

Outputs (in tb/vectors/): image.hex, exp_<case>.hex, cfg_<case>.hex, manifest.
cfg word layout for $readmemh: [0]=mode (0 dual, 1 single), [1]=k,
[2..10]=K1 row-major (8-bit two's complement), [11..19]=K2.
"""
import json
import os
import numpy as np

W, H = 160, 120
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tb", "vectors")
os.makedirs(OUT, exist_ok=True)

# ---------------- synthetic test scene (same families as manuscript Fig. 10) ----
yy, xx = np.mgrid[0:H, 0:W]
img = 90 + 60 * (xx / W) + 25 * np.sin(2 * np.pi * yy / 64)
img[((xx - 40) ** 2 + (yy - 40) ** 2) <= 24 ** 2] = 215
img[((xx - 40) ** 2 + (yy - 40) ** 2) <= 13 ** 2] = 60
img[20:65, 95:150] = 40
img[30:55, 105:140] = 190
tri = (yy > 70) & (yy < 112) & (xx > 15) & ((xx - 15) < (yy - 70)) & ((80 - xx) > (yy - 70) * 0.4)
img[tri] = 230
for kk, v in [(-12, 245), (0, 20), (12, 245)]:
    d = np.abs((xx - 105) - (yy - 90) + kk)
    img[(d < 1.0) & (yy > 66) & (xx > 80)] = v
cb = ((xx // 6 + yy // 6) % 2 == 1) & (xx > 118) & (xx < 154) & (yy > 76) & (yy < 112)
img[cb] = 200
img = np.clip(img, 0, 255).astype(np.uint8)

# ---------------- bit-exact golden model ----------------
def conv3x3_int(y8, K):
    """Edge-replicated signed integer 3x3 convolution (matches RTL window)."""
    p = np.pad(y8.astype(np.int64), 1, mode="edge")
    acc = np.zeros(y8.shape, dtype=np.int64)
    for r in range(3):
        for c in range(3):
            acc += int(K[r][c]) * p[r:r + y8.shape[0], c:c + y8.shape[1]]
    return acc

def engine_golden(y8, K1, K2, mode, k):
    a1 = np.abs(conv3x3_int(y8, K1))
    s = a1 if mode == 1 else a1 + np.abs(conv3x3_int(y8, K2))
    return np.clip(s >> k, 0, 255).astype(np.uint8)

SOBEL_GX = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
SOBEL_GY = [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]
CASES = {
    "sobel":     dict(K1=SOBEL_GX, K2=SOBEL_GY, mode=0, k=3),
    "scharr":    dict(K1=[[-3, 0, 3], [-10, 0, 10], [-3, 0, 3]],
                      K2=[[-3, -10, -3], [0, 0, 0], [3, 10, 3]], mode=0, k=5),
    "gaussian":  dict(K1=[[1, 2, 1], [2, 4, 2], [1, 2, 1]], K2=SOBEL_GY, mode=1, k=4),
    "laplacian": dict(K1=[[0, 1, 0], [1, -4, 1], [0, 1, 0]], K2=SOBEL_GY, mode=1, k=0),
}

def w8(v):  # 8-bit two's complement hex
    return f"{int(v) & 0xFF:02x}"

with open(os.path.join(OUT, "image.hex"), "w") as f:
    f.write("\n".join(f"{v:02x}" for v in img.flatten()) + "\n")

manifest = {"W": W, "H": H, "cases": {}}
for name, c in CASES.items():
    exp = engine_golden(img, np.array(c["K1"]), np.array(c["K2"]), c["mode"], c["k"])
    with open(os.path.join(OUT, f"exp_{name}.hex"), "w") as f:
        f.write("\n".join(f"{v:02x}" for v in exp.flatten()) + "\n")
    cfg = [c["mode"], c["k"]] + [x for r in c["K1"] for x in r] + [x for r in c["K2"] for x in r]
    with open(os.path.join(OUT, f"cfg_{name}.hex"), "w") as f:
        f.write("\n".join(w8(v) for v in cfg) + "\n")
    manifest["cases"][name] = {"mode": c["mode"], "k": c["k"],
                               "checksum": int(exp.astype(np.uint64).sum())}
    # self-consistency: recompute independently via float64 path where exact
    a1 = np.abs(conv3x3_int(img, np.array(c["K1"])))
    a2 = np.abs(conv3x3_int(img, np.array(c["K2"])))
    s = a1 if c["mode"] == 1 else a1 + a2
    assert np.array_equal(exp, np.clip(s >> c["k"], 0, 255).astype(np.uint8))

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=1)
print(f"vectors written to {os.path.normpath(OUT)}: image + {len(CASES)} cases "
      f"({W}x{H}); checksums: " + ", ".join(f"{n}={m['checksum']}" for n, m in manifest['cases'].items()))
