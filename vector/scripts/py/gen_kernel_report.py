#!/usr/bin/env python3

##########################################################################################
### OBS: THIS CODE WAS DONE BY CLAUDE CODE BASED ON SOME LOGGING EXAMPLE I GAVE HIM... ###
##########################################################################################

"""
FPGA Vector Instruction Cycle Table Generator
=============================================
Lê um arquivo CSV no formato INSTRUCTION,SEW,LMUL,CYCLES e gera
quatro tabelas (uma por LMUL), com SEW nas colunas e instruções nas linhas.
Cada célula exibe: CYCLES / OCORRÊNCIAS
Última linha: CPI médio por SEW.

Uso:
    python cycle_tables.py <arquivo.log>
    python cycle_tables.py                  # usa 'data.log' por padrão
"""

import sys
import csv
import re
from collections import defaultdict
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.gridspec import GridSpec
import numpy as np

# =============================================================================
# CONFIG
# =============================================================================
DEFAULT_FILE = "data.log"

# Paleta de cor por instrução (cycling se necessário)
PALETTE = [
    "#4C72B0", "#DD8452", "#55A868", "#C44E52",
    "#8172B2", "#937860", "#DA8BC3", "#8C8C8C",
    "#CCB974", "#64B5CD", "#B07A4C", "#72B04C",
]

# Cores de tema
C_HEADER_BG   = "#2B3A55"
C_HEADER_FG   = "#FFFFFF"
C_LMUL_BG     = "#1A2438"
C_LMUL_FG     = "#E8F0FF"
C_SEW_BG      = "#3D5278"
C_SEW_FG      = "#FFFFFF"
C_INST_BG     = "#EEF2FA"
C_INST_FG     = "#1A2438"
C_CPI_BG      = "#FFE8A3"
C_CPI_FG      = "#5A3A00"
C_CELL_BG     = "#FFFFFF"
C_CELL_FG     = "#222222"
C_ALT_BG      = "#F4F7FD"
C_GRID        = "#C8D4EC"
C_ZERO_FG     = "#AAAAAA"

# =============================================================================
# PARSING
# =============================================================================

def parse_file(path):
    """
    Retorna dict: data[lmul][sew][instruction] = (total_cycles, occurrences)
    """
    data = defaultdict(lambda: defaultdict(lambda: defaultdict(lambda: [0, 0])))
    lmuls = set()
    sews  = set()
    insts = set()

    with open(path, newline="") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(",")
            if len(parts) != 4:
                continue
            inst, sew, lmul, cycles = parts[0].strip(), int(parts[1]), int(parts[2]), int(parts[3])
            data[lmul][sew][inst][0] += cycles
            data[lmul][sew][inst][1] += 1
            lmuls.add(lmul)
            sews.add(sew)
            insts.add(inst)

    return data, sorted(lmuls), sorted(sews), sorted(insts)


# =============================================================================
# TABLE DRAWING
# =============================================================================

