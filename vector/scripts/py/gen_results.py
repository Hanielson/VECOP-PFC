import matplotlib.pyplot as plt
import numpy as np

# -------------------------------------------------------
# YOUR MEASURED RESULTS
# -------------------------------------------------------

tests = [
    "Simple Add",
    "Depend Chain",
    "Load/Store",
    "Arithmetic Chain",
    "SAXPY"
]

instruction_count = np.array([5, 5, 4, 4, 6])
total_cycles = np.array([86, 74, 66, 52, 101])
cpi = np.array([17, 14, 16, 13, 16])

# -------------------------------------------------------
# OPTIONAL COMPARISON DATA
# (Replace with real measurements later)
# -------------------------------------------------------

# Example reference vector cores
reference_cores = {
    "Ideal Pipelined RVV": np.array([2.5, 2.0, 4.0, 2.0, 3.0]),
    "Academic Vector Core": np.array([6.0, 5.5, 7.0, 5.0, 6.5]),
}

# -------------------------------------------------------
# CPI COMPARISON GRAPH
# -------------------------------------------------------

x = np.arange(len(tests))
width = 0.2

plt.figure()

plt.bar(x, cpi, width, label="Your RVV Prototype")

offset = width
for name, ref_cpi in reference_cores.items():
    plt.bar(x + offset, ref_cpi, width, label=name)
    offset += width

plt.xticks(x + width, tests, rotation=30)
plt.ylabel("Average CPI")
plt.title("Vector Kernel CPI Comparison")
plt.legend()
plt.tight_layout()
plt.show()

# -------------------------------------------------------
# TOTAL CYCLES GRAPH
# -------------------------------------------------------

plt.figure()

plt.bar(tests, total_cycles)

plt.ylabel("Total Cycles")
plt.title("Total Execution Cycles per Kernel")
plt.xticks(rotation=30)
plt.tight_layout()
plt.show()

# -------------------------------------------------------
# COMPUTE VS MEMORY CLASSIFICATION
# -------------------------------------------------------

compute_tests = ["Depend Chain", "Arithmetic Chain"]
memory_tests = ["Load/Store"]
mixed_tests = ["Simple Add", "SAXPY"]

compute_cpi = np.mean([cpi[tests.index(t)] for t in compute_tests])
memory_cpi = np.mean([cpi[tests.index(t)] for t in memory_tests])
mixed_cpi = np.mean([cpi[tests.index(t)] for t in mixed_tests])

plt.figure()

categories = ["Compute Bound", "Memory Bound", "Mixed"]
values = [compute_cpi, memory_cpi, mixed_cpi]

plt.bar(categories, values)

plt.ylabel("Average CPI")
plt.title("Workload Characterization")
plt.tight_layout()
plt.show()