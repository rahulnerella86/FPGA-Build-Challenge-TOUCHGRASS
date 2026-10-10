# FPGA Build Challenge 2026

Team FPGA's submission for the V-SPACE FPGA Build Challenge 2026.

## Project summary

This repository presents five FPGA design experiments that progress from a
hardware random-number source to RISC-V-assisted compute-in-memory (CIM).
Each experiment includes RTL, constraints where applicable, testbenches,
simulation material, and supporting documentation.

The designs target Xilinx Artix-7 devices, primarily the Basys 3
(XC7A35T-1CPG236C) and Nexys A7-100T (XC7A100T-1CSG324C). SystemVerilog is
the primary HDL; the PicoRV32 integration also contains Verilog sources.

## Experiments

### 1. Ring-oscillator TRNG

- Ring-oscillator entropy source with CDC synchronization.
- Von Neumann debiasing, AXI-Stream packing, and FIFO buffering.
- NIST SP 800-22 test harness and ModelSim verification.
- Hardware synthesis still requires implementation-specific constraints,
  including false paths and preservation of the ring oscillator.

### 2. PicoRV32 RISC-V CRC accelerator

- PicoRV32-compatible processor integration with an AXI-Lite memory map.
- CRC-32 accelerator, memory bridge, and bus interconnect.
- Bus BFM and SoC simulations pass; the CRC golden result is `0xCBF43926`.
- Firmware compilation and Vivado timing closure remain future work.

### 3. Quantized INT8 MAC array

- Parameterized signed INT8 multiply-accumulate datapath.
- DSP48E1-oriented arithmetic with explicit sign extension.
- Tiled neural-network accelerator with NumPy golden-model comparison.
- Known-answer and layer-0 bit-exact checks pass. The INT4 path is present
  but has not yet been exercised by vectors.

### 4. SRAM processing-in-memory (SRAM-PIM)

- BRAM-based digital model of an SRAM compute-in-memory macro.
- One-MAC-per-cycle streaming datapath for row-wise dot products.
- Reset recovery, back-to-back operation, and Python golden-model checks.
- The primary simulation checks pass; Vivado resource and timing reports
  remain future work.

### 5. RISC-V SRAM compute-in-memory (SRAM-CIM)

- Custom instruction and MMIO dispatch around the SRAM-CIM datapath.
- Loader, launch, status, result capture, row selection, and run-time
  write-gating logic.
- Custom-instruction decode and CIM dispatch testbenches pass.
- The complete SoC testbench still has an initialization/X-propagation issue
  under investigation, so it is not claimed as passing.

## Repository layout

```text
FPGA-Build-Challenge-TeamFPGA/
├── Experiment-1-Beginner/
├── Experiment-2-Beginner/
├── Experiment-3-Intermediate/
├── Experiment-4-Intermediate/
├── Experiment-5-Advanced/
├── Final_Report/
├── Images_summary.png
├── README.md
└── SUBMISSION_CHECKLIST.md
```

Each experiment directory is organized around its documentation, RTL,
testbench, simulation, images, and board constraints.

## Tools

- ModelSim Intel FPGA Edition 10.5b for RTL simulation.
- Python 3.10 for reference models, NIST tests, and plot generation.
- Vivado for synthesis, implementation, utilization, and timing analysis.
- RISC-V GNU toolchain when compiling the processor firmware.

Vivado and the RISC-V toolchain were not available for all verification runs.
The repository therefore distinguishes simulation results from hardware
implementation results and does not claim synthesis or timing closure where
those reports are absent.

## Running simulations

The exact source lists and ModelSim commands are maintained with each
experiment. A typical command sequence from an experiment directory is:

```text
vlib work
vlog -sv <RTL sources> <testbench sources>
vsim -c <work.testbench> -do "run -all; quit -f"
```

For repeatable project-specific flows, use the supplied `run_sim.py`,
`run_tests.do`, or simulation scripts when present. Generated ModelSim
libraries and waveform files are local build artifacts and are not part of
the submission.

## Verification status

Simulation logs and supporting reports are included where available. Results
are reported conservatively: a passing block-level testbench does not imply
that the design has been synthesized, placed, routed, or timed on hardware.
Known limitations and remaining work are tracked in the experiment
documentation and [`SUBMISSION_CHECKLIST.md`](SUBMISSION_CHECKLIST.md).

## Team information

Team member names and registration numbers should be added before final
submission.
