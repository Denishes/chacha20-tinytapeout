"""Test vectors for eight preset keys and fixed nonce/counter."""
import random
from reference import block

NONCE = bytes.fromhex("000000004a00000000000000")
COUNTER = 1


def selected_key(selector):
    # FPGA constants are packed words: 00010203, 04050607, ...
    # The reference expects those words serialized little endian.
    packed = bytes(range(selector * 32, selector * 32 + 32))
    return b"".join(
        packed[i:i + 4][::-1] for i in range(0, 32, 4)
    )


def cases():
    rng = random.Random(20261118)

    for selector in range(8):
        plaintexts = [
            bytes(16),
            bytes([255]) * 16,
            bytes(range(16)),
        ]
        plaintexts += [rng.randbytes(16) for _ in range(5)]

        for plaintext in plaintexts:
            stream = block(selected_key(selector), NONCE, COUNTER)
            expected = bytes(
                p ^ k for p, k in zip(plaintext, stream)
            )
            frame = bytes([selector]) + plaintext
            yield frame, expected