import base64, math, sys
sys.path.insert(0, '/tmp/claude-0/enun')
import roof

D = '/tmp/claude-0/enun/'
html = open(D + 'enunciado_explicado.html').read()

# ---------- Figura 5: corte 2D + layout em memoria ----------
def slice_fig():
    o = []
    c = 26; x0, y0 = 40, 30; N = 7
    o.append(f'<text x="{x0+N*c/2}" y="16" text-anchor="middle" font-size="11" font-weight="bold" fill="#12325c">plano j fixo (linhas: i, colunas: k)</text>')
    for i in range(N):
        for k in range(N):
            halo = i in (0, N-1) or k in (0, N-1)
            if not halo: col = '#ffd9a8'
            elif i == 0: col = '#f4a3a3'
            else: col = '#cfd8e6'
            o.append(f'<rect x="{x0+k*c}" y="{y0+i*c}" width="{c}" height="{c}" fill="{col}" stroke="#777" stroke-width="0.8"/>')
            if i == 0 and 0 < k < N-1:
                o.append(f'<text x="{x0+k*c+c/2}" y="{y0+c/2+4}" text-anchor="middle" font-size="9.5">1</text>')
            elif halo and not (i == 0):
                o.append(f'<text x="{x0+k*c+c/2}" y="{y0+i*c+c/2+4}" text-anchor="middle" font-size="9.5" fill="#555">0</text>')
    for t in range(N):
        o.append(f'<text x="{x0+t*c+c/2}" y="{y0+N*c+13}" text-anchor="middle" font-size="9">{t}</text>')
        o.append(f'<text x="{x0-6}" y="{y0+t*c+c/2+3}" text-anchor="end" font-size="9">{t}</text>')
    o.append(f'<text x="{x0+N*c/2}" y="{y0+N*c+27}" text-anchor="middle" font-size="10">k →  (contíguo na memória)</text>')
    o.append(f'<text x="{x0-24}" y="{y0+N*c/2}" text-anchor="middle" font-size="10" transform="rotate(-90 {x0-24} {y0+N*c/2})">i ↓</text>')
    # legenda
    lx = 250
    for j, (col, t) in enumerate((('#ffd9a8', 'interior (incógnitas)'), ('#f4a3a3', 'halo da face i = 0 (u = 1)'), ('#cfd8e6', 'restante halo (u = 0)'))):
        o.append(f'<rect x="{lx}" y="{30+j*18}" width="12" height="12" fill="{col}" stroke="#777"/><text x="{lx+18}" y="{40+j*18}">{t}</text>')
    # layout linear
    ly = 115; cw = 34
    o.append(f'<text x="{lx}" y="{ly-8}" font-weight="bold" fill="#12325c" font-size="10.5">Na memória, um só array linear (k muda mais depressa):</text>')
    labels = ['k=0', 'k=1', 'k=2', '…', 'k=n+1', 'k=0', 'k=1', '…']
    for t, lab in enumerate(labels):
        col = '#e8eef7' if t < 5 else '#f6ecdc'
        o.append(f'<rect x="{lx+t*cw}" y="{ly}" width="{cw}" height="22" fill="{col}" stroke="#777"/><text x="{lx+t*cw+cw/2}" y="{ly+15}" text-anchor="middle" font-size="9">{lab}</text>')
    o.append(f'<text x="{lx+2.5*cw}" y="{ly+36}" text-anchor="middle" font-size="9.5">linha (i, j)</text>')
    o.append(f'<text x="{lx+6.5*cw}" y="{ly+36}" text-anchor="middle" font-size="9.5">linha (i, j+1)</text>')
    o.append(f'<text x="{lx}" y="{ly+58}" font-size="10" font-family="DejaVu Sans Mono">idx(i,j,k) = (i·(ny+2) + j)·(nz+2) + k</text>')
    o.append(f'<text x="{lx}" y="{ly+76}" font-size="10">distância ao vizinho:  k±1 → 1 elemento;  j±1 → nz+2;</text>')
    o.append(f'<text x="{lx}" y="{ly+92}" font-size="10">i±1 → (ny+2)(nz+2) elementos (para n = 520: 272 484 floats ≈ 1 MiB)</text>')
    return '\n'.join(o)

