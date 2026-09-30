#!/usr/bin/env python3
"""Regenerate the brief's BSDS500 figure: test image 3063, (a) Rec. 601
luminance and (b) the fixed-point Sobel magnitude clamp((|Gx|+|Gy|) >> 3),
computed by the bit-exact integer reference model.

    python eval/make_fig10.py <BSDS500 data dir> [out.png]
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bsds_eval import luminance, gradients, magnitude  # noqa: E402

data = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", "fig10.png")
y = luminance(os.path.join(data, "images", "test", "3063.jpg"))
gx, gy = gradients(y)
e = magnitude(gx, gy, "fixed")

plt.rcParams.update({"font.family": "serif", "font.size": 11})
fig, ax = plt.subplots(1, 2, figsize=(7.0, 2.55))
for a, img, lab in ((ax[0], y, "(a)"), (ax[1], e, "(b)")):
    a.imshow(img, cmap="gray", vmin=0, vmax=255, interpolation="nearest")
    a.set_xticks([]); a.set_yticks([])
    a.set_xlabel(lab)
fig.tight_layout(pad=0.3, w_pad=0.6)
os.makedirs(os.path.dirname(out), exist_ok=True)
fig.savefig(out, dpi=250)
print("wrote", out, "| magnitude max", int(e.max()), "| saturated px", int((e >= 255).sum()))
