#!/usr/bin/env python3
"""Exploratory SKY130 HD mapping; not a substitute for Tiny Tapeout hardening."""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--liberty',type=Path,required=True)
p.add_argument('--top',default='tt_um_dinis_chacha20',choices=['tt_um_dinis_chacha20','chacha20_core'])
a=p.parse_args();lib=a.liberty.resolve();root=Path(__file__).resolve().parents[1]
out=root/'reports'/a.top;out.mkdir(parents=True,exist_ok=True)
def q(x): return '"'+str(x).replace('\\','/').replace('"','\\"')+'"'
script=f"""read_verilog {q(root/'src/chacha20_core.v')} {q(root/'src/tt_um_dinis_chacha20.v')}
synth -top {a.top} -flatten
 dfflibmap -liberty {q(lib)}
 abc -liberty {q(lib)}
 clean
 read_liberty -lib {q(lib)}
 check -assert
 stat -liberty {q(lib)}
 write_verilog -noattr -noexpr {q(out/'mapped.v')}
 write_json {q(out/'mapped.json')}
"""
(out/'synth.ys').write_text(script)
subprocess.run(['yosys','-l',str(out/'synthesis.log'),'-s',str(out/'synth.ys')],check=True)
(out/'provenance.json').write_text(json.dumps({'liberty':str(lib),'liberty_sha256':hashlib.sha256(lib.read_bytes()).hexdigest(),'note':'Unconstrained area mapping. No timing closure, floorplan, CTS, routing, DRC or LVS.'},indent=2))