def draw_table(ax, lmul, sews, insts, data_lmul, inst_color_map):
    """
    Draws a single LMUL table onto the given axes.
    Rows = instructions + CPI row. Columns = SEW values.
    """
    ax.axis("off")
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)

    n_sew  = len(sews)
    n_inst = len(insts)
    n_rows = n_inst + 1  # +1 for CPI row

    col_inst_w = 0.22        # width of instruction name column
    col_data_w = (1.0 - col_inst_w) / n_sew
    row_header_h = 0.12      # SEW header row height
    row_data_h   = (1.0 - row_header_h) / n_rows

    def cell_rect(col, row):
        """col=0 → inst name col; col=1..n_sew → data cols. row=0 → header."""
        if col == 0:
            x = 0
            w = col_inst_w
        else:
            x = col_inst_w + (col - 1) * col_data_w
            w = col_data_w
        if row == 0:
            y = 1.0 - row_header_h
            h = row_header_h
        else:
            y = 1.0 - row_header_h - row * row_data_h
            h = row_data_h
        return x, y, w, h

    def draw_cell(col, row, text, bg, fg, fontsize=8, bold=False, alpha=1.0,
                  ha="center", valign="center", accent_color=None):
        x, y, w, h = cell_rect(col, row)
        rect = patches.FancyBboxPatch(
            (x + 0.002, y + 0.002), w - 0.004, h - 0.004,
            boxstyle="square,pad=0",
            facecolor=bg, edgecolor=C_GRID, linewidth=0.6, alpha=alpha,
            transform=ax.transAxes, clip_on=False
        )
        ax.add_patch(rect)

        # Accent stripe on left edge for instruction rows
        if accent_color:
            stripe = patches.FancyBboxPatch(
                (x + 0.002, y + 0.002), 0.012, h - 0.004,
                boxstyle="square,pad=0",
                facecolor=accent_color, edgecolor="none",
                transform=ax.transAxes, clip_on=False
            )
            ax.add_patch(stripe)

        ax.text(
            x + w / 2, y + h / 2, text,
            ha=ha, va=valign,
            fontsize=fontsize,
            fontweight="bold" if bold else "normal",
            color=fg,
            transform=ax.transAxes,
            clip_on=False,
            wrap=False,
        )

    # --- LMUL header (top-left corner cell) ---
    draw_cell(0, 0, f"LMUL = {lmul}", C_LMUL_BG, C_LMUL_FG, fontsize=9, bold=True)

    # --- SEW column headers ---
    for ci, sew in enumerate(sews):
        draw_cell(ci + 1, 0, f"SEW={sew}", C_SEW_BG, C_SEW_FG, fontsize=8, bold=True)

    # --- Instruction rows ---
    for ri, inst in enumerate(insts):
        row_idx = ri + 1
        bg = C_INST_BG if ri % 2 == 0 else C_ALT_BG
        accent = inst_color_map[inst]
        draw_cell(0, row_idx, inst, bg, C_INST_FG, fontsize=7.5, bold=True,
                  ha="center", accent_color=accent)

        for ci, sew in enumerate(sews):
            entry = data_lmul.get(sew, {}).get(inst)
            if entry and entry[1] > 0:
                cycles, occ = entry
                text = f"{cycles} / {occ}"
                fg   = C_CELL_FG
            else:
                text = "— / —"
                fg   = C_ZERO_FG
            draw_cell(ci + 1, row_idx, text, bg, fg, fontsize=7.5)

    # --- CPI row ---
    cpi_row = n_inst + 1
    draw_cell(0, cpi_row, "Avg CPI", C_CPI_BG, C_CPI_FG, fontsize=7.5, bold=True)

    for ci, sew in enumerate(sews):
        sew_data = data_lmul.get(sew, {})
        total_weighted = 0
        total_insts    = 0
        for inst, (cyc, occ) in sew_data.items():
            total_weighted += cyc  # cyc already = sum of cycles (cyc_per_inst * occ)
            total_insts    += occ
        if total_insts > 0:
            cpi = total_weighted / total_insts
            text = f"{cpi:.2f}"
        else:
            text = "—"
        draw_cell(ci + 1, cpi_row, text, C_CPI_BG, C_CPI_FG, fontsize=8, bold=True)


# =============================================================================
# MAIN
# =============================================================================

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_FILE

    print(f"Lendo arquivo: {path}")
    data, lmuls, sews, insts = parse_file(path)

    # Map each instruction to a stable color
    inst_color_map = {inst: PALETTE[i % len(PALETTE)] for i, inst in enumerate(insts)}

    n_lmul = len(lmuls)
    n_cols = 2
    n_rows_grid = (n_lmul + n_cols - 1) // n_cols

    fig_w = 7 * n_cols
    fig_h = (2.2 + 0.38 * len(insts)) * n_rows_grid + 1.4  # +1.4 for legend

    fig = plt.figure(figsize=(fig_w, fig_h), facecolor="#F0F4FC")
    fig.suptitle(
        "Medições de Performance por Kernel - VLOAD/VSTORE\n(Ciclos/Ocorrências)",
        fontsize=14, fontweight="bold", color=C_HEADER_BG, y=1.00
    )

    gs = GridSpec(
        n_rows_grid + 1, n_cols,
        figure=fig,
        height_ratios=[1.0] * n_rows_grid + [0.18],
        hspace=0.12,
        wspace=0.06,
        left=0.03, right=0.97,
        top=0.94, bottom=0.04,
    )

    for idx, lmul in enumerate(lmuls):
        r, c = divmod(idx, n_cols)
        ax = fig.add_subplot(gs[r, c])
        draw_table(ax, lmul, sews, insts, data[lmul], inst_color_map)

    # --- Shared legend ---
    legend_ax = fig.add_subplot(gs[n_rows_grid, :])
    legend_ax.axis("off")
    handles = [
        patches.Patch(facecolor=inst_color_map[inst], edgecolor="#888", label=inst)
        for inst in insts
    ]
    legend_ax.legend(
        handles=handles,
        loc="center",
        ncol=min(len(insts), 8),
        fontsize=9,
        frameon=True,
        framealpha=0.85,
        edgecolor=C_GRID,
        title="Instruções",
        title_fontsize=9,
        borderpad=0.8,
        columnspacing=1.2,
    )

    out_png = path.rsplit(".", 1)[0] + "_tables.png"
    out_pdf = path.rsplit(".", 1)[0] + "_tables.pdf"
    plt.savefig(out_png, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor())
    print(f"Salvo: {out_png}")
    plt.show()


if __name__ == "__main__":
    main()