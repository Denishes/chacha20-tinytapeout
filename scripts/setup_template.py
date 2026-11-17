#!/usr/bin/env python3
"""Create a fresh official-template checkout and apply this tested overlay."""
import argparse,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('destination',type=Path);a=p.parse_args()
dst=a.destination.resolve();src=Path(__file__).resolve().parents[1]
if dst.exists(): raise SystemExit('Destination must not exist; refusing to overwrite a checkout.')
subprocess.run(['git','clone','https://github.com/TinyTapeout/ttsky-verilog-template.git',str(dst)],check=True)
for name in ['src','test','docs','scripts']:
    shutil.copytree(src/name,dst/name,dirs_exist_ok=True,
        ignore=shutil.ignore_patterns('build','__pycache__'))
for name in ['README.md','info.yaml','Makefile']:
    shutil.copy2(src/name,dst/name)
shutil.copy2(src/'.github/workflows/rtl.yml',dst/'.github/workflows/chacha-rtl.yml')
print('Created',dst)
print('Official GDS/docs workflows retained. Review info.yaml, run tests, then push to your own repository.')
