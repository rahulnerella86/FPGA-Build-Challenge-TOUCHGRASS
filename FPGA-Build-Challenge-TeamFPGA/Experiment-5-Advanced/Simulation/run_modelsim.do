# run_modelsim.do - ModelSim batch flow for 05-riscv-sram-cim-accelerator.
#   From THIS directory:  vsim -c -do sim/run_modelsim.do
# (must run from the project root: ../05-riscv-ai-accelerator and
# ../04-sram-pim-cnn are referenced by relative path - never copied here,
# so the verified sources stay single-sourced and this project cannot
# silently fork them.)
#
# Compiles: ai-accelerator RTL (unmodified) + pim_mac_bram (unmodified) +
# local rtl/*.sv + tb/*.sv. Runs the three new benches in one batch.
# Each `run` bound is a watchdog: fixed TBs $finish early (the exhaustive
# decode sweep needs ~164us of #1 steps: 131072 + 32768 iterations); a hang
# consumes the budget and the missing verdict line exposes it in the log.
# Loads use -onfinish stop (each TB ends with $finish/$fatal; a plain
# quit -f after the first TB would end the whole session).
# Output: sim/log/sim.log (tee it: vsim ... 2>&1 | tee sim/log/sim.log)

if {[catch {project open .}] == 0} { puts "project opened" } else { puts "no project file - continuing without one" }
vlib work
vmap work work
vlog -sv ../05-riscv-ai-accelerator/rtl/*.sv \
         ../04-sram-pim-cnn/rtl/pim_mac_bram.sv \
         rtl/custom_instr_decode.sv \
         rtl/cim_dispatch.sv \
         rtl/soc_top_cim.sv \
         tb/tb_custom_instr_decode.sv \
         tb/tb_cim_dispatch.sv \
         tb/tb_soc_top_cim.sv
foreach tb {tb_custom_instr_decode tb_cim_dispatch tb_soc_top_cim} {
    puts "===== $tb ====="
    vsim -c -onfinish stop work.$tb
    run 300us
}
puts "All 05-riscv-sram-cim-accelerator benches done."
quit -f
