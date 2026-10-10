# =============================================================================
# nexys_a7.xdc - 03-quantized-nn-accelerator (Nexys A7-100T, XC7A100T-1CSG324)
#
# VERIFY all pin assignments against the official Nexys A7 master XDC:
#   https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc
#
# DSP/BRAM PLACEMENT NOTES (XC7A100T: 240 DSP48E1, 135 BRAM36):
#  * N_PAR=8 -> 8 DSP (3%); N_PAR=32 -> 32 DSP (13%). Both trivially fit.
#  * The default single-clock design needs no CDC constraints.
#  * At N_PAR>=32 the accumulator fanout to y_o grows; if report_timing shows
#    the requant chain as critical path, register psum before req() (one
#    more S_DRAIN beat, update drain_q==2'd3 -> 2'd4).
# =============================================================================
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports clk_i]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk_i]

## CPU_RESETN button (active-low; VERIFY polarity against your wrapper)
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports rst_ni]

## start: BTNC (VERIFY)
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports start_i]

## done LED (VERIFY)
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports done_o]

## y_o debug LEDs (VERIFY against master XDC LED section)
# set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {y_o[0]}]
# ... one per lane
