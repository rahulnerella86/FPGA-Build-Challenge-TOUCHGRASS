# 03-quantized-nn-accelerator measured results

Data from `tb/vectors/layer0_*` (real INT8 PTQ vectors exported by
`quantize_model.py`) and the same NumPy reference math as
`scripts/reference_layer.py`. npar=8, klen=16, shift=7.

- Weights: 128 INT8 values, range [-127, 113] - fig_weight_hist.png
- Per-lane reference vs golden: max abs error = 0 (0 = bit-exact, which is what the RTL is held to by tb_mac_array) - fig_ref_vs_exp.png
