import random

MEM_WIDTH = 32
MEM_SIZE  = 512

with open("mem_contents.txt", "w") as file:
    for i in range(MEM_SIZE):
        data = random.randint(0, 2**MEM_WIDTH)
        file.write(f"{hex(data).lstrip('0x').ljust(MEM_WIDTH//4, '0')}\n")
