# -*- coding: utf-8 -*-
"""
Roofline da Task 1 (1.2 e 1.3) - AMD EPYC 7742 x2 (no x86) e Fujitsu A64FX (no ARM).

Uso:   python3 roofline.py            (gera as figuras em ingles e em portugues)

O QUE ESTE SCRIPT FAZ
  1. Guarda numa tabela (dicionario MAQ) os valores ja registados em
     task1/analise_resultados_t1.txt, task1/valores_teoricos.txt e decisoes.txt.
     NENHUM valor e calculado de novo aqui, exceto os pontos de viragem (ridge),
     que sao so a divisao pico / banda.
  2. Desenha o modelo roofline em escala log-log (base 2), como sugere o
     Apendice A do artigo de Williams et al. (2008):
        desempenho atingivel(AI) = min(pico, banda x AI)
     AI = intensidade aritmetica (FLOP por byte de memoria).
  3. Fig. 1 (1.2): as duas maquinas no MESMO grafico; linha cheia = medido,
     tracejado = teorico (D14).
     Fig. 2 (1.3): um painel por maquina, mesmos eixos, com os tetos C1-C5
     (calculo, horizontais) e M1-M4 (memoria, diagonais) da D16.
     Como no artigo, um teto de calculo comeca onde toca o telhado de memoria
     e um teto de memoria acaba onde toca o telhado de calculo.

As escolhas que mudam o resultado estao nas variaveis ESCOLHA_* (ver D21).
"""
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ---------------------------------------------------------------------------
# ESCOLHAS (decisao D21, Rodrigo)
# ---------------------------------------------------------------------------
ESCOLHA_C1 = "sdiv_1c"    # "sdiv_1c" (div. escalar 1 thread) | "div_all" | "sdiv_all"
ESCOLHA_TELHADO = "M4"    # banda do telhado medido: "M4" ou "M3"

# ---------------------------------------------------------------------------
# DADOS (GFLOP/s e GB/s, FP32, no inteiro). Fonte de cada valor ao lado.
# ---------------------------------------------------------------------------
MAQ = {
    "AMD": {
        "nome": "AMD EPYC 7742 x2 (128 c)",
        "cor": "#1f5fa8",
        "pico_teo": 9216.0,    # valores_teoricos.txt: 128 x 2.25 GHz x 32
        "banda_teo": 409.6,    # valores_teoricos.txt: 16 canais DDR4-3200
        # calculo (analise sec. 1, peak.c, mediana de 10 reps)
        "C5": 11269.0,         # fma, 128 cores (pico medido)
        "C4": 10536.0,         # muladd, 128 cores (SIMD sem FMA)
        "C3": 1589.0,          # sfma, 128 cores (escalar, todos os cores)
        "C2": 13.5,            # sfma, 1 core (1 thread, escalar)
        "div_all": 988.0,      # div SIMD, 128 cores
        "sdiv_all": 123.0,     # div escalar, 128 cores
        "sdiv_1c": 6.2,        # D23: div escalar 1 core (0.9635) x 45/7 FLOP por divisao
        # memoria (analise sec. 3.4 e 6; D18, D20)
        "M4": 299.0,           # sem write-allocate (224 x 32/24; Copy NT 298)
        "M3": 224.0,           # STREAM Triad (com write-allocate)
        "M2": 22.6,            # NUMA errado (numactl --membind=0)
        "M1": 14.0,            # stride (224/16, calculado, D16)
    },
    "A64FX": {
        "nome": "Fujitsu A64FX (48 c)",
        "cor": "#d9661f",
        "pico_teo": 6144.0,    # 48 x 2.0 GHz x 64
        "banda_teo": 1024.0,   # 4 x 256 GB/s HBM2
        "C5": 6049.0,
        "C4": 3022.0,
        "C3": 379.0,
        "C2": 8.0,
        "div_all": 15.4,
        "sdiv_all": 3.3,
        "sdiv_1c": 0.44,       # D23: div escalar 1 core (0.06858) x 45/7
        "M4": 813.0,           # STREAM zfill (sem write-allocate)
        "M3": 606.0,           # STREAM openmp (com write-allocate)
        "M2": 87.7,            # NUMA errado (membind0)
        "M1": 9.5,             # stride (606/64, calculado, D16)
    },
}

