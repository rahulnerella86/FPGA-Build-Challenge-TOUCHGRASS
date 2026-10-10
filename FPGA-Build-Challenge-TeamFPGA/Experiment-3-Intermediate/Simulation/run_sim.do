# run_sim.do - compile + run the self-checking NN accelerator testbench in
# ModelSim. Run from the project root:  vsim -c -do sim/run_sim.do
# Produces mac_sim.log and wave.do-able wlfs (see vsim command below).
vlib work
vlog -sv rtl/mac_unit.sv rtl/mac_array.sv rtl/nn_accel_top.sv tb/tb_mac_array.sv
vsim -c work.tb_mac_array -do "run -all; quit -f"
# For interactive waves: vsim work.tb_mac_array -do "add wave -position insertpoint sim:/tb_mac_array/u_top/*; run -all"
