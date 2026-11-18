#!/usr/bin/env python3
from pathlib import Path
import subprocess

from reference import block, vectors

root = Path(__file__).resolve().parents[1]
build = root / "test" / "build"
build.mkdir(exist_ok=True)

fixed_nonce = bytes.fromhex("000000004a00000000000000")
fixed_counter = 1

frames = []
expected = []

for key, _, _, plaintext in vectors():
    frames.append(key + plaintext)
    keystream = block(key, fixed_nonce, fixed_counter)
    expected.append(bytes(
        p ^ k for p, k in zip(plaintext, keystream)
    ))

(build / "frames.hex").write_text(
    "\n".join(frame.hex() for frame in frames) + "\n"
)
(build / "expected.hex").write_text(
    "\n".join(result.hex() for result in expected) + "\n"
)

subprocess.run([
    "iverilog",
    "-g2012",
    "-s", "tb",
    "-Ptb.N=" + str(len(frames)),
    "-o", str(build / "sim"),
    str(root / "src" / "chacha20_core.v"),
    str(root / "src" / "tt_um_dinis_chacha20.v"),
    str(root / "test" / "tb.sv"),
], check=True)

subprocess.run(
    ["vvp", str(build / "sim")],
    cwd=build,
    check=True,
)