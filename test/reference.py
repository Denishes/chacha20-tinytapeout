"""Independent RFC 8439 ChaCha20 block reference, conventional byte ordering."""
import struct

def block(key, nonce, counter):
    s=list(struct.unpack('<4I',b'expand 32-byte k')+struct.unpack('<8I',key)
           +(counter,)+struct.unpack('<3I',nonce))
    x=s.copy()
    def qr(a,b,c,d):
        def rot(v,n): return ((v<<n)|(v>>(32-n))) & 0xffffffff
        x[a]=(x[a]+x[b])&0xffffffff; x[d]=rot(x[d]^x[a],16)
        x[c]=(x[c]+x[d])&0xffffffff; x[b]=rot(x[b]^x[c],12)
        x[a]=(x[a]+x[b])&0xffffffff; x[d]=rot(x[d]^x[a],8)
        x[c]=(x[c]+x[d])&0xffffffff; x[b]=rot(x[b]^x[c],7)
    for _ in range(10):
        for q in [(0,4,8,12),(1,5,9,13),(2,6,10,14),(3,7,11,15),
                  (0,5,10,15),(1,6,11,12),(2,7,8,13),(3,4,9,14)]: qr(*q)
    return struct.pack('<16I',*[(a+b)&0xffffffff for a,b in zip(x,s)])

def vectors():
    import random
    # RFC 8439 section 2.3.2 block function, first 16 bytes.
    key=bytes(range(32)); nonce=bytes.fromhex('000000090000004a00000000')
    assert block(key,nonce,1)[:16].hex()=='10f1e7e4d13b5915500fdd1fa32071c4'
    assert block(bytes(32),bytes(12),0)[:16].hex()=='76b8e0ada0f13d90405d6ae55386bd28'
    yield key,nonce,1,bytes(16)
    yield bytes(32),bytes(12),0,bytes(16)
    yield bytes([255])*32,bytes([255])*12,0xffffffff,bytes([255])*16
    r=random.Random(20261115)
    for _ in range(50):
        yield r.randbytes(32),r.randbytes(12),r.getrandbits(32),r.randbytes(16)
