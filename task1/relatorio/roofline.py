# Roofline FP32 (Task 1.2/1.3): AMD EPYC 7742 x2 vs Fujitsu A64FX, valores MEDIDOS
# (fonte: task1/analise_resultados_t1.txt). Gera roofline.pdf/.png para o relatório.
# D23: C1 = divisão escalar 1 thread x 45/7; um só gráfico; eixos log2.
# D24: a OI conta bytes ÚTEIS (sem write-allocate); M1/M3 = bandas efetivas.
import numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import LogLocator, FuncFormatter
plt.rcParams.update({"font.size": 7, "font.family": "serif"})

# tetos de cálculo (GFLOP/s) e de memória (GB/s), de cima para baixo (D16)
M = {
 "AMD 7742 x2": dict(col="#1f5fa8", ls="-",
    C=[("C5", 11269), ("C4", 10536), ("C3", 1589), ("C2", 13.5), ("C1", 6.2)],
    B=[("M4", 299), ("M3", 224), ("M2", 22.6), ("M1", 14)],
    teo=(9216, 409.6),                          # valores_teoricos.txt (D14)
    xlab={"M3": (4, 0.75), "M2": (4, 1), "M1": (2, 1)}),          # x onde fica o rótulo de cada diagonal
 "A64FX": dict(col="#c8501e", ls="--",
    C=[("C5", 6049), ("C4", 3022), ("C3", 379), ("C2", 8.0), ("C1", 0.44)],
    B=[("M4", 813), ("M3", 606), ("M2", 87.7), ("M1", 9.5)],
    teo=(6144, 1024),
    xlab={"M3": (0.25, 0.8), "M2": (0.25, 1), "M1": (0.25, 1)}),
}
XMIN, XMAX, YMIN, YMAX = 1/16, 64, 0.25, 2**15
x = np.logspace(np.log10(XMIN), np.log10(XMAX), 400)
# 3.08 in = 0.88 x coluna IEEE (3.5 in): o LaTeX não reduz a figura e as letras ficam com o tamanho real
fig, ax = plt.subplots(figsize=(3.08, 2.10))  # mesma altura impressa que antes (2.35 x 3.08/3.45)
box = dict(boxstyle="square,pad=0.08", fc="white", ec="none")
for name, d in M.items():
    amd = name.startswith("AMD")
    peak = d["C"][0][1]; bw = d["B"][0][1]
    ax.plot(x, np.minimum(peak, bw * x), color=d["col"], lw=1.6, ls=d["ls"], label=name)
    ax.plot([peak / bw], [peak], marker="o", ms=2.5, color=d["col"])
    # D25: ponto de viragem NOMINAL (pico e banda teóricos), marcador oco
    pt, bt = d["teo"]
    ax.plot([pt / bt], [pt], marker="o", ms=3.2, mfc="white", mec=d["col"], mew=0.9, ls="none", zorder=5)
    for lab, c in d["C"]:
        x0 = max(c / bw, XMIN)
        if lab != "C5": ax.plot([x0, XMAX], [c, c], color=d["col"], lw=0.7, ls=d["ls"], alpha=0.85)
        if amd:   # rótulos à direita; C4 (logo abaixo do C5) e C1 (junto do C2 do A64FX) por baixo da linha
            below = lab in ("C4", "C1")
            ax.text(XMAX*0.96, c*(0.9 if below else 1.1), lab, color=d["col"], fontsize=6,
                    ha="right", va="top" if below else "bottom")
        else:     # C4/C3 em x=16 (no início ficavam em cima do telhado); C4 por baixo da linha
            xt = 16 if lab != "C5" else x0*1.1   # x=16: longe do telhado e das diagonais
            below = lab == "C4"
            ax.text(xt, c*(0.9 if below else 1.1), lab, color=d["col"], fontsize=6, ha="left",
                    va="top" if below else "bottom")
    for lab, b in d["B"][1:]:
        x1 = min(peak / b, XMAX)
        xs = x[x <= x1]
        ax.plot(xs, b * xs, color=d["col"], lw=0.7, ls=d["ls"], alpha=0.85)
        xt, f = d["xlab"][lab]        # f < 1: rótulo um pouco abaixo da linha (longe do telhado)
        ax.text(xt, b * xt * f, lab, color=d["col"], fontsize=6, ha="center", va="center", bbox=box)
# OI do sweep com bytes úteis (D24): referência 45/12 = 3.75; E2 ~21/9 = 2.3
for ai, lab in [(2.33, "E2 ~2.3"), (3.75, "ref. 3.75")]:
    ax.axvline(ai, color="grey", lw=0.6, ls=":")
    ax.text(ai*1.05, 0.3, lab, fontsize=5, color="grey", rotation=90, va="bottom")
ax.set_xscale("log", base=2); ax.set_yscale("log", base=2)
# marcas em números normais (1/4, 1, 4, ... 16384), mais fáceis de ler do que 2^k
def num(v, _):
    return f"1/{round(1/v)}" if v < 1 else f"{v:,.0f}".replace(",", " ")
ax.set_xticks([2.0**k for k in range(-4, 7, 2)])
ax.set_yticks([2.0**k for k in range(-2, 15, 2)])
ax.xaxis.set_major_formatter(FuncFormatter(num)); ax.yaxis.set_major_formatter(FuncFormatter(num))
ax.minorticks_off()
ax.set_xlim(XMIN, XMAX); ax.set_ylim(YMIN, YMAX)
ax.set_xlabel("Operational intensity (FLOP per useful byte)")
ax.set_ylabel("Attainable FP32 GFLOP/s")
ax.grid(True, which="major", lw=0.3, alpha=0.5)
# ridges: ponto cheio = medido, oco = nominal (explicado na legenda da figura no LaTeX,
# para a legenda do gráfico não tapar o telhado do A64FX)
ax.legend(loc="upper left", fontsize=6.5, frameon=True)
fig.tight_layout(pad=0.3)
fig.savefig("roofline.pdf"); fig.savefig("roofline.png", dpi=400)