# ---------------------------------------------------------------------------
# TEXTOS (EN para o relatorio, PT para estudo)
# ---------------------------------------------------------------------------
TXT = {
    "en": {
        "xl": "Operational intensity (FLOP/byte)",
        "yl": "Attainable performance (GFLOP/s, FP32)",
        "med": "measured", "teo": "theoretical",
        "t1": "Single-precision roofline: AMD EPYC 7742 x2 vs A64FX (whole node)",
        "t2": "Ceilings for the varcoef Jacobi (D16)",
        "C5": "C5 SIMD+FMA (peak)", "C4": "C4 SIMD, no FMA",
        "C3": "C3 all cores, scalar", "C2": "C2 1 thread, scalar",
        "C1": {"sdiv_1c": "C1 7 div/point, scalar, 1 thread",
               "div_all": "C1 SIMD div, all cores",
               "sdiv_all": "C1 scalar div, all cores"},
        "M4": "M4 no write-allocate", "M3": "M3 write-allocate",
        "M2": "M2 wrong NUMA", "M1": "M1 strided",
        "ridge": "ridge",
    },
    "pt": {
        "xl": "Intensidade operacional (FLOP/byte)",
        "yl": "Desempenho atingível (GFLOP/s, FP32)",
        "med": "medido", "teo": "teórico",
        "t1": "Roofline em precisão simples: AMD EPYC 7742 x2 vs A64FX (nó inteiro)",
        "t2": "Tetos para o Jacobi varcoef (D16)",
        "C5": "C5 SIMD+FMA (pico)", "C4": "C4 SIMD sem FMA",
        "C3": "C3 todos os cores, escalar", "C2": "C2 1 thread, escalar",
        "C1": {"sdiv_1c": "C1 7 div/ponto, escalar, 1 thread",
               "div_all": "C1 divisão SIMD, todos os cores",
               "sdiv_all": "C1 divisão escalar, todos os cores"},
        "M4": "M4 sem write-allocate", "M3": "M3 com write-allocate",
        "M2": "M2 NUMA errado", "M1": "M1 com stride",
        "ridge": "ridge",
    },
}

AI = np.logspace(-9, 9, 2000, base=2)          # eixo x: 1/512 ... 512 FLOP/B
XLIM = (2 ** -9, 2 ** 9)
YLIM = (2 ** -5, 2 ** 15)
CAIXA = dict(boxstyle="square,pad=0.1", fc="white", ec="none", alpha=0.85)  # fundo dos rotulos


def fmt(v):
    """Numero legivel: 11 269 / 13.5 / 0.07"""
    if v >= 1000:
        return f"{v:,.0f}".replace(",", " ")
    if v >= 100:
        return f"{v:.0f}"
    if v >= 1:
        return f"{v:.3g}"
    return f"{v:.2g}"


def eixos(ax, t, xlim=XLIM, ylim=YLIM):
    ax.set_xscale("log", base=2)
    ax.set_yscale("log", base=2)
    ax.set_xlim(*xlim)
    ax.set_ylim(*ylim)
    xt = [2.0 ** k for k in range(-8, 10, 2) if xlim[0] <= 2.0 ** k <= xlim[1]]
    ax.set_xticks(xt)
    ax.set_xticklabels([("1/%d" % (1 / x)) if x < 1 else "%d" % x for x in xt])
    yt = [2.0 ** k for k in range(-4, 16, 2) if ylim[0] <= 2.0 ** k <= ylim[1]]
    ax.set_yticks(yt)
    ax.set_yticklabels([("1/%d" % (1 / y)) if y < 1 else "%d" % y for y in yt])
    ax.minorticks_off()
    ax.grid(True, which="major", color="#dddddd", lw=0.6)
    ax.set_xlabel(t["xl"])


def telhado(m):
    """(pico medido, banda medida) do telhado, conforme ESCOLHA_TELHADO."""
    return m["C5"], m[ESCOLHA_TELHADO]


def fig1(lang):
    t = TXT[lang]
    fig, ax = plt.subplots(figsize=(7.0, 4.6))
    eixos(ax, t, xlim=(2 ** -4, 2 ** 9), ylim=(2 ** 3, 2 ** 15))
    ax.set_ylabel(t["yl"])
    for k, m in MAQ.items():
        P, B = telhado(m)
        ax.plot(AI, np.minimum(P, B * AI), color=m["cor"], lw=2.2,
                label=f"{m['nome']} - {t['med']} ({fmt(P)} GF/s, {fmt(B)} GB/s)")
        ax.plot(AI, np.minimum(m["pico_teo"], m["banda_teo"] * AI), color=m["cor"],
                lw=1.3, ls="--",
                label=f"{m['nome']} - {t['teo']} ({fmt(m['pico_teo'])} GF/s, {fmt(m['banda_teo'])} GB/s)")
        # pontos de viragem (ridge)
        for (PP, BB, mk) in ((P, B, "o"), (m["pico_teo"], m["banda_teo"], "s")):
            r = PP / BB
            ax.plot([r], [PP], mk, color=m["cor"], ms=5, mfc="white", mew=1.3)
            ax.annotate(f"{r:.1f}", (r, PP), textcoords="offset points",
                        xytext=(6, -12) if mk == "o" else (-24, 5),
                        fontsize=7.5, color=m["cor"])
    ax.set_title(t["t1"], fontsize=10)
    ax.legend(loc="lower right", fontsize=7.5, frameon=True)
    ax.text(0.01, 0.98, "o / □ = " + t["ridge"] + " (FLOP/B)", transform=ax.transAxes,
            fontsize=7.5, va="top", color="#555555")
    fig.tight_layout()
    return fig


