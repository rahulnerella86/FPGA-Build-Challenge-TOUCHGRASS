# FPGA Build Challenge 2026 - Team FPGA

## Competition Name
V-SPACE FPGA Build Challenge 2026

## Team Name
Team FPGA

## Team Members and Registration Numbers
- TODO: Add team member names and registration numbers

## Selected FPGA Development Board
- TODO: The existing projects target either Basys 3 (Artix-7 XC7A35T-1CPG236C) or Nexys A7-100T (Artix-7 XC7A100T-1CSG324C). Board selection depends on the specific experiment; constraints files for both boards are present in each project.

## FPGA Device
- TODO: Xilinx Artix-7 (XC7A35T for Basys 3, XC7A100T for Nexys A7)

## HDL Used
- SystemVerilog (primary)
- Verilog ( PicoRV32 core in experiment 2)

## Software Tools
- ModelSim Intel FPGA Edition 10.5b for RTL simulation
- Python 3.10 for NIST statistical harness and golden reference generation
- Vivado (mentioned as not run on this machine; XDC constraints provided)
- RISC-V GNU toolchain (not installed; see common/riscv-toolchain.md for setup)

## Overview of Five Experiments
This repository contains a deliberate, ordered progression from foundational FPGA craft toward research-adjacent compute-in-memory, mapped to the V-SPACE FPGA Build Challenge 2026 submission format:

### Experiment 1: Ring-Oscillator-Based TRNG (Beginner)
- **Objective**: Design a true random number generator using ring oscillator entropy, cross-domain CDC synchronization, von Neumann bias correction, and AXI-Stream packing/FIFO output.
- **Technical Contribution**: Statistical jitter model, 2-FF synchronizer, von Neumann corrector, FIFO with overflow detection, NIST SP 800-22 test harness.
- **Completion Status**: Simulation verified (ModelSim). All 5 testbench phases pass (`*** ALL CHECKS PASSED (tb_trng_top) ***`). Hardware implementation not yet synthesized; ring oscillator requires false-path constraints and DONT_TOUCH attributes for synthesis.

### Experiment 2: PicoRV32 RISC-V CRC Accelerator (Beginner)
- **Objective**: Integrate a PicoRV32-compatible soft core with AXI-Lite memory map, a CRC-32 accelerator slave, and an interconnect bus fabric; verify memory-port contract and CRC golden results.
- **Technical Contribution**: Mem2AXI-Lite bridge, bus interconnect with strobe/ready handshake, CRC-32 bitwise accumulation, firmware-free testbench using pre-assembled program image.
- **Completion Status**: Simulation RE-VERIFIED 2026-10-10 (`Simulation/rerun_2026-10-10.log`): `tb_bus_bfm` PASS, `tb_soc_top` PASS (CRC golden `0xCBF43926`). Firmware (.elf) not built (no riscv-gcc). Vivado synthesis + timing closure for Nexys A7 still TODO.

### Experiment 3: INT8 MAC Array (Intermediate)
- **Objective**: Implement a parameterized INT8 signed MAC unit with accumulation pipeline, and a top-level quantized neural network accelerator that processes quantized matrix-vector layers and compares against bit-exact NumPy golden references.
- **Technical Contribution**: DSP48E1-based signed multiply with explicit sign extension, 64-deep accumulation, FSM-controlled tile engine, bit-exact NumPy reference comparison, back-to-back tile re-arm handling.
- **Completion Status**: Simulation verified (ModelSim). Known-answer MAC test passes (3*(-7)+5*11=34). Full tile bit-exact vs NumPy reference validated for layer0. INT4 path implemented in RTL but not yet exercised by vectors. Requires Vivado utilization report to verify DSP count matches math claims.

### Experiment 4: SRAM Processing-in-Memory (SRAM-PIM) (Intermediate)
- **Objective**: Implement a BRAM-based digital stand-in for an SRAM compute-in-memory macro, streaming one weight per cycle into a shared INT8*INT8->INT32 MAC engine to compute row-wise dot products; verify against independent Python golden model.
- **Technical Contention**: Synchronous 1R1W BRAM weight memory, distributed activation registers, FSM-driven issue/consumption pipeline, 1 MAC/cycle throughput, reset mid-compute recovery, back-to-back run protocol, optional Python golden vector cross-check.
- **Completion Status**: Simulation RE-VERIFIED 2026-10-10 on submission-tree sources (`Simulation/rerun_2026-10-10.log`): `*** ALL CHECKS PASSED (tb_pim_mac) ***` (P1–P5; P6 skipped, no `vectors/*.hex`). Consistent with earlier `rtl_vs_golden_mismatches=0`. Hardware (Vivado synth, BRAM confirm, timing) still TODO.

### Experiment 5: RISC-V SRAM Compute-in-Memory (SRAM-CIM) (Advanced)
- **Objective**: Build a custom RISC-V instruction dispatch layer that wraps the CiM block from experiment 4, exposing loader/launch/status MMIO registers over a custom-instruction interface, with verified result capture from the BRAM-CiM engine.
- **Technical Contribution**: MMIO dispatch FSM (IDLE/RUN/WAIT/CAP/HOLD), sticky dropped flag, level-based launch discipline, result register capture (2-cycle latency), row-select clamping, loader-write-during-run gating.
- **Completion Status**: RTL + TBs present (dispatch, decode, soc_top_cim; base-core RTL vendored from `05-riscv-ai-accelerator/rtl/`). Fresh runs 2026-10-10 (`Simulation/rerun_2026-10-10.log`): `tb_custom_instr_decode` PASS, `tb_cim_dispatch` PASS (row2 = 272, clamp = 32); `tb_soc_top_cim` FAILS (8, PC=X — init/X-propagation under investigation, NOT claimed). Firmware = assembler/C source only (no riscv-gcc). Vivado synth + XDC still TODO.

