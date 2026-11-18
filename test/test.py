"""Tests for the fixed-nonce, fixed-counter Tiny Tapeout wrapper."""
import cocotb
from cocotb.triggers import Timer
from reference import block, vectors

# RTL packed nonce: 96'h000000000000004A00000000
# Reference representation: little-endian bytes within each word.
FIXED_NONCE = bytes.fromhex("000000004a00000000000000")
FIXED_COUNTER = 1


@cocotb.test()
async def known_and_random_vectors(d):
    d.clk.value = 0
    d.ena.value = 1
    d.rst_n.value = 0
    d.ui_in.value = 0
    d.uio_in.value = 0

    async def step(cmd=0, data=0):
        d.clk.value = 0
        d.uio_in.value = cmd
        d.ui_in.value = data
        await Timer(50, units="ns")
        d.clk.value = 1
        await Timer(50, units="ns")

    await step()
    await step()
    d.rst_n.value = 1

    assert int(d.uio_oe.value) == 0xF0

    # Starting before loading a complete frame must fail.
    await step(2)
    assert int(d.uio_out.value) & 0x80

    # Abort clears the error.
    await step(8)
    assert int(d.uio_out.value) == 0

    for index, (key, _, _, plaintext) in enumerate(vectors()):
        # Only key and plaintext are transmitted.
        frame = key + plaintext
        assert len(frame) == 48

        for byte in frame:
            await step(1, byte)

        assert int(d.uio_out.value) & 0x20, "Not ready after 48 bytes"
        assert not (int(d.uio_out.value) & 0x80), "Load error"

        await step(2)
        assert int(d.uio_out.value) & 0x10, "Busy not asserted"

        for _ in range(100):
            await step()
            if int(d.uio_out.value) & 0x40:
                break
        else:
            assert False, "Completion timeout"

        keystream = block(key, FIXED_NONCE, FIXED_COUNTER)
        expected = bytes(
            p ^ k for p, k in zip(plaintext, keystream)
        )

        for byte_index, expected_byte in enumerate(expected):
            actual = int(d.uo_out.value)
            assert actual == expected_byte, (
                f"Vector {index}, byte {byte_index}: "
                f"got {actual:02x}, expected {expected_byte:02x}"
            )
            await step(4)

        assert not (int(d.uio_out.value) & 0x40)
        assert not (int(d.uio_out.value) & 0x80)

    # Abort a partially loaded frame.
    await step(1, 255)
    await step(8)
    assert int(d.uio_out.value) == 0