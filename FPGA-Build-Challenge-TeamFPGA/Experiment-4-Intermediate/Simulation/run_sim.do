# run_sim.do - ModelSim script for 04-sram-pim-cnn
# Usage (from project root):  vsim -c -do sim/run_sim.do
#         (from sim dir):      vsim -c -do "do run_sim.do"
# Produces: sim/log/sim.log with "*** ALL CHECKS PASSED (tb_pim_mac) ***"
if {[catch {project open .}] == 0} { puts "project opened" }
vlib work
vmap work work
if {[file exists "../rtl/pim_mac_bram.sv"]} {
    vlog -sv ../rtl/pim_mac_bram.sv ../tb/pim_mac_tb.sv
} else {
    vlog -sv rtl/pim_mac_bram.sv tb/pim_mac_tb.sv
}
vsim -c -suppress 3534 work.tb_pim_mac
log -r /*
run -all
puts "Simulation done."
quit -f
