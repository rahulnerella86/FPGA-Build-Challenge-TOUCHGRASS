#!/usr/bin/env python3
"""Decode the tb_soc_top_cim firmware words with standard RISC-V semantics.

Used to verify which immediate convention the hand-written testbench firmware
assumes, and to produce the address/target table for the RTL reference model.
"""
import re
import sys

PC_BASE = 0x00000000


def sx(v, bits):
    if v & (1 << (bits - 1)):
        v -= (1 << bits)
    return v


def decode(w, pc):
    op = w & 0x7F
    rd = (w >> 7) & 0x1F
    f3 = (w >> 12) & 0x7
    rs1 = (w >> 15) & 0x1F
    rs2 = (w >> 20) & 0x1F
    f7 = (w >> 25) & 0x7F

    if op == 0x37:                                   # LUI
        return f"LUI   x{rd}, 0x{w >> 12:x}"
    if op == 0x17:                                   # AUIPC
        return f"AUIPC x{rd}, 0x{w >> 12:x}"
    if op == 0x6F:                                   # JAL
        imm = ((w >> 31) << 20) | (((w >> 12) & 0xFF) << 12) | \
              (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1)
        tgt = pc + sx(imm, 21)
        return f"JAL   x{rd}, {sx(imm,21):+d}  -> 0x{tgt:03X}"
    if op == 0x67:                                   # JALR
        imm = sx(w >> 20, 12)
        return f"JALR  x{rd}, {imm:+d}(x{rs1})"
    if op == 0x63:                                   # BRANCH
        imm = ((w >> 31) << 12) | (((w >> 7) & 1) << 11) | \
              (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1)
        imm = sx(imm, 13)
        tgt = pc + imm
        name = {0: "BEQ", 1: "BNE", 4: "BLT", 5: "BGE",
                6: "BLTU", 7: "BGEU"}.get(f3, f"BR{f3}")
        return f"{name:<5} x{rs1}, x{rs2}, {imm:+d}  -> 0x{tgt:03X}"
    if op == 0x03:                                   # LOAD
        imm = sx(w >> 20, 12)
        name = {0: "LB", 1: "LH", 2: "LW", 4: "LBU", 5: "LHU"}.get(f3, f"L{f3}")
        return f"{name:<5} x{rd}, {imm}(x{rs1})"
    if op == 0x23:                                   # STORE
        imm = ((w >> 25) << 5) | ((w >> 7) & 0x1F)
        name = {0: "SB", 1: "SH", 2: "SW"}.get(f3, f"S{f3}")
        return f"{name:<5} x{rs2}, {sx(imm,12)}(x{rs1})"
    if op == 0x13:                                   # OP-IMM
        imm = sx(w >> 20, 12)
        if f3 == 0:
            return f"ADDI  x{rd}, x{rs1}, {imm}"
        name = {2: "SLTI", 3: "SLTIU", 4: "XORI", 6: "ORI", 7: "ANDI",
                1: "SLLI", 5: "SRLI"}.get(f3, f"OPI{f3}")
        return f"{name:<5} x{rd}, x{rs1}, {imm}"
    if op == 0x33:                                   # OP
        return f"OP{f3}  x{rd}, x{rs1}, x{rs2}"
    if op == 0x0B:                                   # custom-0
        return f"CIM.RUN row={rs1} (f3={f3} f7=0x{f7:02x})"
    return f"UNKNOWN opcode 0x{op:02x} (w=0x{w:08X})"


def load_words(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    words = {}
    for m in re.finditer(r"imem_inst\.mem\[(\d+)\]\s*=\s*32'h([0-9A-Fa-f]+)", txt):
        words[int(m.group(1))] = int(m.group(2), 16)
    return words


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else \
        "../tb/tb_soc_top_cim.sv"
    words = load_words(path)
    for idx in sorted(words):
        pc = PC_BASE + 4 * idx
        print(f"{idx:3d} 0x{pc:03X}  0x{words[idx]:08X}  {decode(words[idx], pc)}")