cd "C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator"
vlib "C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator/work"
vmap work "C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator/work"
vlog -sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/alu.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/branch_unit.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/control_unit.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/data_memory.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/instruction_memory.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/mac_accelerator.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/pc.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/register_file.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/riscv_core.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-ai-accelerator/rtl/system_top.sv C:/Projects/FPGA_projects/fpga-projects/04-sram-pim-cnn/rtl/pim_mac_bram.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator/rtl/custom_instr_decode.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator/rtl/cim_dispatch.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator/rtl/soc_top_cim.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator/tb/tb_custom_instr_decode.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator/tb/tb_cim_dispatch.sv C:/Projects/FPGA_projects/fpga-projects/05-riscv-sram-cim-accelerator/tb/tb_soc_top_cim.sv
echo === TB1: custom_instr_decode ===
load work.tb_custom_instr_decode
run -all
echo === TB2: cim_dispatch ===
load work.tb_cim_dispatch
run -all
echo === TB3: soc_top_cim ===
load work.tb_soc_top_cim
run -all
quit -f