# ---------- Figura 7: corte com materiais ----------
def mat_fig():
    o = []
    c = 20; x0, y0 = 20, 15; NX, NY = 16, 9
    cols = {'E': '#f3e7c9', 'C': '#5d6d7e', 'A': '#d6f0ff', 'H': '#e74c3c'}
    def mat(r, q):
        if r in (2, 6): return 'C'
        if (q - 7.5) ** 2 + (r - 4) ** 2 <= 2.3: return 'H'
        for (ar, aq) in ((4, 2), (4, 13), (0, 7), (8, 7)):
            if (q - aq) ** 2 + (r - ar) ** 2 <= 1.0: return 'A'
        return 'E'
    for r in range(NY):
        for q in range(NX):
            o.append(f'<rect x="{x0+q*c}" y="{y0+r*c}" width="{c}" height="{c}" fill="{cols[mat(r,q)]}" stroke="#999" stroke-width="0.5"/>')
    # p na fronteira carbono / epoxy
    pr, pq = 3, 3
    cx, cy = x0 + pq * c + c / 2, y0 + pr * c + c / 2
    for dr, dq in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        o.append(f'<line x1="{cx}" y1="{cy}" x2="{cx+dq*c}" y2="{cy+dr*c}" stroke="#111" stroke-width="2"/>')
        o.append(f'<circle cx="{cx+dq*c}" cy="{cy+dr*c}" r="4" fill="#1f6fb2"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="6" fill="#e67e22" stroke="#111"/>')
    o.append(f'<text x="{cx+8}" y="{cy-6}" font-weight="bold">p</text>')
    o.append(f'<text x="{cx+8}" y="{cy-c-8}" font-size="9.5" font-weight="bold">q</text>')
    # legenda
    lx = 360
    for j, (k, t) in enumerate((('E', 'epoxy  κ = 1'), ('C', 'carbon  κ = 20'), ('A', 'air  κ = 0.05'), ('H', 'heater  κ = 5, q = 500'))):
        o.append(f'<rect x="{lx}" y="{15+j*18}" width="12" height="12" fill="{cols[k]}" stroke="#777"/><text x="{lx+18}" y="{25+j*18}">{t}</text>')
    o.append(f'<text x="{lx}" y="110" font-weight="bold" fill="#12325c">Ponto p (epoxy), vizinho q acima (carbono):</text>')
    o.append(f'<text x="{lx}" y="128">1. material[p] = epoxy → κp = 1.0 (tabela)</text>')
    o.append(f'<text x="{lx}" y="144">2. material[q] = carbon → κq = 20.0 (tabela)</text>')
    o.append(f'<text x="{lx}" y="160">3. κpq = 2·1·20 / (1+20) ≈ 1.905</text>')
    o.append(f'<text x="{lx}" y="176">4. repetir para os outros 5 vizinhos (3D),</text>')
    o.append(f'<text x="{lx+12}" y="192">somar e dividir</text>')
    return '\n'.join(o)

