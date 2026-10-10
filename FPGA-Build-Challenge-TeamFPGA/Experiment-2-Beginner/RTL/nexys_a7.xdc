# ============================================================================
# nexys_a7.xdc - project-02 SoC constraints (Nexys A7-100, Artix-7 XC7A100T).
#
# These pin/clock values follow the Digilent Nexys A7 default master XDC.
# VERIFY AGAINST YOUR BOARD'S MASTER XDC before using - the master file
# shipped by Digilent changes per board revision.
# ============================================================================

# --- Primary IO clock: 100 MHz, master clock of the design ---------------
create_clock -name clk -period 10.000 [get_ports clk]

# --- PicoRV32 core + SoC fabric (design compatibility, not top level yet) -
# The design is partitioned in Vivado as a block design first; the following
# are the physical top-level only after a full hierarchy pushdown:
# set_property PACKAGER_PIN /clk [get_ports {clk}]

# --- Location of the CRC accelerator sub-block ----------------------------
# Synthesized as part of the SoC fabric. For floorplanning:
# set_property HLOCK TRUE [get_cells crc*]

# --- False-path / timing exceptions for the SoC nets ----------------------
# The design has NO cross-domain paths at this level (single 100 MHz clock).
# These are placeholders showing WHERE exceptions belong if you add a
# secondary clock domain (e.g. a 250 MHz accelerator clock) later:
# set_false_path -from [get_clocks clk] -to [get_clocks clk]
# set_multicycle_path -from [get_pins soc_top/ic/*valid] -to [get_pins soc_top/ic/*ready] 2

# --- BUFG / clocking -------------------------------------------------------
# Use of the raw board clock input (tie to clk) is allowed for this design.
# Verify your board routes clk to a global buffer (see master XDC).

# --- Reset ----------------------------------------------------------------
# The board drives rst_n via a debounce; keep rst_n on the top for the reset
# domain. VERIFY against your board's master XDC.

# --- UART pins for firmware upload/debug (Nexys A7) ------------------------
# The Nexys A7 UART lives on these IO, per Digilent master XDC:
# set_property PACKAGER_PIN /fpga_projects/02-riscv-soc-accelerator/rtl/uart_tx [get_ports {txd}]
# set_property PACKAGER_PIN /fpga_projects/02-riscv-soc-accelerator/rtl/uart_rx [get_ports {rxd}]

# NOTE: verify the exact signal/hier path against the board's master XDC -
# the above are placeholders for your hierarchy.