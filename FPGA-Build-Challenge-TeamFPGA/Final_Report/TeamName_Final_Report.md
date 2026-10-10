# V-SPACE FPGA Build Challenge 2026 — Final Team Report (Team FPGA)

## Competition and team information

- Competition: V-SPACE FPGA Build Challenge 2026
- Team: Team FPGA (TODO: replace with registered TeamName; rename folder `FPGA-Build-Challenge-TeamFPGA` accordingly)
- Members / registration numbers: TODO
- Repo: `FPGA-Build-Challenge-TeamFPGA/` (this submission scaffold, mapped from `fpga-projects/`)

## Overall introduction and objectives

Ordered progression entropy/CDC → bus integration → MAC/quantization → memory-centric datapath → custom-ISA co-processor. Objectives: (1) synthesizable SystemVerilog everywhere, (2) self-checking TBs (never waveform-only), (3) no fabricated results — every claim backed by a log or marked TODO.

## FPGA board and development environment

- Boards: Basys 3 (XC7A35T) / Nexys A7-100T (XC7A100T); per-experiment XDC in `Experiment-*/RTL/*.xdc` (TEMPLATE — verify vs Digilent master).
- HDL: SystemVerilog (+ PicoRV32 Verilog in Exp2).
- Tools actually used: ModelSim Intel FPGA ASE 10.5b (`vlog`/`vsim`), Python 3.10 (NIST harness, golden refs, plots). Vivado NOT run here; RISC-V GCC NOT installed (see toolchain notes in root README).

## Summary of all five experiments

| # | Experiment | Level | Status (evidence-based) |
|---|---|---|---|
| 1 | Ring-Oscillator TRNG | Beginner | Simulated — `*** ALL CHECKS PASSED (tb_trng_top) ***` in `Experiment-1-Beginner/Simulation/transcript.txt`; NIST chi2 9.055, bias frac 0.4945 |
| 2 | PicoRV32 RISC-V CRC Accelerator | Beginner | RE-VERIFIED 2026-10-10 — both benches `ALL CHECKS PASSED`; CRC golden `0xCBF43926` (`Simulation/rerun_2026-10-10.log`) |
| 3 | INT8 MAC Array | Intermediate | RE-VERIFIED 2026-10-10 — M1=34, M2 bit-exact vs NumPy, M3 re-arm (`Simulation/rerun_2026-10-10.log`); INT4 RTL untested |
| 4 | SRAM-PIM | Intermediate | RE-VERIFIED 2026-10-10 — `ALL CHECKS PASSED (tb_pim_mac)` P1–P5 (`Simulation/rerun_2026-10-10.log`); consistent with earlier `mismatches=0` |
| 5 | RISC-V SRAM-CIM | Advanced | PARTIAL 2026-10-10 — decode + dispatch PASS (272/32 goldens); `tb_soc_top_cim` FAILS ×8 (PC=X, under investigation, NOT claimed) |

## Individual objectives and architectures

- Exp1: `entropy_source → cdc_sync → vn_corrector → packer → trng_fifo (AXI-S)`. See `Experiment-1-Beginner/Documentation/Experiment_Report.md` Fig.1 + `Images/block_diagram.png`.
- Exp2: `mem port → mem2axi_lite → bus_interconnect → axi_ram / crc32_accel`. See Exp2 report.
- Exp3: `ACT/WGT/BIAS mems → mac_array (N_PAR mac_unit) → SHIFT requant → y_o`, FSM `nn_accel_top`. See Exp3 report.
- Exp4: `wmem BRAM + amem → shared MAC → acc → rmem`, IDLE/COMPUTE/DONE. Honest approximation, not analog CiM. See Exp4 report.
- Exp5: `core MMIO + cim_valid/rs1 → cim_dispatch (IDLE/RUN/WAIT/CAP/HOLD) → pim_mac_bram (by ref)`. Level launch, drop-flag, clamp. See Exp5 report.

## Simulation and hardware results

Simulation: ModelSim commands per root README and each `Simulation/run_sim.do`. Genuine transcripts/logs copied to each `Simulation/`; `transcript.txt` normalized where source `transcript` existed. `waveform.png` NOT fabricated — pending export from `vsim.wlf` via `view wave` screenshot. `simulation_report.pdf` per experiment: pending (Markdown source is authoritative).

Hardware: no synthesis/PnR/programming run in this environment. No LUT/FF/BRAM/DSP, no silicon NIST, no board photos claimed. `Images/board_setup.jpg`, `hardware_output.jpg`, `rtl_schematic.png`: TODO/pending. All XDCs marked TEMPLATE.

## Comparative discussion

| Dim | Exp1 | Exp2 | Exp3 | Exp4 | Exp5 |
|---|---|---|---|---|---|
| Bottleneck | VN throughput (1 word/256 raw min) | bitwise CRC 36c/word, single-outstanding | 1 MAC/cycle/lane | 1 MAC/cycle engine | dispatch drop-flag (no stall port) |
| Proof style | statistical + scoreboard | BFM edge + golden | bit-exact NumPy | independent ref + golden | independent ref_dot + protocol |
| Reuse | CDC/FIFO pattern | SoC pattern → Exp5 | requant → Exp4 note | engine → Exp5 by ref | wraps Exp2+Exp4 |

## Innovation and technical contributions

- FWFT-race-free TB sampling (tv_q), ready-low settle, level (not edge) CIM launch, issue-counter width fix, explicit sign-extension for DSP mapping — all found by TB trace and documented in code.
- `[ST]` latency instrumentation → latency figure pipeline.
- Honest-labelling discipline: behavioral jitter vs silicon entropy, approximation vs circuit, paused vs verified.

## Limitations and future scope

- Re-run Exp2/Exp4/Exp5 sims from submission CWDs; export `waveform.png`; generate PDFs.
- Vivado synth + timing (100 MHz), BRAM/DSP verify, XDC pin verify, `DONT_TOUCH` RO handling.
- Capture ≥1M HW bits (Exp1 UART), build riscv-gcc firmware (Exp2/5), INT4 + layer2 vectors (Exp3), parallel MACs + requant (Exp4), board_top + on-board FC golden (Exp5).
- Record team/board/video URLs; rename TeamFPGA → registered name.

## Overall conclusion

Submission scaffold is traceable and simulation-grounded; no hardware claimed without evidence. Remaining work is explicitly TODO-tagged in README, checklist, and per-experiment reports.

## References and figure captions

- Exp1 Figs: NIST p-values, nibble hist, ones ratio, pipeline block diagram.
- Exp2 Fig: AXI latency from `[ST]` lines.
- Exp3 Figs: ref-vs-exp, weight hist.
- Exp4 Figs: latency scaling, throughput, acc headroom + `results_summary.csv`.
- Exp5 Figs: CIM results plots.
- Docs: ModelSim 10.5b, Xilinx 7-series (DSP48E1/BRAM), Digilent master XDCs, NIST SP 800-22, PicoRV32/RISC-V ISA, von Neumann 1951.

Linked reports: `../Experiment-1-Beginner/Documentation/Experiment_Report.md` … `../Experiment-5-Advanced/Documentation/Experiment_Report.md`.
Final PDF: `TeamName_Final_Report.pdf` — TODO: export from this Markdown (e.g. Pandoc/Word) and verify; Markdown is authoritative until then.
