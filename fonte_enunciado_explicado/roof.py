import math

# Valores medidos na Task 1 (relatorio_task1.tex, Tabela I): pico FP32 e banda STREAM sem write-allocate
AMD = (11269.0, 299.0)
ARM = (6049.0, 813.0)

W, H = 640, 400
L, R, T, B = 70, 20, 20, 50
PW, PH = W - L - R, H - T - B
XMIN, XMAX = -3, 7          # log2(OI): 1/8 .. 128 FLOP/B
YMIN, YMAX = -1, 5          # log10(GFLOP/s): 0.1 .. 100000


def X(oi):
    return L + (math.log2(oi) - XMIN) / (XMAX - XMIN) * PW


def Y(g):
    return T + PH - (math.log10(g) - YMIN) / (YMAX - YMIN) * PH


def roof(peak, bw, color, label, ly):
    ridge = peak / bw
    x0 = 2 ** XMIN
    s = (f'<polyline points="{X(x0):.1f},{Y(bw*x0):.1f} {X(ridge):.1f},{Y(peak):.1f} '
         f'{X(2**XMAX):.1f},{Y(peak):.1f}" fill="none" stroke="{color}" stroke-width="3"/>')
    s += f'<circle cx="{X(ridge):.1f}" cy="{Y(peak):.1f}" r="4.5" fill="{color}"/>'
    if ly < 0:
        s += (f'<text x="{X(ridge)-8:.1f}" y="{Y(peak)-8:.1f}" font-size="11" fill="{color}" text-anchor="end">'
              f'ridge ≈ {ridge:.1f} FLOP/B</text>')
    else:
        s += (f'<text x="{X(ridge)+6:.1f}" y="{Y(peak)+16:.1f}" font-size="11" fill="{color}">'
              f'ridge ≈ {ridge:.1f} FLOP/B</text>')
    yy = Y(4) + (0 if ly < 0 else 20)
    s += (f'<line x1="{X(24):.1f}" y1="{yy-4:.1f}" x2="{X(34):.1f}" y2="{yy-4:.1f}" stroke="{color}" stroke-width="3"/>'
          f'<text x="{X(37):.1f}" y="{yy:.1f}" font-size="11.5" font-weight="bold" fill="{color}">{label}</text>')
    return s


def svg():
    o = [f'<svg viewBox="0 0 {W} {H}" width="100%" xmlns="http://www.w3.org/2000/svg" font-family="DejaVu Sans, sans-serif">']
    o.append(f'<rect x="{L}" y="{T}" width="{PW}" height="{PH}" fill="#fbfbfd" stroke="#888"/>')
    # memory-bound / compute-bound shading labels
    for e in range(XMIN, XMAX + 1):
        x = L + (e - XMIN) / (XMAX - XMIN) * PW
        o.append(f'<line x1="{x:.1f}" y1="{T}" x2="{x:.1f}" y2="{T+PH}" stroke="#e3e3ea"/>')
        lab = f'1/{2**-e}' if e < 0 else f'{2**e}'
        o.append(f'<text x="{x:.1f}" y="{T+PH+16}" font-size="11" text-anchor="middle">{lab}</text>')
    for e in range(YMIN, YMAX + 1):
        y = T + PH - (e - YMIN) / (YMAX - YMIN) * PH
        o.append(f'<line x1="{L}" y1="{y:.1f}" x2="{L+PW}" y2="{y:.1f}" stroke="#e3e3ea"/>')
        lab = {-1: '0.1', 0: '1', 1: '10', 2: '100', 3: '1 000', 4: '10 000', 5: '100 000'}[e]
        o.append(f'<text x="{L-6}" y="{y+4:.1f}" font-size="11" text-anchor="end">{lab}</text>')
    o.append(f'<text x="{L+PW/2}" y="{H-10}" font-size="12" text-anchor="middle">Intensidade operacional, OI (FLOP por byte) — escala log</text>')
    o.append(f'<text x="16" y="{T+PH/2}" font-size="12" text-anchor="middle" transform="rotate(-90 16 {T+PH/2})">Desempenho (GFLOP/s) — escala log</text>')
    o.append(roof(*AMD, '#c0392b', 'x86 (AMD 7742)', -2))
    o.append(roof(*ARM, '#1f6fb2', 'ARM (A64FX)', 0))
    # OI do Jacobi
    oi = 3.75
    o.append(f'<line x1="{X(oi):.1f}" y1="{T}" x2="{X(oi):.1f}" y2="{T+PH}" stroke="#2e7d32" stroke-width="2" stroke-dasharray="6 4"/>')
    o.append(f'<text x="{X(oi)+5:.1f}" y="{T+14}" font-size="11.5" fill="#2e7d32" font-weight="bold">OI do Jacobi varcoef ≈ 3.75</text>')
    # tetos de memoria no ponto
    for bw, c in ((AMD[1], '#c0392b'), (ARM[1], '#1f6fb2')):
        o.append(f'<circle cx="{X(oi):.1f}" cy="{Y(bw*oi):.1f}" r="5" fill="white" stroke="{c}" stroke-width="2.5"/>')
    o.append(f'<text x="{X(oi)-8:.1f}" y="{Y(ARM[1]*oi)-8:.1f}" font-size="10.5" text-anchor="end" fill="#1f6fb2">máx. ≈ {ARM[1]*oi/1000:.1f} TFLOP/s</text>')
    o.append(f'<text x="{X(oi)-8:.1f}" y="{Y(AMD[1]*oi)+16:.1f}" font-size="10.5" text-anchor="end" fill="#c0392b">máx. ≈ {AMD[1]*oi/1000:.1f} TFLOP/s</text>')
    # referencia (ordem de grandeza, ilustrativa)
    ref = 0.45
    o.append(f'<rect x="{X(oi)-7:.1f}" y="{Y(ref)-7:.1f}" width="14" height="14" fill="#555" transform="rotate(45 {X(oi):.1f} {Y(ref):.1f})"/>')
    o.append(f'<text x="{X(oi)+12:.1f}" y="{Y(ref)+4:.1f}" font-size="10.5" fill="#333">referência (1 thread): ~0.5 GFLOP/s</text>')
    # seta "otimizar"
    o.append('<defs><marker id="ar" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto"><path d="M0,0 L10,4 L0,8 z" fill="#2e7d32"/></marker></defs>')
    o.append(f'<line x1="{X(oi)+30:.1f}" y1="{Y(ref)-12:.1f}" x2="{X(oi)+30:.1f}" y2="{Y(AMD[1]*oi)+26:.1f}" stroke="#2e7d32" stroke-width="2.5" marker-end="url(#ar)"/>')
    o.append(f'<text x="{X(oi)+38:.1f}" y="{(Y(ref)+Y(AMD[1]*oi))/2:.1f}" font-size="11.5" fill="#2e7d32" font-weight="bold">Task 2: subir até ao telhado</text>')
    o.append(f'<text x="{X(oi)+38:.1f}" y="{(Y(ref)+Y(AMD[1]*oi))/2+14:.1f}" font-size="10.5" fill="#2e7d32">(paralelizar, vetorizar, melhorar acessos)</text>')
    # regioes
    o.append(f'<text x="{X(0.18):.1f}" y="{Y(30000):.1f}" font-size="11" fill="#666" font-style="italic">← limitado pela memória</text>')
    o.append(f'<text x="{X(14):.1f}" y="{Y(40000):.1f}" font-size="11" fill="#666" font-style="italic">limitado pelas contas →</text>')
    o.append('</svg>')
    return '\n'.join(o)


if __name__ == '__main__':
    print(svg())
