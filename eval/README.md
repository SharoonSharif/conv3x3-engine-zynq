# BSDS500 evaluation — NOT INCLUDED

The edge-quality numbers in the manuscript (ODS/OIS F-measure and Pratt's
figure of merit, fixed-point vs. float64) were **not** produced by code in this
repository, and that evaluation code could not be located when this release
was assembled. Nothing here reproduces them.

What is missing:

* the evaluation pipeline (non-maximum suppression, 99-threshold sweep,
  ODS/OIS aggregation, Pratt FOM),
* a float64 reference edge-magnitude model (`golden/` is integer/fixed-point
  only; see `golden/README.md`),
* the 20-image BSDS500 test subset list and ground-truth handling.

The protocol the manuscript describes, for reference, is in the top-level
`README.md` under *BSDS500 evaluation protocol*. If the code is recovered it
belongs in this directory.
