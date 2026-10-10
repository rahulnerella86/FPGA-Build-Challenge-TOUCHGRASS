# ============================================================================
# run_sim.do - ModelSim batch script for project-02 (SoC + accelerator).
#
#   From the project root:  vsim -c -do sim/run_sim.do
#   (must run from the project root: paths below are root-relative)
#
# Compiles the RTL/TB once, then runs both self-checking benches in one batch:
#   tb_bus_bfm  (fabric + slaves: strobes, B2B, AW+W, DECERR, CRC golden)
#   tb_soc_top  (full-SoC firmware-level sequence through the mem port)
# NOTE: earlier revisions used one `vsim -c -do "run -all; quit -f"` per TB,
# but the first `quit -f` ends the whole session, so only the first TB ever
# ran. Sequential `vsim` loads fix that, but each self-checking TB ends with
# $finish (which would also end the session), so loads use -onfinish stop to
# return to the script instead of quitting; the final quit -f ends the batch.
# (tb_crc_dbg / tb_axi_probe were debug-only probes, removed by the owner;
# they carried no verdict and are not part of this flow.)
# Output: sim/log/sim.log (contains both ALL-CHECK-PASSED lines)
# ============================================================================

if {[catch {project open .}] == 0} { puts "project opened" } else { puts "no project file - continuing without one" }
vlib work
vmap work work
vlog -sv rtl/mem_map_pkg.sv \
         rtl/axi_ram.sv \
         rtl/crc32_accel.sv \
         rtl/bus_interconnect.sv \
         rtl/mem2axi_lite.sv \
         rtl/soc_top.sv +define+SOC_TOP_WITH_BFM \
         tb/tb_bus_bfm.sv tb/tb_soc_top.sv
vsim -c -onfinish stop work.tb_bus_bfm
run -all
vsim -c -onfinish stop work.tb_soc_top
run -all
puts "All project-02 benches done."
quit -f
