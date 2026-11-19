import cocotb
from cocotb.triggers import Timer
from preset_vectors import cases


@cocotb.test()
async def preset_keys_and_protocol(d):
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

    # Reject premature start.
    await step(2)
    assert int(d.uio_out.value) & 0x80
    await step(8)
    assert int(d.uio_out.value) == 0

    # Reject invalid key selector.
    await step(1, 8)
    assert int(d.uio_out.value) & 0x80
    await step(8)
    assert int(d.uio_out.value) == 0

    for index, (frame, expected) in enumerate(cases()):
        assert len(frame) == 17

        for byte in frame:
            await step(1, byte)

        status = int(d.uio_out.value)
        assert status & 0x20, "Not ready after 17 bytes"
        assert not (status & 0x80), "Unexpected load error"

        await step(2)
        assert int(d.uio_out.value) & 0x10, "Busy not asserted"

        for _ in range(400):
            await step()
            if int(d.uio_out.value) & 0x40:
                break
        else:
            assert False, "Completion timeout"

        for byte_index, expected_byte in enumerate(expected):
            actual = int(d.uo_out.value)
            assert actual == expected_byte, (
                f"Vector {index}, byte {byte_index}: "
                f"got {actual:02x}, expected {expected_byte:02x}"
            )
            await step(4)

        assert not (int(d.uio_out.value) & 0x40)
        assert not (int(d.uio_out.value) & 0x80)
        assert int(d.uo_out.value) == 0

    # Abort a partial transaction.
    await step(1, 0)
    await step(1, 255)
    await step(8)
    assert int(d.uio_out.value) == 0