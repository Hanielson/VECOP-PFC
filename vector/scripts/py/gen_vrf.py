import random

VLEN = 256
REGS = 32

with open("vrf_contents.txt", "w") as file:
    for i in range(REGS):
        data = random.randint(0, 2**VLEN)
        file.write(f"{hex(data).lstrip('0x').ljust(VLEN//4, '0')}\n")
