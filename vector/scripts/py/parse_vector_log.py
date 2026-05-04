#!/usr/bin/env python3

##########################################################################################
### OBS: THIS CODE WAS DONE BY CLAUDE CODE BASED ON SOME LOGGING EXAMPLE I GAVE HIM... ###
##########################################################################################

"""
Parses a vector instruction test log and generates a PNG report
with 4 tables in a 2x2 grid (one per LMUL value),
rows = instructions, columns = VSEW.
"""

import sys
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch
import numpy as np

# ── Configuration ─────────────────────────────────────────────────────────────
LMUL_VALUES = [1, 2, 4, 8]
VSEW_VALUES  = [8, 16, 32]

# ── Colors (light theme) ──────────────────────────────────────────────────────
BG          = "#f4f6fa"
SURFACE     = "#ffffff"
HEADER_BG   = "#e8ecf5"
BORDER      = "#c9d0e0"
TEXT        = "#1a1f2e"
TEXT_DIM    = "#7a84a0"
ACCENT      = "#1d5fa8"

PASS_BG     = "#edfaf3"
PASS_FG     = "#166534"
FAIL_BG     = "#fff1f1"
FAIL_FG     = "#991b1b"
NA_FG       = "#9aa0b5"
NA_BG       = "#f8f9fc"

# ── Parser ────────────────────────────────────────────────────────────────────
def parse_log(path: str):
    # data[lmul][instr][vsew] = (status, count)
    # status: 'PASSED' if all passed, else 'FAILED'
    # count: total number of entries for that combination
    raw   = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    instructions_order = []

    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(",")
            if len(parts) < 6:
                continue
            instr, vsew_s, lmul_s = parts[0], parts[1], parts[2]
            status = parts[5].upper()
            try:
                vsew, lmul = int(vsew_s), int(lmul_s)
            except ValueError:
                continue
            if instr not in instructions_order:
                instructions_order.append(instr)
            raw[lmul][instr][vsew].append(status)

    # Aggregate: any FAILED entry → FAILED
    data = defaultdict(lambda: defaultdict(dict))
    for lmul, instrs in raw.items():
        for instr, vsews in instrs.items():
            for vsew, statuses in vsews.items():
                count      = len(statuses)
                agg_status = "PASSED" if all("PASS" in s for s in statuses) else "FAILED"
                data[lmul][instr][vsew] = (agg_status, count)

    return data, instructions_order

# ── Draw one table into an Axes ───────────────────────────────────────────────
def draw_table(ax, lmul, lmul_data, instructions):
    ax.set_facecolor(SURFACE)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")

    n_rows = len(instructions)
    n_cols = len(VSEW_VALUES)

    left_w   = 0.34
    col_w    = (1.0 - left_w) / n_cols
    header_h = 0.08
    row_h    = (1.0 - header_h * 2) / n_rows if n_rows else 0.05

    # ── Title bar ──────────────────────────────────────────────────────────
    rect = plt.Rectangle((0, 1 - header_h), 1, header_h,
                          facecolor=ACCENT, linewidth=0,
                          transform=ax.transAxes)
    ax.add_patch(rect)
    ax.text(0.014, 1 - header_h / 2, f"LMUL = {lmul}",
            color="white", fontsize=9, fontweight="bold",
            va="center", ha="left", transform=ax.transAxes,
            fontfamily="monospace")

    # ── Column headers (VSEW) ──────────────────────────────────────────────
    header_top = 1 - header_h
    for ci, vsew in enumerate(VSEW_VALUES):
        x = left_w + ci * col_w
        rect = plt.Rectangle((x, header_top - header_h), col_w, header_h,
                              facecolor=HEADER_BG, edgecolor=BORDER,
                              linewidth=0.6, transform=ax.transAxes)
        ax.add_patch(rect)
        ax.text(x + col_w / 2, header_top - header_h / 2,
                f"VSEW = {vsew}",
                color=ACCENT, fontsize=7.5, fontweight="bold",
                va="center", ha="center",
                transform=ax.transAxes, fontfamily="monospace")

    # "Instrução" header cell
    rect = plt.Rectangle((0, header_top - header_h), left_w, header_h,
                          facecolor=HEADER_BG, edgecolor=BORDER,
                          linewidth=0.6, transform=ax.transAxes)
    ax.add_patch(rect)
    ax.text(0.014, header_top - header_h / 2, "Instrução",
            color=ACCENT, fontsize=7.5, fontweight="bold",
            va="center", ha="left",
            transform=ax.transAxes, fontfamily="monospace")

    # ── Data rows ──────────────────────────────────────────────────────────
    data_top = header_top - header_h

    for ri, instr in enumerate(instructions):
        y_top  = data_top - ri * row_h
        row_bg = SURFACE if ri % 2 == 0 else "#f0f3fa"

        # Instruction name cell
        rect = plt.Rectangle((0, y_top - row_h), left_w, row_h,
                              facecolor=row_bg, edgecolor=BORDER,
                              linewidth=0.4, transform=ax.transAxes)
        ax.add_patch(rect)
        ax.text(0.014, y_top - row_h / 2, instr,
                color=TEXT, fontsize=7.2, va="center", ha="left",
                transform=ax.transAxes, fontfamily="monospace")

        # Status cells
        for ci, vsew in enumerate(VSEW_VALUES):
            x   = left_w + ci * col_w
            val = lmul_data.get(instr, {}).get(vsew, None)

            if val is None:
                cell_bg    = NA_BG
                label      = "—"
                label_color = NA_FG
                count_label = ""
            else:
                status, count = val
                count_label   = f"({count})"
                if "PASS" in status:
                    cell_bg, label, label_color = PASS_BG, "PASS", PASS_FG
                else:
                    cell_bg, label, label_color = FAIL_BG, "FAIL", FAIL_FG

            rect = plt.Rectangle((x, y_top - row_h), col_w, row_h,
                                  facecolor=cell_bg, edgecolor=BORDER,
                                  linewidth=0.4, transform=ax.transAxes)
            ax.add_patch(rect)

            if count_label:
                # Status on top, count below
                ax.text(x + col_w / 2, y_top - row_h * 0.36, label,
                        color=label_color, fontsize=7.2, fontweight="bold",
                        va="center", ha="center",
                        transform=ax.transAxes, fontfamily="monospace")
                ax.text(x + col_w / 2, y_top - row_h * 0.70, count_label,
                        color=label_color, fontsize=6.0,
                        va="center", ha="center", alpha=0.75,
                        transform=ax.transAxes, fontfamily="monospace")
            else:
                ax.text(x + col_w / 2, y_top - row_h / 2, label,
                        color=label_color, fontsize=7.5, fontweight="bold",
                        va="center", ha="center",
                        transform=ax.transAxes, fontfamily="monospace")

