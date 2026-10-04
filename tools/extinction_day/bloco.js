// Monta o bloco do mapa Extinction Day e insere no config/jogo.json.  node bloco.js <caminho do jogo.json>
const fs = require('fs');
const { ps, mundo } = require('./cursos.js');
const { vulcao, V, dirv } = require('./gen.js');
const desenhar = require('./desenho.js');
const r1 = v => Math.round(v * 10) / 10;
const pts = t => t.pts.map(p => [r1(p[0]), r1(p[1]), r1(p[2])]);
const dir4 = h => [Math.round(Math.sin(h * Math.PI / 180)), Math.round(-Math.cos(h * Math.PI / 180))];
const D = Math.PI / 180;

// ------------------------------------------------------------------ armadilhas por etapa (posições por etiqueta)
// Tipos: raptores [T, m, fase, período(0 = padrão), túnel], mordidas [T, m, fase, lado], rochas [T, m, fase, túnel],
// lavas [T, m, fase], lajes/pontes [T, m0, m1, túnel], eletricas [T, m, fase], manadas [T, m, fase, lado],
// portoes [T, m, fase, letreiro], estouros [T, m0, m1, fase], meteoros [T, m, fase], avalanches [T, m0, m1, fase]
const armas = [
  { // E1 Boca do Vulcão: parque na entrada, depois o túnel por dentro do vulcão (metade da etapa)
    raptores: [['B', '#b2+520', 1.1, 0, true], ['C', '#c3+120', 0.4, 0, true]], raptor: { periodo: 3.8, salto_s: 0.85 },
    rochas: [['A', '#a6+15', 0.0, false], ['B', '#b2+300', 1.2, true], ['C', '#c2+60', 0.6, true]], rocha: { periodo: 5.4, queda_s: 0.6, fica_s: 2.2 },
    lavas: [['B', '#b2+120', 0.0], ['C', '#c1+90', 1.0]], lava: { periodo: 4.4, ligado_s: 1.4 },
    lajes: [['B', '#b2+700', '#b2+760', true]], laje: { tempo_s: 0.8, volta_s: 5.0, comprimento: 4.0, aderencia: 0.85 },
    mordidas: [['B', '#b2+860', 0.0, -1], ['C', '#c1+260', 2.0, -1]], mordida: { periodo: 6.8, bote_s: 0.5, fechada_s: 0.9, volta_s: 1.4 },
    impulsos: [['B', -62, 12], ['C', -100]],
  },
  { // E2 Noite da Aurora: o parque à noite, à luz de tochas; poço de lava no lugar da plataforma e bifurcação no C
    raptores: [['A', '#a4+40', 0.0, 0, false], ['C', '#c6+240', 1.5, 0, false]], raptor: { periodo: 3.5, salto_s: 0.8 },
    portoes: [['A', '#a5+70', 0.0, 'RECINTO 07']], portao: { periodo: 6.8, fecha_s: 0.6, fechada_s: 1.2, abre_s: 1.3 },
    manadas: [['A', '#a8+150', 0.0, 1], ['B', '#b2+130', 6.0, -1], ['C', '#c4+350', 12.0, 1]], manada: { bicho: 'tiranossauro', travessia_s: 6.5, vira_s: 2.0, comprimento: 24, segura_s: 3.0 },
    pontes: [['B', '#b2+300', '#b2+380'], ['C', '#c6+60', '#c6+120']], ponte: { tempo_s: 0.6, volta_s: 5.0, comprimento: 2.2, aderencia: 0.9 },
    impulsos: [['B', -62, 12], ['C', -100]],
  },
  { // E3 Fuga da Encosta: quatro molas na ladeira (o dono mandou tirar o estouro de manada), a subida pelo flanco
    estouros: [], estouro: { periodo: 6.5, velocidade: 14, padrao: 'alterna', comprimento: 13.5 },
    // cinco pontos de cuspidores na ladeira, entre as molas (pedido do dono, por captura de tela)
    raptores: [['A', '#a2-30', 0.0, 0, false], ['A', '#a2+13', 0.7, 0, false], ['A', '#a2+57', 1.4, 0, false], ['A', '#a2+103', 2.1, 0, false], ['A', '#a2+147', 2.8, 0, false]],
    raptor: { periodo: 3.4, salto_s: 0.8 },
    rochas: [['B', '#b2+120', 0.0, false], ['B', '#b2+620', 1.4, false], ['C', '#c5+40', 0.8, false]], rocha: { periodo: 5.0, queda_s: 0.55, fica_s: 2.2 },
    lavas: [['B', '#b2+380', 0.0], ['C', '#c2+260', 1.2]], lava: { periodo: 4.0, ligado_s: 1.4 },
    lajes: [['B', '#b2+680', '#b2+740', false]], laje: { tempo_s: 0.75, volta_s: 5.0, comprimento: 4.0, aderencia: 0.85 },
    impulsos: [['B', -62, 12], ['C', -100]],
  },
  { // E4 Impacto: tudo junto, com pedaços do meteoro caindo na pista
    meteoros: [['A', '#a2+40', 0.0], ['A', '#a4+60', 2.1], ['B', '#b1+60', 0.7], ['C', '#c1+20', 1.4], ['C', '#c3+140', 4.2], ['C', '#c4+160', 0.3]],
    meteoro: { periodo: 6.5, aviso_s: 1.8, queima_s: 3.0 },
    raptores: [['A', '#a2+130', 0.5, 0, false], ['C', '#c6+40', 1.0, 0, false]], raptor: { periodo: 3.2, salto_s: 0.75 },
    lavas: [['A', '#a6+40', 0.0]], lava: { periodo: 3.8, ligado_s: 1.4 },
    lajes: [['B', '#b2+70', '#b2+110', false]], laje: { tempo_s: 0.7, volta_s: 5.5, comprimento: 4.0, aderencia: 0.85 },
    rochas: [['B', '#b4+40', 0.0, false]], rocha: { periodo: 4.8, queda_s: 0.55, fica_s: 2.2 },
    manadas: [['C', '#c3+60', 3.0, 1]], manada: { bicho: 'tiranossauro', travessia_s: 6.0, vira_s: 2.0, comprimento: 24, segura_s: 3.0 },
    portoes: [['C', '#c4+60', 1.0, 'SETOR T-REX']], portao: { periodo: 6.2, fecha_s: 0.5, fechada_s: 1.2, abre_s: 1.2 },
    impulsos: [['B', -62, 12], ['C', -100]],
  },
];
// ------------------------------------------------------------------ bifurcações (rotas alternativas)
// E2, reta do C entre z=60 e z=355 (a estrada vai para o sul em x=311, subindo 5,2%):
//  - oeste: ILHAS DE BASALTO — cinco colunas soltas no ar, cada uma 1,5 m mais baixa que a anterior, com 6,5 m de vão
//    (abaixo de ~13 m/s o carro não alcança a próxima); depois a ladeira forte de volta à estrada
//  - meio: a estrada, com o raptor e o portão do RECINTO 12
//  - leste: GÊISER — a pista baixa acaba na boca do gêiser, que lança o carro para um deque alto; o deque
//    passa por fora da chicane e volta à estrada depois dela (atalho)
const desvios = [[], [], [], []];   // preenchido adiante (lados fáceis de cada desafio)
ps.forEach((p, k) => {
  for (const d of desvios[k] || []) for (const c of ['de', 'para']) {
    const m = String(d[c][1]).match(/^(#\w+)([+-]\d+)?$/);
    if (m) d[c][1] = Math.round(p[d[c][0]].tags[m[1]] + Number(m[2] || 0));
  }
});
// Cuspidores antes de todo piso que quebra do mapa (pedido do dono, 2026-10-03), ~22 m antes de cada um.
// (o piso do túnel da E1, B 1199, ficou sem: não há beirada para os bichos dentro do tubo)
const CUSPIDORES_PISO = [[["A",428,0.3]],[["B",662,0.8],["C",600,0.2],["C",1872,1.2]],[["A",762,0.4],["B",1300,1.6]],[["B",494,1.3]]];
CUSPIDORES_PISO.forEach((l, k) => { for (const c of l) armas[k].raptores = (armas[k].raptores || []).concat([[c[0], c[1], c[2], 0, false]]); });
const TIPOS1 = ['raptores', 'mordidas', 'rochas', 'lavas', 'eletricas', 'manadas', 'portoes', 'meteoros', 'catapultas'];
const TIPOS2 = ['lajes', 'pontes', 'estouros', 'avalanches'];
// Metros que cada armadilha ocupa na estrada (para conferir as distâncias)
const VAO_CATAPULTA = 36;
const COMP = { catapultas: 6 + VAO_CATAPULTA + 45, raptores: 6, mordidas: 16, rochas: 10, lavas: 6, eletricas: 6, manadas: 20, portoes: 4, meteoros: 8 };
ps.forEach((p, k) => {
  const res = (T, v) => {
    if (typeof v !== 'string') return v;
    const m = v.match(/^(#\w+)([+-]\d+)?$/);
    if (!m || p[T].tags[m[1]] === undefined) { console.log(`!! E${k + 1} etiqueta desconhecida ${T} ${v}`); process.exit(1); }
    return Math.round(p[T].tags[m[1]] + Number(m[2] || 0));
  };
  const a = armas[k];
  for (const t of TIPOS1) for (const it of a[t] || []) it[1] = res(it[0], it[1]);
  for (const t of TIPOS2) for (const it of a[t] || []) { it[1] = res(it[0], it[1]); it[2] = res(it[0], it[2]); }
});

// ------------------------------------------------------------------ pista principal difícil, lados fáceis
// Regra do dono (2026-10-03): o caminho reto (pista principal) é o mais curto e o mais perigoso — quatro
// desafios em sequência: portão, piso que cai, aceleradores contrários (jogam o carro para trás; passa-se
// pelo lado livre) e a mola ejetora (lança o carro ~30 m para cima girando sem controle; no ar, paraquedas).
// Ao lado, um desvio largo e sem armadilha que serpenteia e custa uns 8 a 10 s a mais.
// Na E2 há mais duas molas avulsas (onde ficavam as catapultas), cada uma com o seu desvio fácil.
function ponto_em(t, m) {
  let acc = 0;
  for (let i = 1; i < t.pts.length; i++) {
    const a = t.pts[i - 1], b = t.pts[i];
    const L = Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
    if (acc + L >= m || i === t.pts.length - 1) {
      const f = (m - acc) / L, h = Math.hypot(b[0] - a[0], b[2] - a[2]);
      return { pos: [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f], esq: [(b[2] - a[2]) / h, -(b[0] - a[0]) / h] };
    }
    acc += L;
  }
}
const tagm = (k, T, v) => { const m = String(v).match(/^(#\w+)([+-]\d+)?$/); return Math.round(ps[k][T].tags[m[1]] + Number(m[2] || 0)); };
const LARGURA_FACIL = 14;
// Desvio fácil: sai colado na borda (lado +1 = direita), afasta D0 m, serpenteia com amplitude A (n ondas) e volta
function lateral_facil(k, nome, T, m0, m1, lado, D0, A, n) {
  const t = ps[k][T], pontos = [];
  const ss = (a, b, x) => { const u = Math.min(Math.max((x - a) / (b - a), 0), 1); return u * u * (3 - 2 * u); };
  const N = Math.round((m1 - m0) / 10);
  let pior = 1e9, comp = 0, ant = null;
  for (let j = 0; j <= N; j++) {
    const u = j / N, q = ponto_em(t, m0 + (m1 - m0) * u);
    // Os primeiros e os últimos 42 m correm colados na estrada (é por ali que se entra e se sai: a ponta é uma cunha)
    const adj = 42 / (m1 - m0);
    const E = ss(adj, adj + 0.2, u) * (1 - ss(1 - adj - 0.2, 1 - adj, u));
    const off = 5 + LARGURA_FACIL / 2 - 0.3 + E * (D0 + A * Math.sin(2 * Math.PI * n * u));
    const x = q.pos[0] - q.esq[0] * lado * off, z = q.pos[2] - q.esq[1] * lado * off;
    pontos.push([r1(x), r1(q.pos[1]), r1(z)]);
    if (ant) comp += Math.hypot(x - ant[0], z - ant[1]);
    ant = [x, z];
    if (vulcao(x, z) > q.pos[1] - 8) console.log(`!! E${k + 1} desvio ${nome} dentro da encosta do vulcão em (${x.toFixed(0)}, ${z.toFixed(0)})`);
    if (E > 0.6) for (const TT of ['A', 'B', 'C']) {
      let mm = 0; const pp = ps[k][TT].pts;
      for (let i = 0; i < pp.length; i++) {
        if (i) mm += Math.hypot(pp[i][0] - pp[i - 1][0], pp[i][1] - pp[i - 1][1], pp[i][2] - pp[i - 1][2]);
        if (TT === T && mm > m0 - 60 && mm < m1 + 60) continue;
        pior = Math.min(pior, Math.hypot(pp[i][0] - x, pp[i][2] - z));
      }
    }
  }
  if (pior < 45) console.log(`!! E${k + 1} desvio ${nome} a ${pior.toFixed(0)} m de outra estrada`);
  console.log(`E${k + 1} desvio ${nome}: ${T} ${m0}-${m1}, ${comp.toFixed(0)} m contra ${m1 - m0} m da pista (+${(comp - (m1 - m0)).toFixed(0)} m)`);
  return { nome, tipo: 'estrada', de: [T, m0], para: [T, m1], largura: LARGURA_FACIL, peso_bots: 2.0, pontos };
}
// Desvio ESTREITO e longo (pedido do dono para o lado das plataformas redondas da E2): 4,5 m de largura e
// ~4x o comprimento do desvio antigo — sai colado na borda, e sobe e desce em grampos (pernas perpendiculares
// à estrada ligadas por meias-voltas de raio R), até voltar. `alvo` = comprimento total desejado.
const LARGURA_ESTREITA = 4.5;
// R = raio das meias-voltas: 18 m dá 6 pernas em 300 m de pista (o dono pediu metade das curvas que havia com R = 9).
function lateral_estreita(k, nome, T, m0, m1, lado, alvo, R = 18) {
  const t = ps[k][T], L = m1 - m0, ADJ = 42;
  const n = 2 * Math.floor((L - 2 * ADJ) / (4 * R));          // pernas (par: a última volta para a estrada)
  const sobra = (L - 2 * ADJ - 2 * R * n) / 2;
  const dB = R + 8;
  const dT = (alvo - 2 * ADJ - 2 * sobra - n * Math.PI * R + 2 * R + (n - 2) * dB) / n;
  const sd = [];                                               // pontos (s ao longo da estrada, d para fora)
  const arco = (cs, cd, a0, a1) => { const N = 8; for (let j = 1; j <= N; j++) { const a = a0 + (a1 - a0) * j / N; sd.push([cs + R * Math.cos(a), cd + R * Math.sin(a)]); } };
  const reta = (s1, d1) => { const [s0, d0] = sd[sd.length - 1]; const N = Math.max(1, Math.round(Math.hypot(s1 - s0, d1 - d0) / 8)); for (let j = 1; j <= N; j++) sd.push([s0 + (s1 - s0) * j / N, d0 + (d1 - d0) * j / N]); };
  sd.push([0, 0]);
  let s = ADJ + sobra;
  reta(s, 0);
  arco(s, R, -Math.PI / 2, 0);                                 // vira para fora
  s += R;
  for (let j = 0; j < n; j++) {
    const sobe = j % 2 === 0;
    if (sobe) { reta(s, dT); if (j < n - 1) arco(s + R, dT, Math.PI, 0); }
    else { reta(s, j === n - 1 ? R : dB); if (j < n - 1) arco(s + R, dB, Math.PI, 2 * Math.PI); }
    if (j < n - 1) s += 2 * R;
  }
  arco(s + R, R, Math.PI, 1.5 * Math.PI);                      // volta a correr junto da estrada
  reta(L, 0);
  const base = 5 + LARGURA_ESTREITA / 2 - 0.3;
  const pontos = [];
  let comp = 0, ant = null, pior = 1e9;
  for (const [ss, d] of sd) {
    const q = ponto_em(t, m0 + ss), off = base + d;
    const x = q.pos[0] - q.esq[0] * lado * off, z = q.pos[2] - q.esq[1] * lado * off;
    pontos.push([r1(x), r1(q.pos[1]), r1(z)]);
    if (ant) comp += Math.hypot(x - ant[0], z - ant[1]);
    ant = [x, z];
    if (vulcao(x, z) > q.pos[1] - 8) console.log(`!! E${k + 1} desvio ${nome} dentro da encosta do vulcão em (${x.toFixed(0)}, ${z.toFixed(0)})`);
    if (d > 20) for (const TT of ['A', 'B', 'C']) {
      let mm = 0; const pp = ps[k][TT].pts;
      for (let i = 0; i < pp.length; i++) {
        if (i) mm += Math.hypot(pp[i][0] - pp[i - 1][0], pp[i][1] - pp[i - 1][1], pp[i][2] - pp[i - 1][2]);
        if (TT === T && mm > m0 - 60 && mm < m1 + 60) continue;
        pior = Math.min(pior, Math.hypot(pp[i][0] - x, pp[i][2] - z));
      }
    }
  }
  if (pior < 45) console.log(`!! E${k + 1} desvio ${nome} a ${pior.toFixed(0)} m de outra estrada`);
  console.log(`E${k + 1} desvio estreito ${nome}: ${T} ${m0}-${m1}, ${comp.toFixed(0)} m contra ${L} m da pista, ${n} pernas até ${(dT + R).toFixed(0)} m para fora`);
  return { nome, tipo: 'estrada', de: [T, m0], para: [T, m1], largura: LARGURA_ESTREITA, peso_bots: 0.0, pontos }   // peso 0: os bots não entram (caíam logo na entrada da faixa estreita);
}
const DESAFIOS = [
  // E1: mola GIGANTE (48 m, de borda a borda) — a de 5 m ficava onde o desvio ainda corre colado na pista e dava
  // para contorná-la por ele e voltar; esta vai até depois de as duas pistas se separarem (pedido do dono)
  { T: 'A', mola: '#a2+34', mola_comp: 48, portao: ['#a3+25', 'RECINTO 03'], piso: ['#a3+75', '#a3+115'], re: ['#a3+150', '#a3+172'], de: '#a1+115', para: '#a3+218', lados: [-1] },
  { T: 'C', portao: ['#c3+60', 'RECINTO 12'], piso: ['#c3+105', '#c3+145'], re: ['#c3+185', '#c3+207'], mola: '#c3+245', de: '#c3+20', para: '#c3+395', lados: [-1, 1],
    molas: [['A', '#a2+60', -1, 'ilhas'], ['B', '#b4+20', 1]] },   // 'ilhas': no lugar da mola, plataformas redondas desniveladas (pedido do dono)
  { T: 'A', portao: ['#a3+90', 'SETOR 9'], piso: ['#a4+15', '#a4+55'], re: ['#a4+88', '#a4+110'], mola: '#a5+5', de: '#a3+18', para: '#a5+130', lados: [1],
    molas: [['C', '#c2+30', 1]],   // no lugar da avalanche (Zona de Fluxo Piroclástico), que o dono mandou tirar
    ilhas_soltas: [['A', 492, 616, 10, 23.5]],   // 5 plataformas redondas no lugar da chicane estreita do A (pedido do dono, por captura de tela): sem desvio ao lado
    molas_soltas: [['A', '#a2+35'], ['A', '#a2+80'], ['A', '#a2+125'], ['A', '#a2+170']] },   // no lugar do estouro de manada (pedido do dono): sem desvio ao lado
  { T: 'B', portao: ['#b2+20', 'SETOR 4'], piso: null, re: ['#b2+140', '#b2+160'], mola: '#b2+178', de: '#b2-50', para: '#b3+70', lados: [-1] },
];
const ALTURA_MOLA = 30;
const extras = [{}, {}, {}, {}];
ps.forEach((p, k) => {
  const d = DESAFIOS[k], a = armas[k], M = v => tagm(k, d.T, v);
  a.portoes = (a.portoes || []).concat([[d.T, M(d.portao[0]), 0.0, d.portao[1]]]);
  a.portao = a.portao || { periodo: 6.5, fecha_s: 0.55, fechada_s: 1.2, abre_s: 1.2 };
  if (d.piso) {
    if (a.pontes) a.pontes = a.pontes.concat([[d.T, M(d.piso[0]), M(d.piso[1])]]);
    else a.lajes = (a.lajes || []).concat([[d.T, M(d.piso[0]), M(d.piso[1]), false]]);
  }
  // Aceleradores contrários: [trecho, m, lateral do meio da placa, meia largura, velocidade para trás] — lados alternados
  extras[k].re = d.re.map((v, j) => [d.T, M(v), j % 2 ? -1.8 : 1.8, 3.2, 14]);
  // Mola: [trecho, m do meio, altura, comprimento (padrão 5 m)]
  extras[k].ej = [[d.T, M(d.mola), ALTURA_MOLA].concat(d.mola_comp ? [d.mola_comp] : [])];
  for (const [T, v] of d.molas_soltas || []) extras[k].ej.push([T, tagm(k, T, v), ALTURA_MOLA]);
  for (const il of d.ilhas_soltas || []) (extras[k].ilhas = extras[k].ilhas || []).push(il);
  extras[k].cps = [[d.T, M(d.de) - 45]];
  d.lados.forEach((lado, j) => desvios[k].push(lateral_facil(k, 'L' + (j + 1), d.T, M(d.de), M(d.para), lado, 65, 38, 1.5)));
  for (const [T, v, lado, tipo] of d.molas || []) {
    const m = tagm(k, T, v);
    // Plataformas redondas: [trecho, m0, m1, raio, passo] — menos e maiores (pedido do dono: eram 16 de 6 m de raio)
    if (tipo === 'ilhas') (extras[k].ilhas = extras[k].ilhas || []).push([T, m - 62, m + 150, 10, 23.5]);
    else extras[k].ej.push([T, m, ALTURA_MOLA]);
    extras[k].cps.push([T, m - 155]);
    // Ao lado das plataformas o desvio é bem estreito e bem mais comprido que o antigo (~310 m → ~1000 m), com 6 pernas (metade das curvas da primeira versão, a pedido do dono)
    if (tipo === 'ilhas') desvios[k].push(lateral_estreita(k, 'M' + T, T, m - 110, m + 190, lado, 1000));
    else desvios[k].push(lateral_facil(k, 'M' + T, T, m - 110, m + 190, lado, 55, 0, 1));
  }
});

// Zonas a evitar: estreitos (chicanes), túneis por bocas, salto (fim do B e começo do C)
function zonas(p) {
  const z = [];
  for (const t of [p.A, p.B, p.C]) for (const e of t.estreitos) z.push([t.nome, e[0] - 14, e[1] + 14, 'estreito']);
  z.push(['B', p.B.m - 110, p.B.m + 1, 'salto']);
  z.push(['C', 0, 40, 'pouso']);
  z.push(['C', p.C.m - 120, p.C.m + 1, 'rampa final']);
  z.push(['A', 0, 230, 'largada']);
  for (const t of [p.A, p.B, p.C]) for (const l of t.loops) z.push([t.nome, l[0] - 45, l[0] + l[4] + 35, 'looping']);
  for (const d of desvios[ps.indexOf(p)] || []) z.push([d.de[0], d.de[1] - 40, d.para[1] + 30, 'desvio']);
  if (p.def.plat.sem_piso) z.push(['A', p.A.m - 130, p.A.m + 1, 'salto do poço']);
  return z;
}
function itens(a) {
  const l = [];
  for (const t of TIPOS1) for (const it of a[t] || []) l.push([it[0], it[1], it[1] + COMP[t], t]);
  for (const t of TIPOS2) for (const it of a[t] || []) l.push([it[0], it[1], it[2], t]);
  return l;
}
// Conferência das armadilhas
ps.forEach((p, k) => {
  const a = armas[k];
  const its = itens(a);
  for (const it of its) {
    const T = p[it[0]];
    if (it[2] > T.m - 5) console.log(`!! E${k + 1} ${it[3]} ${it[0]} ${it[1]} passa do fim do trecho (${T.m.toFixed(0)})`);
    for (const z of zonas(p)) if (it[0] === z[0] && it[2] > z[1] && it[1] < z[2] && it[3] !== 'avalanches' && z[3] !== 'desvio') console.log(`!! E${k + 1} ${it[3]} ${it[0]} ${it[1]}-${it[2]} em cima de ${z[3]} ${z[1].toFixed(0)}-${z[2].toFixed(0)}`);
  }
  for (let i = 0; i < its.length; i++) for (let j = i + 1; j < its.length; j++) {
    if (its[i][3] === 'avalanches' || its[j][3] === 'avalanches') continue;
    if (its[i][0] === its[j][0] && its[i][2] + 40 > its[j][1] && its[i][1] < its[j][2] + 40) console.log(`!! E${k + 1} armadilhas coladas`, its[i], its[j]);
  }
});

// Checkpoints automáticos: a cada ~300 m, fora de armadilha (50 m antes até 25 m depois), estreito, salto e pouso
const cps = ps.map((p, k) => {
  const its = itens(armas[k]);
  const zs = zonas(p).filter(z => z[3] !== 'largada');
  const lista = [];
  for (const T of ['A', 'B', 'C']) {
    const t = p[T];
    let ultimo = T === 'A' ? 0 : -1000;
    for (let m = 20; m < t.m - 45; m += 5) {
      if (m - ultimo < 300) continue;
      let ok = true;
      for (const it of its) if (it[0] === T && it[3] !== 'avalanches' && m > it[1] - 50 && m < it[2] + 25) ok = false;
      for (const it of its) if (it[0] === T && it[3] === 'avalanches' && m > it[1] - 20 && m < it[2] + 10) ok = false;
      for (const z of zs) if (z[0] === T && m > z[1] && m < z[2]) ok = false;
      if (!ok) continue;
      lista.push([T, m]);
      ultimo = m;
    }
  }
  // Na E3, um checkpoint logo antes da avalanche (quem ressurge espera a nuvem passar ali)
  for (const av of armas[k].avalanches || []) {
    const m = av[1] - 40;
    if (!lista.some(c => c[0] === av[0] && Math.abs(c[1] - m) < 30)) lista.push([av[0], m]);
  }
  // Um checkpoint logo antes de cada looping (quem cai dele volta ali)
  for (const T of ['A', 'B', 'C']) for (const l of p[T].loops) lista.push([T, Math.round(l[0] - 40)]);
  // Logo antes de cada desafio / mola; se cair dentro de uma chicane, vai para antes dela (quem ressurge precisa de reta até o portão)
  for (const c of extras[k].cps || []) {
    let m = c[1];
    for (const e of p[c[0]].estreitos) if (m > e[0] - 16 && m < e[1] + 16) m = e[0] - 14;
    lista.push([c[0], m]);
  }
  if (p.def.plat.sem_piso) { lista.push(['B', 62]); lista.push(['A', Math.round(p.A.m - 150)]); }   // logo depois do pouso do poço
  lista.sort((a, b) => 'ABC'.indexOf(a[0]) - 'ABC'.indexOf(b[0]) || a[1] - b[1]);
  // Dois checkpoints colados: fica o de depois
  return lista.filter((c, i) => !(i + 1 < lista.length && lista[i + 1][0] === c[0] && lista[i + 1][1] - c[1] < 60));
});

// ------------------------------------------------------------------ túneis (etapa 1) e aberturas para as armadilhas
const tuneis = ps.map((p, k) => {
  const l = [];
  for (const T of ['A', 'B', 'C']) for (const q of p[T].tuneis) {
    const camaras = [];
    const aberturas = [];
    if (k === 0 && T === 'B') { camaras.push([p.B.m - 120, p.B.m + 40, 16, 22]); camaras.push([880, 980, 13, 18]); }
    if (k === 0 && T === 'C') camaras.push([-40, 110, 16, 22]);
    // (sem nicho na parede para os raptores do túnel: viraram cortina de lava e o nicho era um buraco preto feio)
    for (const it of armas[k].mordidas || []) if (it[0] === T) aberturas.push([it[1], it[3], 8.0, 11.0, 0.0]);
    l.push([T, q[0], q[1], camaras, aberturas]);
  }
  return l;
});

// ------------------------------------------------------------------ alvos
const alvos = ps.map(p => p.alvo.map(Math.round));
const rampas = ps.map(p => [p.C.fim.x, p.C.fim.y, p.C.fim.z]);
const rumos = ps.map(p => p.C.fim.h);

// ------------------------------------------------------------------ rios e lagos de lava (longe das estradas baixas)
const todas = [];
ps.forEach((p, k) => { for (const t of [p.A, p.B, p.C]) for (const q of t.pts) todas.push([q[0], q[1], q[2], k]); });
ps.forEach((p, k) => { for (const d of desvios[k] || []) for (const q of d.pontos) todas.push([q[0], q[1], q[2], k]); });
function rio_ok(ang) {
  for (let r = 220; r <= V.base + 120; r += 20) {
    const a = ang * D + 0.11 * Math.sin(r / 95 + ang) + 0.05 * Math.sin(r / 37);
    const x = V.x + Math.cos(a) * r, z = V.z + Math.sin(a) * r;
    const nivel = Math.max(vulcao(x, z), 6.5) - 3.5;
    for (const q of todas) if (Math.hypot(q[0] - x, q[2] - z) < 45 && q[1] - nivel < 25) return false;
    for (const al of alvos) if (Math.hypot(al[0] - x, al[1] - z) < 200) return false;
  }
  return true;
}
const rios = [];
for (const ang of [0, 20, 40, 55, 75, 95, 150, 180, 205, 240, 270, 290, 310, 340]) {
  if (rios.length >= 6) break;
  if (rio_ok(ang)) rios.push([ang, 9]);
  else console.log('rio de lava descartado em', ang);
}
const lagos = [];   // (o lago de lava do alvo da etapa 1 virou cratera de meteoro, a pedido do dono)

// ------------------------------------------------------------------ estruturas do parque
const seg = (p, a, b) => { const dx = b[0] - a[0], dz = b[1] - a[1]; const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / (dx * dx + dz * dz))); return Math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dz * t); };
function livre(x, z, folga, alto) {
  for (const q of todas) if (Math.hypot(q[0] - x, q[2] - z) < folga && q[1] - 6 < alto) return false;
  for (let k = 0; k < 4; k++) {
    if (Math.hypot(alvos[k][0] - x, alvos[k][1] - z) < 200) return false;
    if (seg([x, z], [rampas[k][0], rampas[k][2]], alvos[k]) < 150 && alto > 20) return false;
    for (const R of [ps[k].def.largada, ps[k].def.plat]) if (Math.hypot(R.o[0] - x, R.o[2] - z) < 110) return false;
  }
  if (vulcao(x, z) > 30) return false;
  for (const l of lagos) if (Math.hypot(l[0] - x, l[1] - z) < l[2] + 30) return false;
  const v = mundo.vale; if (x < v[0] + 60 || x > v[2] - 60 || z < v[1] + 60 || z > v[3] - 60) return false;
  return true;
}
const objetos = [];
// Portão do parque logo depois da largada de cada etapa (a estrada passa pelo vão de 23 m)
ps.forEach((p, k) => {
  const t = p.A; let mm = 0, i = 1;
  while (i < t.pts.length - 1 && mm < 50) { mm += Math.hypot(t.pts[i][0] - t.pts[i - 1][0], t.pts[i][2] - t.pts[i - 1][2]); i++; }
  const q = t.pts[i];
  const h = Math.atan2(t.pts[i + 1][0] - t.pts[i - 1][0], -(t.pts[i + 1][2] - t.pts[i - 1][2])) / D;
  // 6º = altura (-9999 = no chão), 7º = etapa: só existe na etapa dele (os das outras ficavam perdidos no mato, sem estrada)
  objetos.push(['portao', r1(q[0]), r1(q[2]), r1(-h), 4.4, -9999, k + 1]);
});
// Cercas elétricas: fileiras paralelas às estradas baixas, 40 m para o lado.
// Desligadas (pedido do dono, 2026-10-03): lances soltos de 3 peças no mato, vistos da estrada, pareciam cerca perdida.
if (false) ps.forEach((p, k) => {
  for (const t of [p.A, p.C]) {
    let mm = 0;
    let fila = 0;
    for (let i = 1; i < t.pts.length - 1; i++) {
      const a = t.pts[i - 1], b = t.pts[i];
      mm += Math.hypot(b[0] - a[0], b[2] - a[2]);
      if (mm < 260 || b[1] > 120) continue;
      if (Math.floor(mm / 420) === fila) continue;
      fila = Math.floor(mm / 420);
      const dx = b[0] - a[0], dz = b[2] - a[2], l = Math.hypot(dx, dz);
      const lado = (fila % 2 ? 1 : -1);
      for (let s = 0; s < 3; s++) {
        const x = b[0] - dz / l * 42 * lado + dx / l * s * 19.4, z = b[2] + dx / l * 42 * lado + dz / l * s * 19.4;
        if (!livre(x, z, 30, 8)) break;
        objetos.push(['cerca', r1(x), r1(z), r1(-Math.atan2(dx, -dz) / D + 90), 1.0]);
      }
    }
  }
});
// Recintos dos raptores, jaula, ruínas e crânio de tricerátopo em lugares livres perto das estradas
const procurar = (tipo, perto, raio_min, raio_max, folga, alto, escala, qtd, semente) => {
  let rnd = semente;
  const rand = () => { rnd = (rnd * 16807) % 2147483647; return rnd / 2147483647; };
  let feitos = 0;
  for (let tent = 0; tent < 600 && feitos < qtd; tent++) {
    const a = rand() * Math.PI * 2, r = raio_min + rand() * (raio_max - raio_min);
    const x = perto[0] + Math.cos(a) * r, z = perto[1] + Math.sin(a) * r;
    if (!livre(x, z, folga, alto)) continue;
    if (objetos.some(o => o[0] !== 'cerca' && Math.hypot(o[1] - x, o[2] - z) < 160)) continue;
    objetos.push([tipo, r1(x), r1(z), Math.round(rand() * 360), escala]);
    feitos++;
  }
};
procurar('recinto', [1200, 600], 150, 450, 60, 30, 2.2, 2, 11);
procurar('recinto', [-2200, 900], 150, 500, 60, 30, 2.2, 1, 13);
// (a jaula solta no mato saiu a pedido do dono) procurar('jaula', [600, 300], 100, 500, 50, 20, 0.035, 1, 17);   // o modelo da jaula está em centímetros
procurar('ruina', [-2300, -1200], 200, 700, 60, 70, 3.2, 2, 19);
procurar('ruina', [900, -600], 200, 700, 60, 70, 3.2, 1, 23);
procurar('cranio', [-100, 700], 120, 400, 50, 40, 5.0, 1, 29);
procurar('cranio', [-1800, 1200], 120, 400, 50, 40, 5.0, 1, 31);
// Gigantes caminhando pelo ambiente da etapa 4 (pedido do dono): rondas [x, z, [[espécie, comprimento, raio, vel]]]
// em clareiras a 200–420 m da estrada da etapa, com a volta inteira em lugar livre
const rondas = {};
{
  const k = 3, achadas = [];
  const pk = [];
  for (const t of [ps[k].A, ps[k].B, ps[k].C]) for (const q of t.pts) pk.push(q);
  const grupos = [[['titanossauro', 125, 120, 5.5], ['espinossauro', 62, 75, -7]], [['titanossauro', 105, 110, -5], ['trex', 52, 70, 7.5]], [['titanossauro', 135, 125, 5], ['tiranossauro', 48, 80, -7]],
    [['titanossauro', 115, 115, -5.2], ['alossauro', 45, 70, 7]]];
  const v = mundo.vale;
  for (let x = v[0] + 200; x < v[2] - 200 && achadas.length < grupos.length; x += 90) for (let z = v[1] + 200; z < v[3] - 200 && achadas.length < grupos.length; z += 90) {
    let dmin = 1e9;
    for (const q of pk) dmin = Math.min(dmin, Math.hypot(q[0] - x, q[2] - z));
    if (dmin < 200 || dmin > 420) continue;
    if (achadas.some(a => Math.hypot(a[0] - x, a[1] - z) < 600)) continue;
    const R = grupos[achadas.length][0][2] * 1.1;
    let ok = true;
    for (let a = 0; a < 16 && ok; a++) ok = livre(x + Math.cos(a / 16 * 2 * Math.PI) * R, z + Math.sin(a / 16 * 2 * Math.PI) * R, 45, 70);
    if (ok && !objetos.some(o => Math.hypot(o[1] - x, o[2] - z) < R + 40)) achadas.push([x, z, grupos[achadas.length]]);
  }
  rondas[String(k + 1)] = achadas;
  console.log('rondas E4', achadas.map(a => [a[0], a[1]]).join(' | '));
}
console.log('objetos', objetos.length, objetos.filter(o => o[0] !== 'cerca').map(o => o[0]).join(','));

// ------------------------------------------------------------------ percursos
const vagas = [[4, -39, 0], [4, -28, 0], [4, -17, 0], [4, -6, 0], [4, 6, 0], [4, 17, 0], [4, 28, 0], [4, 39, 0],
  [16, -41, 90], [30, -41, 90], [44, -41, 90], [58, -41, 90], [16, 41, -90], [30, 41, -90], [44, 41, -90], [58, 41, -90]];
const buracos = [
  (s) => [[22, -22 * s, 6], [30, 24 * s, 6], [52, 0, 7], [70, -28 * s, 6], [74, 20 * s, 6], [88, -6 * s, 5]],
  (s) => [[18, -20 * s, 5.5], [24, 20 * s, 6], [42, -4 * s, 7], [46, 28 * s, 5], [60, -26 * s, 5.5], [64, 10 * s, 6], [78, -12 * s, 5], [80, 24 * s, 5]],
  (s) => [[16, -22 * s, 5.5], [22, 18 * s, 6], [38, -6 * s, 7], [42, 26 * s, 5], [54, -26 * s, 5.5], [58, 8 * s, 6], [70, -14 * s, 5], [74, 24 * s, 5], [82, -30 * s, 4.5]],
  (s) => [[18, -24 * s, 6], [24, 22 * s, 6.5], [40, -6 * s, 7], [46, 30 * s, 5.5], [58, -30 * s, 6], [62, 10 * s, 6.5], [74, -16 * s, 5.5], [78, 26 * s, 5], [88, -2 * s, 5], [90, -32 * s, 4.5], [92, 34 * s, 4.5]],
];
// Os dez últimos forram a porta de entrada (pedido do dono): quem entra sem pular é jogado para dentro, na direção
// do buraco em frente. Duas fileiras de cinco, da parede até 14 m para dentro e 4 m além de cada lado da porta —
// com três placas dava para contornar; agora só passa quem pula.
// (os dez aceleradores da porta agora são postos pelo próprio jogo em todos os mapas: Recinto.forrar_portas)
const imp_plat = (s, comp, xe) => [[comp * 0.34, 34 * s, -35 * s, false], [comp * 0.58, -40 * s, 0, false], [comp * 0.76, 2 * s, 0, false]];
const placas = ['NINHO DE LAVA', 'RECINTO DOS TITÃS', 'FLANCO OESTE', 'ÚLTIMO REFÚGIO'];
const zonas_pouso = [{ largura: 16, comprimento: 220, transicao: 50 }, { largura: 15, comprimento: 220, transicao: 50 }, { largura: 15, comprimento: 210, transicao: 50 }, { largura: 14, comprimento: 200, transicao: 50 }];
// Etapas à noite (pedido do dono): tochas na beira da estrada no lugar do neon e asfalto cinza-claro
const tochas = [false, true, true, true];
const asfalto = [null, [0.4, 0.41, 0.42], [0.4, 0.41, 0.42], [0.3, 0.3, 0.31]];
const percursos = {};
ps.forEach((p, k) => {
  const L = p.def.largada, P = p.def.plat, a = armas[k];
  const arm = {};
  for (const c of Object.keys(a)) if (c !== 'impulsos' && c !== 'catapultas') arm[c] = a[c];
  const estreitos = [];
  // (o estreito que cai em cima de plataformas redondas avulsas sai: ali não há pista)
  for (const t of [p.A, p.B, p.C]) for (const e of t.estreitos)
    if (!(DESAFIOS[k].ilhas_soltas || []).some(il => il[0] === t.nome && il[1] < e[1] && il[2] > e[0])) estreitos.push([t.nome, e[0], e[1], e[2]]);
  const plat = { origem: P.o, frente: dir4(P.h), comprimento: P.comp, largura: P.larg, saida_largura: P.sem_piso ? 18 : 10, sem_piso: !!P.sem_piso, muro_altura: 2.6, grade_altura: 8.5, placa: placas[k], portico_arte: 'res://assets/dino/portao/extinction_day.png',
    entradas: P.sem_piso ? [] : [[P.s, P.xe, 12]], porta_acelerada: !P.sem_piso, buracos: buracos[k](P.s).concat(P.sem_piso ? [] : [[P.xe, 18 * P.s, 5]]).map(b => [Math.round(b[0] * P.comp / 100), Math.round(b[1] * P.larg / 100), b[2]]),
    impulsos: imp_plat(P.s, P.comp, P.xe).slice(0, 3).map(i => [Math.round(i[0]), Math.round(i[1] * P.larg / 100), i[2], i[3]]) };
  const pc = {
    _: p.def.nome,
    largada: { origem: L.o, frente: dir4(L.h), comprimento: L.comp, largura: L.larg, saida_largura: 10, muro_altura: 2.6, grade_altura: 7.4, placa: 'EXTINCTION DAY', portico_arte: 'res://assets/dino/portao/extinction_day.png', impulsos: [[52, 0, 0, true]], vagas },
    plataforma: plat,
    trechos: { A: pts(p.A), B: pts(p.B), C: pts(p.C) },
    estreitos,
    impulsos: a.impulsos,
    zona_pouso: zonas_pouso[k],
    largura_inicio: { largura: 20, comprimento: 170, transicao: 60 },
    meio_fio_inicio: 110,
    checkpoints: { pontos: cps[k], fantasma_s: 3.0, raio: 6.5, altura: 6.0 },
    armadilhas: arm,
  };
  if (tuneis[k].length) pc.tuneis = tuneis[k];
  // Loopings: [trecho, m da entrada, raio no topo, transição, desvio lateral, aceleradores, velocidade mínima (m/s)]
  const loopings = [];
  for (const t of [p.A, p.B, p.C]) for (const l of t.loops) loopings.push([t.nome, l[0], l[1], l[2], l[3], 10, 26]);
  if (loopings.length) pc.loopings = loopings;
  if (tochas[k]) pc.tochas = true;
  if (asfalto[k]) pc.asfalto = asfalto[k];
  if (desvios[k] && desvios[k].length) pc.desvios = desvios[k];
  pc.impulsos_re = extras[k].re;
  pc.ejetores = extras[k].ej;
  if (extras[k].ilhas) pc.ilhas_pista = extras[k].ilhas;
  if (a.catapultas) { pc.catapultas = a.catapultas.map(c => [c[0], c[1], VAO_CATAPULTA, c[2]]); pc.catapulta = { periodo: 4.0, ativo_s: 0.7, vel_h: 20, vel_v: 16, raio: 4.3 }; }
  percursos[String(k + 1)] = pc;
});

// Rota dos bots no voo: no sentido do lançamento, direto ao alvo
const rotas = {};
for (let k = 0; k < 4; k++) rotas[String(k + 1)] = { capsulas: [], rota: [[Math.round((rampas[k][0] + alvos[k][0]) / 2), Math.round((rampas[k][2] + alvos[k][1]) / 2)]] };

const chao = (x, z) => Math.max(6.5, vulcao(x, z));
// Cratera de impacto em volta do alvo da etapa 4 (o meteoro caído fica no fundo dela)
const CRATERA = { raio: 78, prof: 14, borda: 10, nivel: 6.5 };
const mapa = {
  id: 'extinction_day',
  imagem: 'res://assets/ui/mapa_extinction_day.jpg',
  nome: 'Extinction Day',
  tipo: 'subida',
  ambiente: 'dino',
  descricao: 'Parque dos dinossauros no dia do meteoro: túnel por dentro do vulcão, dinossauros soltos, avalanche em brasa e o impacto final.',
  _ambiente: 'Mesmas regras do Climb to Death (corrida com checkpoints, ressurge no último checkpoint, só os primeiros 30% pontuam, ejetor a corrida toda, freio). Cenário: scripts/mundo/dino.gd (vulcão, lava, floresta gigante, estruturas do parque), tunel_vulcao.gd, dinos_parque.gd, ceu_dino.gd; armadilhas em armadilhas_dino.gd; alvos em alvo_dino.gd; impacto final em efeitos/impacto_meteoro.gd. Traçado gerado por tools/extinction_day.',
  sobrepor: {
    bots: { agressividade: [0.65, 1.0], meta: { nome: 'Subir, derrubar e pontuar', _meta: 'Pedido do dono: chegar ao fim continua sendo a meta, mas os bots atacam quem está no caminho (chao), se defendem de quem vem de lado (defesa: pulo com o ejetor ou freada) e revidam quem bate neles (revide). Depois ele pediu bots MAIS agressivos e competitivos: agressividade alta, ataque também no ar e no alvo, largam antes e andam mais rápido.', ataques: { chao: 1.6, ar: 1.0, alvo: 1.0 }, defesa: 1.0, revide: 1.6, pouso_lento: true, espera: 0.4, _coragem: 'Pedido do dono (bots lentos no portão da jaula): mais rápidos e corajosos. velocidade multiplica o ritmo na estrada e nas curvas; armadilha_vel_max = velocidade máxima ao passar numa armadilha (m/s; padrão 19); armadilha_folga = folga de tempo antes/depois dela (1 = prudente; menor = passa mais em cima).', velocidade: 1.16, armadilha_vel_max: 30, armadilha_folga: 0.45 } },
    mapa: {
      _distancia: 'Da rampa final até o alvo.',
      distancia_saida_alvo: 800,
      alvo_altura: 50,
      semente_terreno: 6560,
      _nivel_agua: 'Sem água: o líquido deste mapa é a lava (mortal pela altura, ver Dino.altura).',
      nivel_agua: -30,
      subida: {
        _subida: 'Extinction Day. Mundo: x = leste, z = sul. Cada etapa tem um percurso (percursos.N: largada, plataforma, trechos A/B/C, estreitos, impulsos, checkpoints, armadilhas e túneis), gerado por tools/extinction_day (node bloco.js config/jogo.json).',
        _desvios: 'percursos.N.desvios: bifurcações [{nome, tipo (ilhas | catapulta | estrada), placa, de/para: [trecho, m] onde sai e volta à estrada, pontos, largura, peso_bots, ilhas [[x, y, z, raio]], catapulta {pos, deck, raio, vel_h, vel_v, periodo, ativo_s}}]. plataforma.sem_piso: poço de lava (atravessa de paraquedas). tochas / asfalto [r, g, b]: etapas à noite.',
        _tuneis: 'percursos.N.tuneis: [trecho, m0, m1, câmaras [[m0, m1, meia-largura, altura]], aberturas [[m, lado (0 = os dois), meia-largura ao longo da estrada, altura, fundo do nicho]]]. As bocas ficam onde a encosta natural passa 3 m acima do arco.',
        tema: 'dino',
        largura_estrada: 10,
        meio_fio_inicio: 110,
        impulso_velocidade: 16,
        rota_pela_rampa: true,
        vale: mundo.vale,
        barreiras: { fileiras: [] },
        vegetacao: [0, 0, 0],
        montanhas: { face: 50, fixas: [], etapas: rotas },
        checkpoints: { fantasma_s: 3.0, raio: 6.5, altura: 6.0 },
        percursos,
        dino: {
          penhasco: 330,
          vulcao: { centro: [V.x, V.z], borda: V.borda, base: V.base, altura: V.altura, fundo: V.fundo, lava: V.fundo + 8 },
          _rios_lava: 'Rios de lava descendo o vulcão: [ângulo em graus (de +x para +z), meia-largura].',
          rios_lava: rios,
          _crateras: 'Crateras de impacto [x, z, raio, profundidade, altura da borda, nível do chão] (a do alvo da etapa 4, com o meteoro caído no fundo).',
          crateras: [[alvos[2][0], alvos[2][1], CRATERA.raio + 12, CRATERA.prof, CRATERA.borda, CRATERA.nivel, true],   // etapa 3: igual à da etapa 1 (pedido do dono)
            [alvos[0][0], alvos[0][1], CRATERA.raio + 12, CRATERA.prof, CRATERA.borda, CRATERA.nivel, true]],   // etapa 1: com dinossauros mortos e ossadas
          _lagos_lava: 'Lagos de lava [x, z, raio, nível].',
          lagos_lava: lagos,
          tunel: { meia_largura: 9.0, altura: 13.0 },
          _objetos: 'Estruturas do parque [tipo, x, z, giro em graus, escala] (modelos em assets/dino/<tipo>).',
          objetos,
          _rondas: 'Gigantes caminhando pelo ambiente, por etapa: {etapa: [[x, z, [[espécie, comprimento, raio da volta, velocidade]]]]} (scripts/mundo/ronda_dino.gd, sem colisão).',
          rondas,
          arvores: { sequoias: 2200, araucarias: 2200, copas: 4200, fetos: 9000, cicas: 5000, samambaias: 26000, perto_estrada: 0.45 },
          dinos: { titanossauros: 5, trex: 3, tiranossauros: 2, espinossauros: 3, carnotauros: 3, alossauros: 3, ceratossauros: 3, raptores: 4, pterossauros: 26 },
        },
      },
    },
    alvo: { _zonas: 'Alvo de uma zona só: tocar em qualquer parte vale 10 pontos (como no Climb to Death).', zonas: [[10, 15.0]] },
    regras: { corrida: { fracao_pontuam: 0.3, pontos: [10, 5, 3] }, ejetor_sempre: true, freios_instalados: true },
    fisica: { ejetor_recarga: 5.0 },
    _partida: '7 min por etapa (pedido do dono).',
    partida: { tempo_segundos: 420 },
    _etapas: 'forma: ninho | sela | jaula | pegada (AlvoDino). trajeto: geiser (sobe e desce na lava), tita (nas costas do titanossauro andando em círculo), pendulo (jaula no guindaste). ceu: noite, aurora, apocalipse, cinzas, nuvens, bolas_de_fogo e o meteoro {azimute, elevacao, tamanho, cauda, comprimento, aproxima, elevacao_final, tamanho_final}. impacto: o meteoro cai na pista no fim da etapa.',
    etapas: [
      { nome: 'Boca do Vulcão', forma: 'meteoro', bacia: 26, fundo: 6.5, raio_meteoro: 27, deslocamento: alvos[0], altura: CRATERA.nivel - CRATERA.prof + 27.5,
        ceu: { noite: 0.0, aurora: 0.0, nuvens: 0.4, meteoro: { azimute: rumos[0] + 14, elevacao: 9, tamanho: 0.35, cauda: 35, comprimento: 3.5, brilho: 1.0 } },
        _etapa: 'Dia. O parque, a floresta gigante e metade da etapa por dentro do vulcão: lava escorrendo nas paredes, raptores de tocaia, a mordida do T-Rex, pedras do teto, gêiseres e lajes de basalto que quebram sobre a lava. Alvo: ninho gigante numa coluna de basalto que sobe e desce no gêiser do lago de lava.' },
      { nome: 'Noite da Aurora', forma: 'ninho', bacia: 12, fundo: 1.6, giro_forma: rumos[1], deslocamento: alvos[1], altura: chao(alvos[1][0], alvos[1][1]) + 24.1,
        ceu: { noite: 1.0, aurora: 1.0, nuvens: 0.3, meteoro: { azimute: rumos[1] + 12, elevacao: 14, tamanho: 0.75, cauda: 30, comprimento: 7.0, brilho: 1.1 } },
        _etapa: 'Noite com aurora boreal, a pista à luz de tochas e os carros de farol aceso. Catapultas de madeira que lançam o carro por cima de um vão sem pista, raptores, portões dos recintos, titanossauros atravessando, pontes suspensas, o poço de lava no lugar da plataforma (atravessa-se de paraquedas) e a bifurcação do C: ilhas de basalto, a estrada ou o gêiser que lança o carro para o deque alto. Alvo (pedido do dono): fixo, côncavo e pequeno — um ninho de dinossauro em cima de um pórtico de pedra em ruína; cabem dois carros e os ovos quebram quando o carro cai neles.' },
      { nome: 'Fuga da Encosta', tempo_mult: 1.0, forma: 'meteoro', bacia: 26, fundo: 6.5, raio_meteoro: 27, deslocamento: alvos[2], altura: CRATERA.nivel - CRATERA.prof + 27.5,
        ceu: { noite: 1.0, aurora: 0.8, nuvens: 0.55, cinzas: 0.35, meteoro: { azimute: rumos[2] - 12, elevacao: 18, tamanho: 1.5, cauda: 40, comprimento: 12.0, brilho: 1.25 } },
        _etapa: 'Noite: quatro molas ejetoras na ladeira, a subida pelo flanco do vulcão com pedras, gêiseres e lajes. Alvo (pedido do dono): igual ao da etapa 1 — o meteoro caído com a bacia funda no topo, dentro da cratera com as carcaças e as ossadas.' },
      { nome: 'Impacto', forma: 'jaula', raio_rede: 11, altura_grade: 9, deslocamento: alvos[3], altura: 55, altura_helicoptero: 44, trajeto: { tipo: 'oito', comprimento: 100, largura: 40, periodo: 80, direcao: rumos[3] + 90 }, impacto: true, impacto_antes_rampa: 380,
        ceu: { noite: 0.3, apocalipse: 1.0, cinzas: 1.0, bolas_de_fogo: 6, meteoro: { azimute: rumos[3] - 10, elevacao: 22, elevacao_final: 38, tamanho: 3.0, tamanho_final: 14.0, aproxima: true, cauda: 25, comprimento: 20.0, brilho: 1.2 } },
        chuva_voo: { quantidade: 10, tamanho: 3.0 },
        _etapa: 'O meteoro chegando: pedaços dele caem em pontos marcados da pista e muitos cruzam o voo depois da rampa final. Alvo (pedido do dono): o helicóptero de resgate — o saco de rede pendurado no gancho; entra-se por cima da boca da rede, e bater no helicóptero ou no rotor explode o carro. No fim do tempo o helicóptero vai embora levando quem pousou na rede e o meteoro cai e explode tudo.' },
    ],
  },
};
let txt = JSON.stringify(mapa, null, '\t');
const linha = s => s.replace(/\s*\n\s*/g, ' ').replace(/\[ /g, '[').replace(/ \]/g, ']');
txt = txt.replace(/\[[^\[\]{}]*\]/g, m => linha(m));
txt = txt.replace(/\[(\s*\[[^\[\]{}]*\],?)+\s*\]/g, m => linha(m));
txt = txt.split('\n').map(l => '\t\t' + l).join('\n');
fs.writeFileSync(__dirname + '/bloco.txt', txt);
const caminho = process.argv[2];
if (caminho) {
  let jogo = fs.readFileSync(caminho, 'utf8').replace(/\r\n/g, '\n');
  const marca = '\n\t],\n\n\t"mapa": {';
  const ini = jogo.indexOf(',\n\t\t{\n\t\t\t"id": "extinction_day"');
  if (ini >= 0) jogo = jogo.slice(0, ini) + jogo.slice(jogo.indexOf(marca));
  const pos = jogo.indexOf(marca);
  if (pos < 0) { console.log('marca não achada'); process.exit(1); }
  jogo = jogo.slice(0, pos) + ',\n' + txt + jogo.slice(pos);
  JSON.parse(jogo);
  fs.writeFileSync(caminho, jogo);
  console.log('inserido', txt.length);
}
for (let k = 0; k < 4; k++) console.log(ps[k].def.nome, 'chão no alvo', chao(alvos[k][0], alvos[k][1]).toFixed(1), 'alvo', alvos[k], 'rampa', rampas[k].map(Math.round), 'checkpoints', cps[k].length, JSON.stringify(cps[k]));
console.log('rios', JSON.stringify(rios));
desenhar(__dirname + '/mapa.png', mundo, ps, { pontos: objetos.map(o => [o[1], o[2], o[0] === 'cerca' ? 4 : 14, o[0] === 'cerca' ? [120, 200, 255] : [255, 255, 255]]) });
