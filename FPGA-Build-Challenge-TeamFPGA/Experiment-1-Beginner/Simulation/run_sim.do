# run_sim.do - ModelSim script for 01-trng
# Usage:  vsim -c -do "do run_sim.do"
# Produces: sim waveforms (trng_wave.wlf) + trng_bits.txt for NIST analysis

vlib work
vmap work work

vlog -sv ../rtl/entropy_source.sv
vlog -sv ../rtl/cdc_sync.sv
vlog -sv ../rtl/vn_corrector.sv
vlog -sv ../rtl/trng_fifo.sv
vlog -sv ../rtl/trng_top.sv
vlog -sv ../tb/tb_trng_top.sv

vsim -c work.tb_trng_top

# log everything under trng_top so GTKWave/wlf shows all internals
log -r /*

run -all

# bit dump for:  python ../scripts/run_nist_tests.py trng_bits.txt
puts "Simulation done. trng_bits.txt written - run the NIST script next."
quit -f