# ── Main figure builder ───────────────────────────────────────────────────────
def build_png(data, instructions_order, output_path: str):
    n_instrs = len(instructions_order)

    # 2x2 grid — each cell holds one LMUL table
    row_pt      = 0.32          # inches per instruction row
    header_extra = 1.4          # title bars + col-headers per table
    table_h     = n_instrs * row_pt + header_extra
    table_w     = 9.0           # inches per table column

    fig_w = table_w * 2 + 1.2   # two columns + padding
    fig_h = table_h * 2 + 1.8   # two rows + space for main title/legend

    fig = plt.figure(figsize=(fig_w, fig_h), facecolor=BG)

    # ── Main title ──────────────────────────────────────────────────────────
    fig.text(0.5, 1 - 0.35 / fig_h,
             "VECOP - Relatório de Simulação - VINT",
             color=TEXT, fontsize=16, fontweight="bold",
             ha="center", va="top", fontfamily="monospace")
    fig.text(0.5, 1 - 0.78 / fig_h,
             "Instrução × VSEW  ·  agrupado por LMUL",
             color=TEXT_DIM, fontsize=9, ha="center", va="top",
             fontfamily="monospace")

    # ── 2×2 grid of axes ────────────────────────────────────────────────────
    left_pad   = 0.04
    right_pad  = 0.04
    top_offset = 1.3 / fig_h      # reserved for title
    bot_pad    = 0.25 / fig_h
    h_gap      = 0.018
    v_gap      = 0.022

    usable_w = 1.0 - left_pad - right_pad
    usable_h = 1.0 - top_offset - bot_pad

    ax_w = (usable_w - h_gap) / 2
    ax_h = (usable_h - v_gap) / 2

    positions = [
        (0, 1),   # LMUL=1 → top-left
        (1, 1),   # LMUL=2 → top-right
        (0, 0),   # LMUL=4 → bottom-left
        (1, 0),   # LMUL=8 → bottom-right
    ]

    for lmul, (col, row) in zip(LMUL_VALUES, positions):
        x = left_pad + col * (ax_w + h_gap)
        y = bot_pad  + row * (ax_h + v_gap)
        ax = fig.add_axes([x, y, ax_w, ax_h])
        draw_table(ax, lmul, data.get(lmul, {}), instructions_order)

    # ── Legend ──────────────────────────────────────────────────────────────
    leg_ax = fig.add_axes([0.0, 1 - top_offset, 1.0, top_offset * 0.32])
    leg_ax.set_facecolor(BG)
    leg_ax.axis("off")
    legend_items = [
        mpatches.Patch(facecolor=PASS_BG, edgecolor=PASS_FG, linewidth=1.2, label="PASS"),
        mpatches.Patch(facecolor=FAIL_BG, edgecolor=FAIL_FG, linewidth=1.2, label="FAIL"),
        mpatches.Patch(facecolor=NA_BG,   edgecolor=NA_FG,   linewidth=1.2, label="Sem dados"),
    ]
    leg = leg_ax.legend(
        handles=legend_items, loc="center", ncol=3,
        frameon=False, fontsize=8.5,
        labelcolor=[PASS_FG, FAIL_FG, NA_FG],
        handlelength=1.4, handleheight=0.9,
        borderpad=0, columnspacing=1.8
    )
    for text in leg.get_texts():
        text.set_fontfamily("monospace")

    fig.savefig(output_path, dpi=160, bbox_inches="tight",
                facecolor=BG, edgecolor="none")
    plt.close(fig)
    print(f"PNG gerado: {output_path}")

# ── Entry point ───────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print("Uso: python parse_log.py <arquivo.log> [saida.png]")
        sys.exit(1)

    log_path    = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else "relatorio.png"

    if not os.path.isfile(log_path):
        print(f"Erro: arquivo não encontrado – {log_path}")
        sys.exit(1)

    data, instructions_order = parse_log(log_path)
    build_png(data, instructions_order, output_path)

if __name__ == "__main__":
    main()