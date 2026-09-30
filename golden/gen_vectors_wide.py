#!/usr/bin/env python3
"""Generate vectors for tb/tb_engine_ext.v at an arbitrary frame size.

Uses the same bit-exact contract as gen_vectors.py (engine_golden). The image
is uniform random bytes (seeded) so that every line-buffer address, including
columns >= 1024 at W = 1920, carries data-dependent values.

    python golden/gen_vectors_wide.py 1920 16      # -> tb/vectors_w1920_h16/
    python golden/gen_vectors_wide.py 1920 1080    # -> tb/vectors_w1920_h1080/

Output: image.hex, exp_<case>.hex, cfg_<case>.hex (same cfg layout as
gen_vectors.py), manifest.json.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_vectors import engine_golden, CASES, w8  # noqa: E402

W = int(sys.argv[1]) if len(sys.argv) > 1 else 1920
H = int(sys.argv[2]) if len(sys.argv) > 2 else 16
SEED = 20260930

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tb",
                   f"vectors_w{W}_h{H}")
os.makedirs(OUT, exist_ok=True)

img = np.random.default_rng(SEED).integers(0, 256, size=(H, W), dtype=np.uint8)
with open(os.path.join(OUT, "image.hex"), "w", newline="\n") as f:
    f.write("\n".join(f"{v:02x}" for v in img.ravel()) + "\n")

manifest = {"W": W, "H": H, "seed": SEED, "cases": {}}
for name, c in CASES.items():
    sg = c.get("signed", 0)
    exp = engine_golden(img, np.array(c["K1"]), np.array(c["K2"]), c["mode"], c["k"], sg)
    with open(os.path.join(OUT, f"exp_{name}.hex"), "w", newline="\n") as f:
        f.write("\n".join(f"{v:02x}" for v in exp.ravel()) + "\n")
    cfg = [c["mode"] | (sg << 1), c["k"]] + [x for r in c["K1"] for x in r] \
                              + [x for r in c["K2"] for x in r]
    with open(os.path.join(OUT, f"cfg_{name}.hex"), "w", newline="\n") as f:
        f.write("\n".join(w8(v) for v in cfg) + "\n")
    manifest["cases"][name] = {"mode": c["mode"], "k": c["k"],
                               "checksum": int(exp.astype(np.uint64).sum())}
    if sg:
        manifest["cases"][name]["signed"] = 1
with open(os.path.join(OUT, "manifest.json"), "w", newline="\n") as f:
    json.dump(manifest, f, indent=1)
print(f"vectors written to {os.path.normpath(OUT)} ({W}x{H}, seed {SEED})")
