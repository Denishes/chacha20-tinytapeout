"""Cocotb entry point for the Tiny Tapeout template RTL/GL jobs."""
import cocotb
from cocotb.triggers import Timer
from reference import block, vectors

@cocotb.test()
async def known_and_random_vectors(d):
    d.clk.value=0;d.ena.value=1;d.rst_n.value=0
    d.ui_in.value=0;d.uio_in.value=0
    async def step(cmd=0,data=0):
        d.clk.value=0;d.uio_in.value=cmd;d.ui_in.value=data
        await Timer(50,units='ns')
        d.clk.value=1
        await Timer(50,units='ns')
    await step();await step();d.rst_n.value=1
    assert int(d.uio_oe.value)==0xf0
    await step(2);assert int(d.uio_out.value)&0x80
    await step(8);assert int(d.uio_out.value)==0
    for key,nonce,counter,pt in vectors():
        frame=key+nonce+counter.to_bytes(4,'little')+pt
        for b in frame: await step(1,b)
        assert int(d.uio_out.value)&0x20
        await step(2)
        assert int(d.uio_out.value)&0x10
        for cycles in range(100):
            await step()
            if int(d.uio_out.value)&0x40: break
        else: assert False,'completion timeout'
        expected=bytes(a^b for a,b in zip(pt,block(key,nonce,counter)))
        for b in expected:
            assert int(d.uo_out.value)==b
            await step(4)
        assert not (int(d.uio_out.value)&0x40)
        assert not (int(d.uio_out.value)&0x80)
    await step(1,255);await step(8)
    assert int(d.uio_out.value)==0