# ---------- Figura 8: ping-pong ----------
def pingpong():
    o = ['<defs><marker id="a8" markerWidth="9" markerHeight="7" refX="8" refY="3.5" orient="auto"><path d="M0,0 L9,3.5 L0,7 z" fill="#333"/></marker></defs>']
    c = 22
    def grid(x0, y0, title, col, hl=None, nb=()):
        o.append(f'<text x="{x0+3.5*c}" y="{y0-8}" text-anchor="middle" font-weight="bold">{title}</text>')
        for r in range(7):
            for q in range(7):
                f = col
                if (r, q) in nb: f = '#1f6fb2'
                if (r, q) == hl: f = '#e67e22'
                o.append(f'<rect x="{x0+q*c}" y="{y0+r*c}" width="{c}" height="{c}" fill="{f}" stroke="#888" stroke-width="0.7"/>')
    nb = ((2, 3), (4, 3), (3, 2), (3, 4))
    grid(40, 30, 'u  (iteração n)', '#eef4fb', nb=nb + ((3, 3),))
    grid(380, 30, 'u_new  (iteração n+1)', '#fff3e0', hl=(3, 3))
    o.append(f'<path d="M{40+7*c+8},{30+3.5*c} C 280,{30+3.5*c+20} 330,{30+3.5*c+20} {380+3*c-2},{30+3.5*c}" fill="none" stroke="#333" stroke-width="1.8" marker-end="url(#a8)"/>')
    for j, t in enumerate(('jacobi_sweep:', 'lê p e os vizinhos em u,', 'escreve o novo p em u_new')):
        o.append(f'<text x="287" y="{48+j*14}" text-anchor="middle" font-size="10.5">{t}</text>')
    o.append(f'<text x="287" y="{30+7*c-6}" text-anchor="middle" font-size="9.5" fill="#555">(desenho 2D; em 3D são 6 vizinhos)</text>')
    o.append(f'<path d="M{380+3.5*c},{30+7*c+4} C {380+3.5*c},222 {40+3.5*c},222 {40+3.5*c},{30+7*c+8}" fill="none" stroke="#2e7d32" stroke-width="1.8" stroke-dasharray="5 3" marker-end="url(#a8)"/>')
    o.append(f'<text x="287" y="238" text-anchor="middle" font-size="10.5" fill="#2e7d32">jacobi_update: u ← u_new; repete até fazer as -i iterações</text>')
    return '\n'.join(o)

# ---------- Figura 9: decomposicao ----------
def decomp():
    o = []
    cols = ['#dce9f7', '#fde6cc', '#e2f1e3', '#f3e5f5']
    x0, y0, w, h = 40, 25, 400, 140
    sw = w / 4
    for t in range(4):
        o.append(f'<rect x="{x0+t*sw}" y="{y0}" width="{sw}" height="{h}" fill="{cols[t]}" stroke="#555"/>')
        o.append(f'<text x="{x0+t*sw+sw/2}" y="{y0+h/2}" text-anchor="middle" font-weight="bold">thread {t}</text>')
        o.append(f'<text x="{x0+t*sw+sw/2}" y="{y0+h/2+16}" text-anchor="middle" font-size="10">i = {t}·n/4+1 … {t+1}·n/4</text>')
    for t in range(1, 4):
        xb = x0 + t * sw
        o.append(f'<rect x="{xb-7}" y="{y0}" width="14" height="{h}" fill="none" stroke="#c0392b" stroke-width="1.6" stroke-dasharray="4 3"/>')
    o.append(f'<text x="{x0+w/2}" y="{y0-8}" text-anchor="middle" font-size="10.5">grelha vista de lado, partida em fatias ao longo de i</text>')
    o.append(f'<text x="{x0+w/2}" y="{y0+h+18}" text-anchor="middle" font-size="10" fill="#c0392b">a tracejado: planos de fronteira que cada fatia lê da vizinha em cada iteração</text>')
    lx = 470
    lines = [('Dentro de uma iteração:', True), ('todas as fatias em paralelo,', False), ('sem esperar umas pelas outras.', False), ('', False),
             ('Entre iterações:', True), ('barreira; todas têm de acabar', False), ('antes de alguém começar a n+1.', False), ('', False),
             ('Resíduo r:', True), ('cada thread soma a sua parte,', False), ('depois soma-se tudo (redução).', False)]
    for j, (t, b) in enumerate(lines):
        o.append(f'<text x="{lx}" y="{30+j*15}" font-size="10.5" {"font-weight=\"bold\" fill=\"#12325c\"" if b else ""}>{t}</text>')
    return '\n'.join(o)

img = base64.b64encode(open(D + 'img/s02_Picture6.png', 'rb').read()).decode()
html = (html.replace('{{SLICE}}', slice_fig()).replace('{{MATSLICE}}', mat_fig())
        .replace('{{PINGPONG}}', pingpong()).replace('{{DECOMP}}', decomp())
        .replace('{{ROOF}}', roof.svg()).replace('{{IMG_SOL}}', 'data:image/png;base64,' + img))
html = html.replace('<g transform="translate(360,40)" font-size="11.5" fill="#222">', '<g transform="translate(360,40)" font-size="11.5" fill="#222" style="white-space:pre" font-family="DejaVu Sans Mono, monospace">')
assert '{{' not in html
open(D + 'out.html', 'w').write(html)

print('html ok')
