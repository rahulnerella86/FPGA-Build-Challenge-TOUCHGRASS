cd "C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator"
vlib work
vmap work work
vlog -sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\alu.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\branch_unit.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\control_unit.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\data_memory.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\instruction_memory.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\mac_accelerator.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\pc.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\register_file.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\riscv_core.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\system_top.sv C:\Projects\FPGA_projects\fpga-projects\04-sram-pim-cnn\rtl\pim_mac_bram.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-sram-cim-accelerator\rtl\custom_instr_decode.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-sram-cim-accelerator\rtl\cim_dispatch.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-sram-cim-accelerator\rtl\soc_top_cim.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-sram-cim-accelerator\tb\tb_custom_instr_decode.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-sram-cim-accelerator\tb\tb_cim_dispatch.sv C:\Projects\FPGA_projects\fpga-projects\05-riscv-sram-cim-accelerator\tb\tb_soc_top_cim.sv
load work/tb_custom_instr_decode
run 500us
echo === TB1 DONE ===
load work/tb_cim_dispatch
run 500us
echo === TB2 DONE ===
load work/tb_soc_top_cim
run 500us
echo === TB3 DONE ===
quit -f