## Repository Directory Structure
```
FPGA-Build-Challenge-TeamFPGA/
├── README.md
├── SUBMISSION_CHECKLIST.md
├── Experiment-1-Beginner/
│   ├── Documentation/
│   ├── RTL/
│   ├── Testbench/
│   ├── Simulation/
│   ├── Images/
│   └── Video_Link.txt
├── Experiment-2-Beginner/
│   └── ... (same structure)
├── Experiment-3-Intermediate/
│   └── ... (same structure)
├── Experiment-4-Intermediate/
│   └── ... (same structure)
├── Experiment-5-Advanced/
│   └── ... (same structure)
└── Final_Report/
    └── TeamName_Final_Report.md
```

## Instructions to Install or Configure the Required Tools
- ModelSim Intel FPGA Edition 10.5b: Ensure `vlog` and `vsim` are on PATH. The repo was developed on Windows with ModelSim at `C:\intelFPGA\10.5b\modelsim_ase\win32aloem\`.
- Python 3.10: Required for NIST harness (`scripts/run_nist_tests.py`) and figure generation.
- Vivado: XDC constraints are provided in each project `constraints/` directory and in `common/xdc/`. Vivado synthesis has not been run on this machine.
- RISC-V toolchain: Not installed. See `common/riscv-toolchain.md` for Ubuntu/WSL2 setup if firmware compilation is needed.

## Instructions for Simulating Each Project
All simulations use ModelSim (vlog/vsim). Run from the repo root or each project root:

**Experiment 1 (TRNG):**
```powershell
cd FPGA-Build-Challenge-TeamFPGA\Experiment-1-Beginner
vlib work; vlog -sv RTL/entropy_source.sv RTL/cdc_sync.sv RTL/vn_corrector.sv RTL/trng_fifo.sv RTL/trng_top.sv Testbench/tb_trng_top.sim
vsim -c work.tb_trng_top
# Within vsim: run -all; quit -f
# Output: sim/tb_sim.log, sim/trng_bits.txt
```

**Experiment 2 (RISC-V SOC Accelerator):**
```powershell
cd FPGA-Build-Challenge-TeamFPGA\Experiment-2-Beginner
vlib work; vmap work work
vlog -sv +define+SOC_TOP_WITH_BFM RTL/mem_map_pkg.sv RTL/axi_ram.sv RTL/crc32_accel.sv RTL/bus_interconnect.sv RTL/mem2axi_lite.sv RTL/soc_top.sv tb/tb_soc_top.sv tb/tb_bus_bfm.sim
vsim -c -onfinish stop work.tb_bus_bfm
run -all
vsim -c -onfinish stop work.tb_soc_top
run -all
```

**Experiment 3 (INT8 MAC Array):**
```powershell
cd FPGA-Build-Challenge-TeamFPGA\Experiment-3-Intermediate
vlib work; vlog -sv RTL/mac_unit.sv RTL/mac_array.sv RTL/nn_accel_top.sv Testbench/tb_mac_array.sim
vsim -c work.tb_mac_array -do "run -all; quit -f"
```

**Experiment 4 (SRAM-PIM):**
```powershell
cd FPGA-Build-Challenge-TeamFPGA\Experiment-4-Intermediate
vlib work; vmap work work
if [file exists "../rtl/pim_mac_bram.sv"] { vlog -sv ../rtl/pim_mac_bram.sv ../tb/pim_mac_tb.sim } else { vlog -sv rtl/pim_mac_bram.sv tb/pim_mac_tb.sim }
vsim -c -suppress 3534 work.tb_pim_mac
log -r /*; run -all; quit -f
```

**Experiment 5 (SRAM-CIM):**
- Scaffold not yet started. See run_sim.py and run_tests.do for the planned flow once experiment 04 is re-verified.

## Instructions for Synthesis, Implementation, and Hardware Demonstration
- Synthesis and FPGA implementation have NOT been run on this machine. XDC constraint files are provided per project for Basys 3 and Nexys A7, but they are marked as TEMPLATES - verify every pin against the official Digilent master XDC files before synthesis.
- The ring oscillator (experiment 1) requires special handling: set_false_path constraints for the RO nets, DONT_TOUCH attributes, and ASYNC_REG marks on the CDC synchronizer. Vivado may optimize RO LUTs away - DONT_TOUCH and keep_hierarchy are mandatory.
- UART TX is available for bitstream readout; a USB-UART bridge (FT2232) is recommended for bitstream readout without extra hardware.
- Hardware results (resource utilization, NIST on silicon, etc.) are not claimed in this repo. All simulation evidence is backed by ModelSim transcripts and log files.

## Linked Reports and Demonstration Videos
- Individual experiment reports: see `Experiment-X-Beginner/Documentation/Experiment_Report.md` for each experiment.
- Demonstration videos: Google Drive URLs to be uploaded; see each `Video_Link.txt` for the template format.

## Acknowledgements and References
- ModelSim Intel FPGA Edition 10.5b documentation
- Digilent Basys 3 and Nexys A7 reference manuals and master XDC files
- Xilinx 7-series DSP48E1 and Block RAM user manuals
- NIST SP 800-22 statistical test suite
- PicoRV32 and RISC-V ISA documentation
- von Neumann bias correction methodology