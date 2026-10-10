## Nexys A7 template for 04-sram-pim-cnn (PLACEHOLDER - verify vs master XDC)
## Unconstrained until a board wrapper with clk/rst/pins exists. Simulation
## does not need this file; synthesis does. Check: clk period, pin LOCs,
## ASYNC_REG/false-path exceptions if CDC is added in project 05 wrapper.

# create_clock -period 10.000 -name clk [get_ports clk]
