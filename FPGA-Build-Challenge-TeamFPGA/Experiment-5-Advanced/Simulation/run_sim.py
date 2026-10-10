import subprocess
import sys
import os

VSIM = r"C:\intelFPGA\20.1\modelsim_ase\win32aloem\vsim.exe"
VLOG = r"C:\intelFPGA\20.1\modelsim_ase\win32aloem\vlog.exe"
VLIB = r"C:\intelFPGA\20.1\modelsim_ase\win32aloem\vlib.exe"
VMAP = r"C:\intelFPGA\20.1\modelsim_ase\win32aloem\vmap.exe"

PROJ = r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-sram-cim-accelerator"
WORKDIR = os.path.join(PROJ, "work")
LOGDIR = os.path.join(PROJ, "sim", "log")
os.makedirs(LOGDIR, exist_ok=True)
LOG = os.path.join(LOGDIR, "sim_rerun.log")
DO_FILE = os.path.join(PROJ, "run_tests.do")

FILES = [
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\alu.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\branch_unit.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\control_unit.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\data_memory.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\instruction_memory.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\mac_accelerator.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\pc.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\register_file.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\riscv_core.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\05-riscv-ai-accelerator\rtl\system_top.sv",
    r"C:\Projects\FPGA_projects\fpga-projects\04-sram-pim-cnn\rtl\pim_mac_bram.sv",
    os.path.join(PROJ, "rtl", "custom_instr_decode.sv"),
    os.path.join(PROJ, "rtl", "cim_dispatch.sv"),
    os.path.join(PROJ, "rtl", "soc_top_cim.sv"),
    os.path.join(PROJ, "tb", "tb_custom_instr_decode.sv"),
    os.path.join(PROJ, "tb", "tb_cim_dispatch.sv"),
    os.path.join(PROJ, "tb", "tb_soc_top_cim.sv"),
]

log_f = open(LOG, "w", encoding="utf-8")

def log(msg):
    print(msg)
    log_f.write(msg + "\n")
    log_f.flush()

def run(cmd, label=""):
    log(f"\n{'='*70}")
    log(f"RUN: {' '.join(cmd)}" + (f"  [{label}]" if label else ""))
    log(f"{'='*70}")
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, cwd=PROJ, bufsize=1)
    for line in p.stdout:
        log(line.rstrip("\n"))
    rc = p.wait()
    log(f"--- exited with code {rc} ---")
    return rc

def main():
    import shutil
    # Clean
    if os.path.isdir(WORKDIR):
        shutil.rmtree(WORKDIR)
        log(f"Removed {WORKDIR}")

    # vlib
    run([VLIB, WORKDIR], "vlib")
    # vmap
    run([VMAP, "work", WORKDIR], "vmap")
    # vlog
    rc = run([VLOG, "-sv"] + FILES, "vlog")
    if rc != 0:
        log("COMPILE FAILED")
        log_f.close()
        sys.exit(1)

    # Write do-file with short token paths (no spaces/colons in tokens)
    log(f"\nWriting do-file: {DO_FILE}")
    with open(DO_FILE, "w", encoding="ascii") as f:
        f.write("cd \"{0}\"\n".format(PROJ.replace("\\", "/")))
        f.write("vlib work\n")
        f.write("vmap work work\n")
        # Paths must have backslashes escaped for Tcl (a single \ in file = escape char in Tcl)
        f.write("vlog -sv " + " ".join(f.replace("\\", "\\\\") for f in FILES) + "\n")
        f.write("load work/tb_custom_instr_decode\n")
        f.write("run 500us\n")
        f.write("echo === TB1 DONE ===\n")
        f.write("load work/tb_cim_dispatch\n")
        f.write("run 500us\n")
        f.write("echo === TB2 DONE ===\n")
        f.write("load work/tb_soc_top_cim\n")
        f.write("run 500us\n")
        f.write("echo === TB3 DONE ===\n")
        f.write("quit -f\n")
    log("Do-file written OK")

    # Run via do-file using relative path (vsim cds to PROJ via the cd in do-file)
    rc = run([VSIM, "-c", "-do", "do run_tests.do"], "vsim all tests")

    log("\n" + "="*70)
    if rc == 0:
        log("*** ALL TESTS PASSED ***")
    else:
        log(f"*** vsim exited {rc} ***")
    log(f"Full log: {LOG}")
    log_f.close()
    sys.exit(rc)

if __name__ == "__main__":
    main()