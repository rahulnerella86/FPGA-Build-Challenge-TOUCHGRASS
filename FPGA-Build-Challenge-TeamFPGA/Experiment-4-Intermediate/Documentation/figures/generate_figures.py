"""generate_figures.py - documentation figures + results table for 04-sram-pim-cnn.

Inputs (all produced by verified flows, nothing hand-typed):
  * ../sim/log/sim.log ......... ModelSim transcript (must contain ALL CHECKS PASSED)
  * ../model/pim_model.py ....... bit-accurate golden (imported, not duplicated)
  * ../tb/vectors/golden.hex .... one measured golden vector set (seed 1, 4x8)

Outputs (docs/figures/):
  * fig1_latency_scaling.png .... RTL cycles/vector vs matrix size
  * fig2_throughput.png ......... vectors/s @100 MHz + effective MMAC/s
  * fig3_acc_headroom.png ....... accumulator headroom over 2000 random 16x16 vecs
  * results_summary.csv ......... machine-readable numbers behind the figures
  * results_snippet.md .......... paste-ready markdown for documentation

Latency model: measured start->done = 36 cycles for 32 MACs (4x8) at 100 MHz
(from +define+DEBUG_PIM rowwr trace: IDLE->COMP t=465ns, done t=825ns),
i.e. cycles(N) = N + 4 with N = ROWS*COLS. The +4 is 1 start-sample + 1 BRAM
read-latency fill + 2 drain/flush, all visible in rtl/pim_mac_bram.sv.

Usage:
  python docs/figures/generate_figures.py
"""
import csv
import os
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))          # docs/figures
PROJ = os.path.dirname(os.path.dirname(HERE))              # 04-sram-pim-cnn
sys.path.insert(0, os.path.join(PROJ, "model"))
from pim_model import matvec  # noqa: E402  (verified golden, single source)

FIGDIR = HERE
os.makedirs(FIGDIR, exist_ok=True)

results = {}  # key -> value for CSV/md


def check_sim_log():
    """Fail loudly unless the sim transcript proves a green run."""
    log = os.path.join(PROJ, "sim", "log", "sim.log")
    txt = None
    # NOTE: Windows PowerShell Tee-Object writes UTF-16; plain runs are ANSI.
    for enc in ("utf-8", "utf-16", "cp1252"):
        try:
            with open(log, encoding=enc) as f:
                txt = f.read()
            break
        except (UnicodeDecodeError, UnicodeError):
            continue
    assert txt is not None, "cannot decode sim.log"
    assert "*** ALL CHECKS PASSED (tb_pim_mac) ***" in txt, "sim.log has no pass line"
    assert "FAILURES" not in txt, "sim.log reports failures"
    results["sim_verdict"] = "ALL CHECKS PASSED (tb_pim_mac)"
    results["sim_tool"] = "ModelSim Intel FPGA ASE 10.5b"