def painel(ax, m, t):
    P, B = telhado(m)
    cor = m["cor"]
    # telhado teorico (cinzento tracejado) e medido (cor cheia)
    ax.plot(AI, np.minimum(m["pico_teo"], m["banda_teo"] * AI), color="#888888",
            lw=1.0, ls="--", label=t["teo"])
    ax.plot(AI, np.minimum(P, B * AI), color=cor, lw=2.2, label=t["med"])
    # tetos de calculo (horizontais, a partir do telhado de memoria)
    calc = [("C4", m["C4"]), ("C3", m["C3"]), ("C2", m["C2"]),
            ("C1", m[ESCOLHA_C1])]
    for nome, v in calc:
        x0 = v / B
        xs = AI[AI >= x0]
        ax.plot(xs, np.full_like(xs, v), color=cor, lw=1.0, ls=(0, (4, 2)))
        lab = t["C1"][ESCOLHA_C1] if nome == "C1" else t[nome]
        perto = P / v < 1.5          # C4 do AMD fica colado ao C5: rotulo por baixo
        ax.text(XLIM[1] / 1.15, v / 1.12 if perto else v * 1.12,
                f"{lab}: {fmt(v)}", ha="right", va="top" if perto else "bottom",
                fontsize=7, color=cor, bbox=CAIXA)
    ax.text(XLIM[1] / 1.15, P * 1.12, f"{t['C5']}: {fmt(P)}", ha="right",
            va="bottom", fontsize=7, color=cor, weight="bold", bbox=CAIXA)
    # tetos de memoria (diagonais, ate ao telhado de calculo)
    for nome in ("M3", "M2", "M1", "M4"):
        if nome == ESCOLHA_TELHADO:
            continue
        v = m[nome]
        if v > B:      # um teto nunca pode ficar acima do telhado
            continue
        xs = AI[AI <= P / v]
        ax.plot(xs, v * xs, color=cor, lw=1.0, ls=(0, (1, 1.5)))
    # rotulos das diagonais: rodados ao longo da linha; os pares proximos
    # (M4/M3 e M2/M1) ficam um por cima e outro por baixo da sua linha
    ax.figure.canvas.draw()
    pos = {"M4": (64, True), "M3": (m["M3"] * 1.0, False), "M2": (m["M2"] / 32, True), "M1": (8, False)}
    for nome, (y, cima) in pos.items():
        v = m[nome]
        if nome != ESCOLHA_TELHADO and v > B:
            continue
        x = y / v
        p1 = ax.transData.transform((x, y))
        p2 = ax.transData.transform((x * 2, y * 2))
        ang = np.degrees(np.arctan2(p2[1] - p1[1], p2[0] - p1[0]))
        ax.annotate(f"{t[nome]}: {fmt(v)} GB/s", (x, y), textcoords="offset points",
                    xytext=(-4, 4) if cima else (4, -4), rotation=ang,
                    rotation_mode="anchor", ha="center" if cima else "center",
                    va="bottom" if cima else "top", fontsize=6.8, color=cor,
                    weight="bold" if nome == ESCOLHA_TELHADO else "normal",
                    bbox=CAIXA)
    ax.set_title(m["nome"], fontsize=9.5, color=cor)
    ax.legend(loc="upper left", fontsize=7)


def fig2(lang):
    t = TXT[lang]
    fig, axs = plt.subplots(1, 2, figsize=(10.0, 4.6), sharey=True)
    for ax, m in zip(axs, MAQ.values()):
        eixos(ax, t)
        painel(ax, m, t)
    axs[0].set_ylabel(t["yl"])
    fig.suptitle(t["t2"], fontsize=10)
    fig.tight_layout()
    return fig


if __name__ == "__main__":
    import os
    out = os.path.dirname(os.path.abspath(__file__))
    for lang in ("en", "pt"):
        for n, f in (("1_2", fig1), ("1_3", fig2)):
            fig = f(lang)
            for ext in ("png", "pdf"):
                fig.savefig(os.path.join(out, f"roofline_{n}_{lang}.{ext}"),
                            dpi=200 if ext == "png" else None)
            plt.close(fig)
    # resumo no terminal para conferir os numeros
    for k, m in MAQ.items():
        P, B = telhado(m)
        print(f"{k}: telhado {P} GF/s, {B} GB/s, ridge medido {P/B:.2f}, "
              f"ridge teorico {m['pico_teo']/m['banda_teo']:.2f}, "
              f"C1={m[ESCOLHA_C1]}")
