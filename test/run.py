#!/usr/bin/env python3
from pathlib import Path
import subprocess
from reference import block,vectors
root=Path(__file__).resolve().parents[1]
build=root/'test'/'build'; build.mkdir(exist_ok=True)
vs=list(vectors())
frames=[]; expected=[]
for key,nonce,counter,pt in vs:
    frames.append(key+nonce+counter.to_bytes(4,'little')+pt)
    expected.append(bytes(a^b for a,b in zip(pt,block(key,nonce,counter))))
(build/'frames.hex').write_text('\n'.join(x.hex() for x in frames)+'\n')
(build/'expected.hex').write_text('\n'.join(x.hex() for x in expected)+'\n')
subprocess.run(['iverilog','-g2012','-s','tb','-Ptb.N='+str(len(vs)),
 '-o',str(build/'sim'),str(root/'src/chacha20_core.v'),
 str(root/'src/tt_um_dinis_chacha20.v'),str(root/'test/tb.sv')],check=True)
subprocess.run(['vvp',str(build/'sim')],cwd=build,check=True)