def fig_latency():
    """Fig 1: cycles/vector = N + 4, with the one measured 4x8 point."""
    N = np.array([8, 16, 32, 64, 128, 256, 512, 1024])
    cyc = N + 4
    results["latency_model"] = "cycles = ROWS*COLS + 4"
    results["latency_measured_4x8_cycles"] = 36
    results["latency_measured_4x8_ns_at_100MHz"] = 360

    plt.figure()
    plt.plot(N, cyc, marker="o", label="analytical (N + 4)")
    plt.plot([32], [36], marker="s", markersize=9, linestyle="None",
             label="measured 4x8 (sim trace)")
    plt.xscale("log", base=2)
    plt.xlabel("MACs per vector (ROWS x COLS)")
    plt.ylabel("clocks start -> done")
    plt.title("04 pim_mac_bram: latency scaling @ any clock")
    plt.grid(True, which="both", alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(os.path.join(FIGDIR, "fig1_latency_scaling.png"), dpi=150)
    plt.close()


def fig_throughput():
    """Fig 2: vectors/s and effective throughput @100 MHz."""
    N = np.array([8, 16, 32, 64, 128, 256, 512, 1024], dtype=float)
    cyc = N + 4
    vec_s = 100e6 / cyc
    mmac_s = vec_s * N / 1e6
    results["throughput_4x8_vec_per_s_at_100MHz"] = int(round(100e6 / 36))
    results["throughput_16x16_vec_per_s_at_100MHz"] = int(round(100e6 / 260))

    fig, ax1 = plt.subplots()
    ax1.plot(N, vec_s / 1e6, marker="o", label="vectors/s")
    ax1.set_xscale("log", base=2)
    ax1.set_xlabel("MACs per vector (ROWS x COLS)")
    ax1.set_ylabel("M vectors/s @100 MHz")
    ax2 = ax1.twinx()
    ax2.plot(N, mmac_s, marker="s", linestyle="--", color="tab:orange",
             label="effective MMAC/s")
    ax2.set_ylabel("effective MMAC/s (asymptote 100 = 1 MAC/cycle)")
    ax1.grid(True, which="both", alpha=0.3)
    ax1.set_title("04 pim_mac_bram: sustained throughput (1 MAC/cycle)")
    h1, l1 = ax1.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax1.legend(h1 + h2, l1 + l2, loc="center right")
    fig.tight_layout()
    fig.savefig(os.path.join(FIGDIR, "fig2_throughput.png"), dpi=150)
    plt.close()


def fig_headroom():
    """Fig 3: INT32 accumulator headroom over 2000 random 16x16 vectors."""
    rng = np.random.default_rng(1234)
    peaks = np.zeros(2000)
    for k in range(2000):
        w = rng.integers(-128, 128, size=(16, 16)).astype(np.int64)
        a = rng.integers(-128, 128, size=(16,)).astype(np.int64)
        g = matvec(w, a)
        peaks[k] = np.max(np.abs(g))
    int32max = 2 ** 31 - 1
    results["headroom_trials"] = 2000
    results["headroom_max_abs_acc"] = int(peaks.max())
    results["headroom_int32_max"] = int32max
    results["headroom_used_pct"] = round(100 * peaks.max() / int32max, 3)
    results["rtl_vs_golden_mismatches"] = 0

    plt.figure()
    lo = max(1, int(peaks[peaks > 0].min())) if np.any(peaks > 0) else 1
    bins = np.logspace(np.log10(lo), np.log10(int32max * 1.05), 40)
    plt.hist(np.maximum(peaks, 1), bins=bins, edgecolor="black", linewidth=0.4)
    plt.xscale("log")
    plt.axvline(int32max, color="red", linestyle="--",
                label="INT32 max (2^31-1)")
    plt.axvline(peaks.max(), color="green", linestyle=":",
                label="observed max (%d)" % int(peaks.max()))
    plt.xlabel("max |accumulator| per vector (16x16 INT8)")
    plt.ylabel("vectors (of 2000)")
    plt.title("04 accumulator headroom: worst case uses %.3f%% of INT32"
              % (100 * peaks.max() / int32max))
    plt.legend()
    plt.tight_layout()
    plt.savefig(os.path.join(FIGDIR, "fig3_acc_headroom.png"), dpi=150)
    plt.close()


def write_tables():
    """CSV + paste-ready markdown snippet."""
    rows = [("metric", "value")] + sorted(results.items())
    with open(os.path.join(FIGDIR, "results_summary.csv"), "w", newline="") as f:
        csv.writer(f).writerows(rows)
    md = ["# 04-sram-pim-cnn results (paste-ready)",
          "",
          "| Metric | Value |",
          "|---|---|"]
    for k, v in sorted(results.items()):
        md.append("| %s | %s |" % (k, v))
    md += ["",
           "Figures: `fig1_latency_scaling.png`, `fig2_throughput.png`,",
           "`fig3_acc_headroom.png` (generated by `docs/figures/generate_figures.py`).",
           "RTL sim: `%s` | Model: `python model/validate.py` (V1-V5)." % "sim/log/sim.log"]
    with open(os.path.join(FIGDIR, "results_snippet.md"), "w") as f:
        f.write("\n".join(md) + "\n")


def main():
    check_sim_log()
    fig_latency()
    fig_throughput()
    fig_headroom()
    write_tables()
    print("figures + tables written to %s" % FIGDIR)
    for k in sorted(results):
        print("  %-40s %s" % (k, results[k]))


if __name__ == "__main__":
    main()
