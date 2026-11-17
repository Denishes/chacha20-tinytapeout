#!/usr/bin/env python3
"""Zero-delay simulation of our mapped netlist using Liberty-derived cell models."""
import argparse,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--liberty',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[1];b=r/'test/build';b.mkdir(exist_ok=True)
subprocess.run(['python3',str(r/'test/run.py')],check=True)
subprocess.run(['yosys','-p',f'read_liberty -ignore_miss_func "{a.liberty.resolve()}"; write_verilog -noattr "{b}/cells.v"'],check=True)
subprocess.run(['iverilog','-g2012','-s','tb','-o',str(b/'gate_sim'),str(b/'cells.v'),str(r/'reports/tt_um_dinis_chacha20/mapped.v'),str(r/'test/tb.sv')],check=True)
subprocess.run(['vvp',str(b/'gate_sim')],cwd=b,check=True)
