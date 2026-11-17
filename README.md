# ChaCha20 Tiny Tapeout SKY130 baseline

Working RTL baseline using the existing 1QR/128-bit-output core, with a
synchronous byte-wide Tiny Tapeout wrapper. See [protocol](docs/info.md) and
[measured status](reports/STATUS.md).

## Validation

Run `python3 test/run.py` (Python 3.9+ and Icarus Verilog). The dependency-free
suite checks 53 vectors and protocol/reset behaviour. For template Cocotb jobs,
install `test/requirements.txt`, then run `make -C test`. That alternate harness
is supplied for integration and was not run in the current environment.

For exploratory SKY130 mapping:

```sh
python3 scripts/synth.py --liberty /absolute/path/to/sky130_fd_sc_hd__tt_025C_1v80.lib
python3 scripts/synth.py --top chacha20_core --liberty /absolute/path/to/sky130_fd_sc_hd__tt_025C_1v80.lib
python3 scripts/gate_test.py --liberty /absolute/path/to/sky130_fd_sc_hd__tt_025C_1v80.lib
```

## Apply to the official template

This archive is an overlay, not a cloned GitHub repository. Network access to
GitHub was unavailable during creation; official workflow files have not been
invented or replaced. With network access, run:

```sh
python3 scripts/setup_template.py ../ttsky-chacha20
```

This clones https://github.com/TinyTapeout/ttsky-verilog-template into a new
folder, overlays this project, and retains its official GDS/docs workflows.
Use your own GitHub repository as the remote before pushing. Alternatively,
create a repository using GitHub's "Use this template" button and copy src/,
test/, docs/, scripts/, info.yaml and the additional RTL workflow into it.
Do not submit the example project or retain its example test as your validation.

`info.yaml` initially requests **4x2 (eight) tiles**, with a 10 MHz target.
This is conservative routing headroom, NOT a verified passing allocation.
After official GDS/precheck and gate-level tests pass, try 3x2, then 2x2;
retain the smallest allocation that passes all timing/routing/signoff checks.
One and two tiles are not credible allocations for this unchanged baseline
based on the exploratory mapped cell area.

## Provenance and limits

The original chacha20_core.v is preserved from the supplied 1QR source. Only
its text was copied; no architectural optimizations were made. New wrapper,
tests and scripts are included. No license change is imposed on your original
RTL; choose an appropriate project license before publishing it. Preserve the
official template's license for its files.

Only the first 16 bytes of each 64-byte ChaCha20 keystream block are used, as in
the original core. This is not an authenticated-encryption implementation.
SKY130 synthesis is exploratory: the library is from a local OpenROAD test
fixture, not a pinned target-shuttle PDK, and ABC was run without a delay target.
No post-route area, maximum clock, DRC/LVS pass, GDS or minimum tile count is claimed.
