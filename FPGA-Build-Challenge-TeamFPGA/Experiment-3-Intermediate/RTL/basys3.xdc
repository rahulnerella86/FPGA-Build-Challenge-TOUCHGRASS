# =============================================================================
# basys3.xdc - 03-quantized-nn-accelerator (Basys 3, XC7A35T-1CPG236C)
#
# VERIFY all pin assignments against the official Basys 3 master XDC:
#   https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc
# The pins below are the standard Basys 3 clock/UART/LED assignments but YOU
# MUST cross-check before implementing.
#
# DSP/BRAM PLACEMENT NOTES (XC7A35T: 90 DSP48E1, 50 BRAM36, 20800 LUT6):
#  * mac_array with N_PAR=8 infers 8 DSP48E1 slots. Default Vivado placement
#    is fine at this size; do NOT hand-place at N_PAR<=16.
#  * nn_accel_top's act/wgt/bias memories are small (16B / 128B / 32B) and
#    infer LUTRAM, not BRAM - no BRAM constraint needed for this tile size.
#    If you scale K_LEN*N_PAR beyond ~2 KiB, memories become BRAM; at that
#    point add create_pblock for the DSP column + BRAM column or Vivado will
#    scatter them and risk routing congestion.
#  * Clock: single 100 MHz domain, no CDC in this design.
# =============================================================================
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports clk_i]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk_i]

## reset: center pushbutton (VERIFY against master XDC)
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports rst_ni]

## start: right pushbutton (VERIFY)
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports start_i]

## done LED (VERIFY)
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports done_o]

## y_o debug LEDs - only in the bitstream bring-up wrapper; VERIFY every pin
## against the master XDC LED section before use.
# set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {y_o[0]}]
# set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {y_o[1]}]
# ... one LED per lane, N_PAR total

## Timing: straight synchronous design; report_timing at 100 MHz must close
## with the 8-DSP MAC chain (single DSP48 pipeline stage) with big margin.
