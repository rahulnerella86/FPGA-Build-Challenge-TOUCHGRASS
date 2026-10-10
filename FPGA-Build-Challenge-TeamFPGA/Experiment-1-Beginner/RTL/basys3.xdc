# ============================================================================
# 01-trng : Basys 3 (Artix-7 XC7A35T-1CPG236C)
# ---------------------------------------------------------------------------
# !! VERIFY EVERY PIN below against the official Digilent Basys 3 Master XDC
# !! (https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc)
# !! before synthesis. The clock pin is well-known; UART pin choice is yours.
# ============================================================================

# ---- 100 MHz system clock (CFBGA236: E3/W5 - this one is standard) ----
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports clk_i]
create_clock -period 10.000 -name sys_clk [get_ports clk_i]

# ---- active-low reset on center button (VERIFY: Basys 3 CPU_RESETN is U18) ----
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports rst_ni]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports en_i]

# ---- status LEDs (VERIFY against master XDC) ----
# led_o[0] = FIFO not empty, led_o[1] = overflow drop event
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led_o[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {led_o[1]}]

# ---- UART TX for bitstream readout (placeholder - pick any free Pmod pin) ----
# !! Placeholder pin. E.g., JA pin 1 = J1 on Basys 3. VERIFY against master XDC.
set_property -dict { PACKAGE_PIN J1  IOSTANDARD LVCMOS33 } [get_ports uart_txd_o]

# ----------------------------------------------------------------------------
# TIMING EXCEPTIONS - REQUIRED for the ring-oscillator entropy source
# ----------------------------------------------------------------------------
# The ring oscillator is an asynchronous free-running net. Vivado MUST NOT:
#   1. time it against clk_i (impossible/false paths), or
#   2. "helpfully" balance/duplicate its LUTs along routing paths.
#
# TRICKY / MUST-DO: after synthesis, open the synthesized design and confirm
# the RO nets were NOT absorbed into LUT combining. Use:
#   set_property DONT_TOUCH true [get_cells ro_inst/*]
# in the XDC or post-synth, and check the synthesis log for "absorbed" LUTs.
# If Vivado optimizes the RO away entirely (symptom: RO frequency report shows
# nothing, or output is stuck), the RO LUTs were merged - fix with DONT_TOUCH
# and/or keep_hierarchy, and mark the RO input register ASYNC_REG.
# ----------------------------------------------------------------------------
set_false_path -to  [get_pins -hierarchical -filter {NAME =~ *cdc_sync*sync_ff_1*/D}]
set_false_path -to  [get_pins -hierarchical -filter {NAME =~ *cdc_sync*sync_ff_2*/D}]
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *cdc_sync*}]
