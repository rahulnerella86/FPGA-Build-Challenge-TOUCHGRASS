# ============================================================================
# 01-trng : Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
# ---------------------------------------------------------------------------
# !! VERIFY EVERY PIN below against the official Digilent Nexys A7 Master XDC
# !! (https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc)
# ============================================================================

# ---- 100 MHz system clock (CSG324: E3 - standard for Nexys A7) ----
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports clk_i]
create_clock -period 10.000 -name sys_clk [get_ports clk_i]

# ---- CPU_RESETN push button (active low) - VERIFY ----
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports rst_ni]
# ---- enable switch SW0 - VERIFY ----
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports en_i]

# ---- status LEDs - VERIFY (LED0/LED1 on Nexys A7 are H17/K15) ----
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {led_o[0]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {led_o[1]}]

# ---- UART TX for readout (placeholder pin - Pmod JA pin 1) ----
# !! Placeholder. VERIFY against master XDC. Consider using the USB-UART
# !! bridge instead: FPGA TX -> FT2232 RX so a PC terminal can read bits
# !! with no extra hardware. Pins: C4 (TXD of the bridge side) - VERIFY.
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports uart_txd_o]

# ---- same timing exceptions as Basys 3 (see basys3.xdc comments) ----
set_false_path -to  [get_pins -hierarchical -filter {NAME =~ *cdc_sync*sync_ff_1*/D}]
set_false_path -to  [get_pins -hierarchical -filter {NAME =~ *cdc_sync*sync_ff_2*/D}]
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *cdc_sync*}]
