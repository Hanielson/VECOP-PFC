#!/usr/bin/env python3

##########################################################################################
### OBS: THIS CODE WAS DONE BY CLAUDE CODE BASED ON SOME LOGGING EXAMPLE I GAVE HIM... ###
##########################################################################################

"""
FPGA Utilization Stacked Bar Chart Generator
"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

# =============================================================================
# DADOS DE UTILIZAÇÃO
# =============================================================================
hierarchy = {
    "VECOP": {
        "luts": 5079, "regs": 1722, "f7mux": 117, "bram": 6.5,
        "children": {
            "V-ALU": {
                "luts": 4037, "regs": 479, "f7mux": 21, "bram": 0,
                "children": {
                    "V-ALU SEQ TOP": {"luts": 625,  "regs": 193, "f7mux": 16, "bram": 0},
                    "V-INT":         {"luts": 1716, "regs": 148, "f7mux": 5,  "bram": 0},
                    "V-MASK":        {"luts": 1427, "regs": 138, "f7mux": 0,  "bram": 0},
                },
            },
            "V-DISPATCHER": {
                "luts": 355, "regs": 777, "f7mux": 96, "bram": 0,
                "children": {
                    "V-BACKEND": {"luts": 148, "regs": 3,   "f7mux": 0,  "bram": 0},
                    "V-IQ":      {"luts": 207, "regs": 774, "f7mux": 96, "bram": 0},
                },
            },
            "V-LSU": {"luts": 406,  "regs": 172, "f7mux": 0, "bram": 0},
            "V-RF":  {"luts": 16,   "regs": 256, "f7mux": 0, "bram": 6},
        }
    }
}

DEVICE_CAPS = {
    "luts":  20800,
    "regs":  41600,
    "f7mux": 16300,
    "bram":  50,
}

RESOURCE_LABELS = {
    "luts":  "LUTs (MAX: 20 800)",
    "regs":  "Registers (MAX: 41 600)",
    "f7mux": "Muxes (MAX: 16 300)",
    "bram":  "Block RAM (MAX: 50)",
}

PALETTE = [
    "#4C72B0", "#DD8452", "#55A868", "#C44E52",
    "#8172B2", "#937860", "#DA8BC3", "#8C8C8C",
    "#CCB974", "#64B5CD",
]

# =============================================================================
# FUNÇÕES AUXILIARES
# =============================================================================

def collect_leaf_segments(module_dict, resource_key):
    segments = []
    children = module_dict.get("children", {})
    parent_val = module_dict.get(resource_key, 0)

    if not children:
        return [(None, parent_val)]

    children_sum = sum(c.get(resource_key, 0) for c in children.values())
    remainder = parent_val - children_sum

    for child_label, child_data in children.items():
        child_children = child_data.get("children", {})
        if child_children:
            sub_segs = collect_leaf_segments(child_data, resource_key)
            segments.extend(sub_segs)
        else:
            segments.append((child_label, child_data.get(resource_key, 0)))

    if remainder > 0:
        segments.append(("(outros)", remainder))

    return segments


def build_plot_data(hierarchy, resource_key):
    root_name, root_data = next(iter(hierarchy.items()))
    children = root_data.get("children", {})

    bar_labels = list(children.keys())
    total_per_bar = [children[k].get(resource_key, 0) for k in bar_labels]

    all_seg_labels = []
    seg_data = {}

    for bar_lbl, bar_data in children.items():
        segs = collect_leaf_segments(bar_data, resource_key)
        for seg_lbl, seg_val in segs:
            effective_lbl = seg_lbl if seg_lbl else bar_lbl
            if effective_lbl not in all_seg_labels:
                all_seg_labels.append(effective_lbl)
            if effective_lbl not in seg_data:
                seg_data[effective_lbl] = {b: 0 for b in bar_labels}
            seg_data[effective_lbl][bar_lbl] = seg_val

    return bar_labels, all_seg_labels, seg_data, total_per_bar


# =============================================================================
# Collect all unique segment labels across ALL resources (for shared legend)
# =============================================================================
all_global_seg_labels = []
for res_key in RESOURCE_LABELS:
    _, seg_labels, _, _ = build_plot_data(hierarchy, res_key)
    for lbl in seg_labels:
        if lbl not in all_global_seg_labels:
            all_global_seg_labels.append(lbl)

# Assign a stable color to each segment label
seg_color_map = {lbl: PALETTE[i % len(PALETTE)] for i, lbl in enumerate(all_global_seg_labels)}

# =============================================================================
# GERAÇÃO DOS GRÁFICOS
# =============================================================================

# Layout: charts on top, shared legend on bottom
# Use gridspec: 2 rows — row 0 = charts (tall), row 1 = legend (short)
fig = plt.figure(figsize=(20, 9))
fig.suptitle("Tabelas de Utilização de Recursos - VECOP",
             fontsize=16, fontweight="bold", y=0.98)

gs = fig.add_gridspec(
    2, 4,
    height_ratios=[10, 1],   # charts tall, legend row thin
    hspace=0.55,              # vertical gap between chart and legend row
    wspace=0.50,              # horizontal gap between charts
    left=0.06, right=0.97,
    top=0.90, bottom=0.05,
)

axes = [fig.add_subplot(gs[0, i]) for i in range(4)]

for ax, (res_key, res_label) in zip(axes, RESOURCE_LABELS.items()):
    bar_labels, seg_labels, seg_data, totals = build_plot_data(hierarchy, res_key)
    cap = DEVICE_CAPS[res_key]

    x = np.arange(len(bar_labels))
    bar_width = 0.55
    bottoms = np.zeros(len(bar_labels))

    for seg_lbl in seg_labels:
        color = seg_color_map[seg_lbl]
        vals = np.array([seg_data[seg_lbl][b] for b in bar_labels], dtype=float)

        ax.bar(x, vals, bar_width, bottom=bottoms, color=color,
               edgecolor="white", linewidth=0.6)

        bottoms += vals

    # Value labels on top of each bar
    for xi, (tot, bot) in enumerate(zip(totals, bottoms)):
        if tot > 0:
            ax.text(xi, bot, f"{tot:g}",
                    ha="center", va="bottom", fontsize=8.5, fontweight="bold",
                    color="#222", clip_on=False)

    # Y scale: 1.5x of max utilization
    max_util = max(totals) if max(totals) > 0 else 1
    y_max = max_util * 1.5

    # Device cap line (only if within scale)
    if cap <= y_max:
        ax.axhline(cap, color="red", linestyle="--", linewidth=1.2, alpha=0.7)
        ax.text(len(bar_labels) - 0.5 + 0.3, cap, f"Cap: {cap:g}",
                va="center", ha="left", fontsize=7, color="red")

    ax.set_xticks(x)
    ax.set_xticklabels(bar_labels, fontsize=8.5, ha="center")
    ax.set_ylim(0, y_max)
    ax.set_ylabel("Quantidade", fontsize=9)
    ax.set_title(res_label, fontsize=10, fontweight="bold", pad=10)
    ax.yaxis.grid(True, linestyle=":", alpha=0.5)
    ax.set_axisbelow(True)
    ax.spines[["top", "right"]].set_visible(False)

    # Secondary Y axis: % of device capacity
    ax2 = ax.twinx()
    ax2.set_ylim(0, y_max)
    ax2.yaxis.set_major_formatter(
        plt.FuncFormatter(lambda v, _, cap=cap: f"{100*v/cap:.0f}%")
    )
    ax2.tick_params(axis="y", labelsize=7.5)
    ax2.spines[["top", "left", "bottom"]].set_visible(False)

# =============================================================================
# SHARED LEGEND — spans all 4 columns in the bottom row
# =============================================================================
legend_ax = fig.add_subplot(gs[1, :])
legend_ax.axis("off")

legend_patches = [
    mpatches.Patch(color=seg_color_map[lbl], label=lbl)
    for lbl in all_global_seg_labels
]

legend_ax.legend(
    handles=legend_patches,
    loc="center",
    ncol=len(all_global_seg_labels),   # all items in one row
    fontsize=9,
    frameon=True,
    framealpha=0.6,
    edgecolor="#ccc",
    title="Módulos",
    title_fontsize=9,
    borderpad=0.8,
    columnspacing=1.2,
)

plt.savefig("fpga_utilization.png",
            dpi=150, bbox_inches="tight", facecolor="white")
print("Gráficos salvos.")