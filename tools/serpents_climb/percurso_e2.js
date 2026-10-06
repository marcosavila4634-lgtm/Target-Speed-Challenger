// Serpent's Climb, etapa 2 feita do zero pelo desenho do dono (2026-10-06, captura da câmera livre F3 da E1 vista
// de cima, x -570 y 2783 z -548): mesmo vale da E1 (anel de montanhas, rio, cachoeira com a cobra da toca), pista
// laranja: largada da E1 → desce em S → montanha de fogo e montanha dos machados (no sentido contrário ao da E1) →
// plataforma na curva → norte → leste → salto sobre o rio → volta grande → espiral (sobe) → desce ao sul → passa
// na cachoeira da toca → volta pelo sul → três espirais (sobem) → norte pela beira oeste → topo da pirâmide grande →
// reta para o buraco do alvo (poço com o ninho, como o da E1). Rosa = montanhas novas de rocha gigante.
// Os pontos vieram do desenho, projetados no chão pela câmera ajustada à largada, à plataforma e ao alvo da E1
// (erro ~10 px, ~4 m por px).
//
// Uso: node tools/serpents_climb/percurso_e2.js [config/jogo.json]
// Reescreve só a etapa 2 do serpents_climb (percursos.2, montanhas.etapas.2, selva.etapas.2, cobra_toca.por_etapa.2,
// etapas[1]); o resto do mapa fica como está.
const fs = require('fs');
const ARQ = process.argv[2] || __dirname + '/../../config/jogo.json';
const r1 = v => Math.round(v * 10) / 10;
const V = (x, z) => [x, z];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const mul = (a, k) => [a[0] * k, a[1] * k];
const len = a => Math.hypot(a[0], a[1]);
const nrm = a => mul(a, 1 / len(a));
const cruz = (a, b) => a[0] * b[1] - a[1] * b[0];

// ------------------------------------------------------------------ curvas (as mesmas do percurso_e1.js)
function catmull(ctrl, passo = 1) {
  const out = [];
  const P = [sub(mul(ctrl[0], 2), ctrl[1]), ...ctrl, sub(mul(ctrl[ctrl.length - 1], 2), ctrl[ctrl.length - 2])];
  for (let i = 1; i < P.length - 2; i++) {
    const [p0, p1, p2, p3] = [P[i - 1], P[i], P[i + 1], P[i + 2]];
    const t0 = 0, t1 = t0 + Math.sqrt(len(sub(p1, p0))), t2 = t1 + Math.sqrt(len(sub(p2, p1))), t3 = t2 + Math.sqrt(len(sub(p3, p2)));
    const n = Math.max(2, Math.ceil(len(sub(p2, p1)) / passo));
    for (let k = 0; k < n; k++) {
      const t = t1 + (t2 - t1) * k / n;
      const L = (a, b, ta, tb) => add(mul(a, (tb - t) / (tb - ta)), mul(b, (t - ta) / (tb - ta)));
      const A1 = L(p0, p1, t0, t1), A2 = L(p1, p2, t1, t2), A3 = L(p2, p3, t2, t3);
      const B1 = L(A1, A2, t0, t2), B2 = L(A2, A3, t1, t3);
      out.push(L(B1, B2, t1, t2));
    }
  }
  out.push(ctrl[ctrl.length - 1]);
  return out;
}
function reamostrar(pts, passo) {
  const s = [0];
  for (let i = 1; i < pts.length; i++) s.push(s[i - 1] + len(sub(pts[i], pts[i - 1])));
  const total = s[s.length - 1];
  const n = Math.max(1, Math.round(total / passo));
  const out = [];
  let j = 0;
  for (let k = 0; k <= n; k++) {
    const alvo = total * k / n;
    while (j < pts.length - 2 && s[j + 1] < alvo) j++;
    const t = (alvo - s[j]) / Math.max(s[j + 1] - s[j], 1e-6);
    out.push(add(pts[j], mul(sub(pts[j + 1], pts[j]), t)));
  }
  return { pts: out, total };
}
function alisar(pts, voltas, fixo0, fixo1) {
  const s = [0];
  for (let i = 1; i < pts.length; i++) s.push(s[i - 1] + len(sub(pts[i], pts[i - 1])));
  const total = s[s.length - 1];
  let p = pts.map(q => q.slice());
  for (let v = 0; v < voltas; v++) {
    const q = p.map(x => x.slice());
    for (let i = 2; i < p.length - 2; i++) {
      if (s[i] < fixo0 || s[i] > total - fixo1) continue;
      q[i] = mul(add(add(add(p[i - 2], p[i + 2]), mul(add(p[i - 1], p[i + 1]), 2)), mul(p[i], 2)), 1 / 8);
    }
    p = q;
  }
  return p;
}
function raioMinimo(pts) {
  let menor = Infinity, onde = null;
  for (let i = 6; i < pts.length - 6; i++) {
    const a = nrm(sub(pts[i], pts[i - 6])), b = nrm(sub(pts[i + 6], pts[i]));
    const ang = Math.acos(Math.max(-1, Math.min(1, a[0] * b[0] + a[1] * b[1])));
    const r = ang > 1e-4 ? len(sub(pts[i + 6], pts[i - 6])) / ang : Infinity;
    if (r < menor) { menor = r; onde = pts[i]; }
  }
  return [menor, onde];
}
function tracar(ctrl, fixo0, fixo1, alisa = 40) {
  return reamostrar(alisar(reamostrar(catmull(ctrl), 1).pts, alisa, fixo0, fixo1), 1);
}

// Laço da espiral: a pista vem pela reta `de` → `para`, dá uma volta inteira de raio r em volta de `centro` e segue
// (cruza por cima de si mesma: ela sobe na volta). Pontos de controle da volta, a cada ~30°.
function laco(de, para, centro, r) {
  const d = nrm(sub(para, de));
  const rel = sub(centro, de);
  const ao_longo = rel[0] * d[0] + rel[1] * d[1];
  const lado = Math.sign(cruz(d, rel)) || 1;
  const n = mul([-d[1], d[0]], lado);                 // da reta para o centro
  const T = add(de, mul(d, ao_longo));               // ponto de tangência na reta
  const c = add(T, mul(n, r));
  const pts = [];
  for (let g = 40; g <= 320; g += 35) {
    const a = g * Math.PI / 180;
    // a partir de T, indo para a frente (d) e girando para o lado do centro
    pts.push(add(c, add(mul(n, -r * Math.cos(a)), mul(d, r * Math.sin(a)))));
  }
  return { antes: add(T, mul(d, -r * 0.9)), pts, depois: add(T, mul(d, r * 0.9)) };
}

// ------------------------------------------------------------------ traçado ([x, z] do desenho)
const ALVO = V(-409, -126);              // buraco com o alvo (poço com o ninho)
const POCO = [ALVO[0], ALVO[1], 40, -194];
const ALVO_Y = -165.5;
// Plataforma na curva depois das montanhas-armadilha: a pista chega pelo lado (vindo do oeste, +x) e sai pela
// frente, para o norte (+z). lateral = frente × cima = -x → entrada no lado +1.
const PLAT_C = V(-1060, 225);            // centro da plataforma
const PLAT = { comprimento: 100, largura: 100 };
const PLAT_Y = 60;   // plataforma no chão (pedestal de tijolo): o A é curto (~1,3 km)
const PLAT_O = [PLAT_C[0], PLAT_Y, PLAT_C[1] - PLAT.comprimento / 2];
const ENTRA = V(PLAT_C[0] - PLAT.largura / 2 - 3, PLAT_C[1]);   // fim do A (lado oeste)
const SAI = V(PLAT_C[0], PLAT_O[2] + PLAT.comprimento + 1);      // começo do B (frente)

// Rio na altura do salto (z ~ 380): x ≈ -205. Lábio 35 m antes, pouso 35 m depois.
const RIO = V(-205, 385);
const VAO = 75;
const LABIO_P = V(RIO[0] - VAO / 2, RIO[1] + 6);
const POUSO_P = V(RIO[0] + VAO / 2, RIO[1] - 6);

const ctrlA = [
  V(-1590, 908), V(-1590, 860), V(-1590, 810), V(-1590, 760),            // sai da largada (a mesma da E1)
  V(-1585, 690), V(-1580, 640), V(-1620, 560), V(-1680, 470),            // desce em S pelo oeste
  V(-1693, 383), V(-1680, 300), V(-1640, 240), V(-1580, 205),
  V(-1520, 190), V(-1471, 185), V(-1420, 188), V(-1370, 192),            // montanha de fogo (~-1425)
  V(-1320, 194), V(-1270, 194), V(-1220, 196), V(-1170, 205),            // montanha dos machados (~-1282)
  V(-1135, 218), ENTRA,
];
const ctrlB = [
  SAI, V(PLAT_C[0], 330), V(-1045, 420), V(-1015, 500),                   // norte
  V(-975, 550), V(-900, 567), V(-800, 567), V(-700, 563),                 // leste (plataformas redondas)
  V(-600, 545), V(-500, 490), V(-420, 440), V(-340, 405),                 // desce para o rio
  V(LABIO_P[0] - 40, LABIO_P[1] + 6), LABIO_P,
];
const dirSalto = nrm(sub(POUSO_P, LABIO_P));
const ctrlC0 = [POUSO_P, add(POUSO_P, mul(dirSalto, 60)), add(POUSO_P, mul(dirSalto, 130))];
const LE = laco(V(250, -230), V(241, -506), V(358, -348), 95);            // espiral da esquerda
// Três espirais da direita, uma atrás da outra, na reta S0 → E1 do desenho
const S0 = V(-860, -560), S1 = V(-1330, -940);
const lacos = [V(-1036, -561), V(-1168, -671), V(-1274, -794)].map(c => laco(S0, S1, c, 85));
// Reta final: da pirâmide grande (a da plataforma da E1) para o alvo, saída a SAIDA_D m dele
const PIR = V(-1262, -300);
const U = nrm(sub(V(-1186, -285), ALVO));   // do alvo para o fim do arco em cima da pirâmide
let SAIDA_D = 600;   // ajustado abaixo pela altura da saída
const ctrlC = [
  ...ctrlC0,
  V(44, 360), V(108, 434), V(171, 477), V(300, 488), V(430, 490),         // oeste→leste pelo norte (reta do ejetor)
  V(560, 480), V(661, 413), V(707, 266), V(700, 150), V(685, 58),         // volta grande pelo leste
  V(579, -45), V(450, -78), V(340, -120), V(270, -180),
  LE.antes, ...LE.pts, LE.depois,                                           // espiral da esquerda
  V(241, -560), V(374, -663), V(398, -856), V(361, -1008),               // desce para o sul (ejetor, lâmina)
  V(239, -1158), V(142, -1185), V(48, -1102), V(15, -856),
  V(-60, -712), V(-160, -640), V(-260, -610), V(-330, -614), V(-400, -622), // cachoeira da toca (a mesma da E1)
  V(-500, -680), V(-580, -790), V(-620, -900), V(-648, -1008),
  V(-685, -1270), V(-761, -1362), V(-914, -1380), V(-1049, -1270),        // volta pelo sul
  V(-1072, -1083), V(-1051, -1008), V(-990, -860), V(-930, -740),         // rocha com as cuspidoras
  V(-870, -670), V(-800, -615), V(-775, -540), V(-815, -480), V(-880, -490), // grampo para entrar nas espirais
  ...lacos.flatMap(l => [l.antes, ...l.pts, l.depois]),                    // três espirais
  V(-1370, -960), V(-1440, -900), V(-1493, -794), V(-1512, -600),
  V(-1512, -420), V(-1512, -308), V(-1505, -160), V(-1480, -60),          // norte pela beira oeste (piso que cai)
  V(-1425, -24), V(-1345, -50),
];
// Chega por cima da pirâmide grande: arco de 120 m da descida (sul) até a direção do alvo
const ARCO_C = V(-1210, -167), ARCO_R = 120;
const arco = [];
for (let g = 180; g <= 281.5; g += 12) arco.push(add(ARCO_C, mul([Math.cos(g * Math.PI / 180), Math.sin(g * Math.PI / 180)], ARCO_R)));
const FIM_ARCO = add(ARCO_C, mul([Math.cos(281.5 * Math.PI / 180), Math.sin(281.5 * Math.PI / 180)], ARCO_R));
// fim: vira para o alvo no topo da pirâmide e reta até a saída (completa depois de saber a altura)

// ------------------------------------------------------------------ alturas
function perfilPor(tr, fn) {
  const s = [0];
  for (let i = 1; i < tr.pts.length; i++) s.push(s[i - 1] + len(sub(tr.pts[i], tr.pts[i - 1])));
  return tr.pts.map((p, i) => [p[0], fn(s[i], tr.total, p), p[1]]);
}
const suave = t => t * t * (3 - 2 * t);
const A = tracar(ctrlA, 140, 60);
const B = tracar(ctrlB, 100, 90);
// Peso da subida: nas espirais a estrada sobe ~6,5% (é para isso que elas servem); fora delas, pouco
function pertoDeLaco(p) {
  for (const [c, r] of [[V(358, -348), 95], ...[V(-1036, -561), V(-1168, -671), V(-1274, -794)].map(c => [c, 85])]) {
    // centro real do laço (o da tangência) fica perto do pedido: usa um raio folgado
    if (len(sub(p, c)) < r + 70) return true;
  }
  return false;
}
function montarC(saidaD) {
  const SAIDA = add(ALVO, mul(U, saidaD));
  const RETA = add(ALVO, mul(U, saidaD + 120));
  const ctrl = [...ctrlC, ...arco, RETA, add(ALVO, mul(U, saidaD + 60)), SAIDA];
  return { C: tracar(ctrl, 60, 150, 30), SAIDA };
}
const LABIO = 120;
const B3 = perfilPor(B, (s, L) => {
  if (s < 110) return PLAT_Y + 3 * s / 110;
  const y = PLAT_Y + 3 + (LABIO - 2.3 - PLAT_Y - 3) * suave(Math.min(1, (s - 110) / (L - 14 - 110)));
  return s > L - 14 ? y + 2.3 * (s - (L - 14)) / 14 : y;
});
const A3 = perfilPor(A, (s, L) => s < 200 ? 10 + 4 * s / 200 : 14 + (PLAT_Y - 14) * suave((s - 200) / (L - 200)));
const PISO_POUSO = LABIO - 1.8 - 12;
function perfilC(C) {
  const s = [0];
  for (let i = 1; i < C.pts.length; i++) s.push(s[i - 1] + len(sub(C.pts[i], C.pts[i - 1])));
  const L = C.total;
  // inclinação desejada por metro: 6,5% nas espirais, 0,9% no resto (depois do pouso); a reta final sobe e chuta
  const incl = C.pts.map((p, i) => s[i] < 260 ? 0 : (pertoDeLaco(p) ? 0.06 : 0.004));
  const y = [];
  for (let i = 0; i < C.pts.length; i++) {
    if (s[i] < 100) { y.push(LABIO - 1.8 - 12 * s[i] / 100); continue; }
    if (s[i] < 260) { y.push(PISO_POUSO); continue; }
    y.push(y[i - 1] + incl[i] * (s[i] - s[i - 1]));
  }
  // chute da rampa final nos últimos 45 m
  for (let i = 0; i < y.length; i++) if (s[i] > L - 45) { const t = (s[i] - (L - 45)) / 45; y[i] = y[i] + 8 * t * t; }
  return C.pts.map((p, i) => [p[0], y[i], p[1]]);
}
// A distância da saída ao alvo cresce com a queda (mesma velocidade da E1: 540 m para 360 m de queda)
let C, SAIDA, C3;
for (let it = 0; it < 4; it++) {
  ({ C, SAIDA } = montarC(SAIDA_D));
  C3 = perfilC(C);
  const queda = C3[C3.length - 1][1] - ALVO_Y;
  SAIDA_D = Math.round(540 * Math.sqrt(queda / 360));
}
({ C, SAIDA } = montarC(SAIDA_D));
C3 = perfilC(C);

const saida = p => p.map(q => [r1(q[0]), r1(q[1]), r1(q[2])]);
const metros = (tr, ponto) => {
  let melhor = Infinity, k = 0;
  tr.pts.forEach((p, i) => { const d = len(sub(p, ponto)); if (d < melhor) { melhor = d; k = i; } });
  return Math.round(k * tr.total / (tr.pts.length - 1));
};
const naPista = (tr, m) => tr.pts[Math.max(0, Math.min(tr.pts.length - 1, Math.round(m / tr.total * (tr.pts.length - 1))))];

// ------------------------------------------------------------------ conferência
console.log('comprimentos A %d B %d C %d total %d m', A.total, B.total, C.total, A.total + B.total + C.total + VAO);
for (const [n, t] of [['A', A], ['B', B], ['C', C]]) { const [r, o] = raioMinimo(t.pts); console.log('raio mínimo %s %d m em %s', n, r, o.map(Math.round)); }
const declive = p => { let m = 0, onde = null; for (let i = 1; i < p.length; i++) { const g = Math.abs(p[i][1] - p[i - 1][1]) / Math.max(len(sub([p[i][0], p[i][2]], [p[i - 1][0], p[i - 1][2]])), 0.01); if (g > m) { m = g; onde = [p[i][0], p[i][2]]; } } return [m, onde]; };
for (const [n, t] of [['A', A3], ['B', B3.slice(0, -16)], ['C', C3.slice(0, -50)]]) { const [g, o] = declive(t); console.log('rampa máx %s %s%% em %s', n, (g * 100).toFixed(1), o.map(Math.round)); }
console.log('saída da rampa', SAIDA.map(Math.round), 'altura', r1(C3[C3.length - 1][1]), 'distância ao alvo', SAIDA_D);
// cruzamentos da pista com ela mesma: folga vertical
{
  const todos = [...A3.map(p => ['A', p]), ...B3.map(p => ['B', p]), ...C3.map(p => ['C', p])];
  let pior = Infinity, ondeP = null;
  for (let i = 0; i < todos.length; i += 2) for (let j = i + 60; j < todos.length; j += 2) {
    const a = todos[i][1], b = todos[j][1];
    if (Math.abs(a[0] - b[0]) < 14 && Math.abs(a[2] - b[2]) < 14) {
      const dy = Math.abs(a[1] - b[1]);
      if (dy < pior) { pior = dy; ondeP = [todos[i][0], todos[j][0], Math.round(a[0]), Math.round(a[2]), r1(a[1]), r1(b[1])]; }
    }
  }
  console.log('menor folga vertical onde a pista passa por cima dela mesma: %s m %s', r1(pior), JSON.stringify(ondeP));
}

// ------------------------------------------------------------------ desafios
const mA = p => metros(A, p), mB = p => metros(B, p), mC = p => metros(C, p);
const FOGO = mA(V(-1425, 188)), MACHADOS = mA(V(-1282, 194));
const TOCA_M = mC(V(-330, -614));
const tocaP = naPista(C, TOCA_M);
const tocaT = nrm(sub(naPista(C, TOCA_M + 10), naPista(C, TOCA_M - 10)));
const eixoToca = [-330, -614 + 0];   // a montanha da toca fica ao norte da pista (lado do eixo da cápsula)
const json = JSON.parse(fs.readFileSync(ARQ, 'utf8'));
const mapa = json.mapas.find(m => m.id === 'serpents_climb');
const s = mapa.sobrepor.mapa.subida;
const capToca = s.montanhas.etapas['1'].capsulas.find(c => c.liso);
const meioToca = mul(add(capToca.a, capToca.b), 0.5);
const ladoToca = Math.sign((meioToca[0] - tocaP[0]) * -tocaT[1] + (meioToca[1] - tocaP[1]) * tocaT[0]);
const reta = (tr, m0, m1) => { const a = naPista(tr, m0), b = naPista(tr, m1); return Math.round(len(sub(b, a)) / Math.max(1, m1 - m0) * 100); };
console.log('fogo A %d, machados A %d, toca C %d (lado %d)', FOGO, MACHADOS, TOCA_M, ladoToca);

// Monólito encostado na volta do sul (C, entre a volta e as espirais) com as cobras cuspidoras
const CUSP = [mC(V(-1072, -1083)), mC(V(-930, -740))];
const pM = naPista(C, Math.round((CUSP[0] + CUSP[1]) / 2));
const tM = nrm(sub(naPista(C, CUSP[1]), naPista(C, CUSP[0])));
const fora = [tM[1], -tM[0]];   // lado de fora da volta (para o sul/leste): o lado oposto às espirais
const centroVolta = V(-870, -1100);
const ladoFora = Math.sign((pM[0] - centroVolta[0]) * fora[0] + (pM[1] - centroVolta[1]) * fora[1]) || 1;
const monolito = add(pM, mul(fora, ladoFora * 120));

const ilhasB = [mB(V(-930, 562)), mB(V(-640, 553))];
const ejetorC = mC(V(300, 488));
const ejetorD = mC(V(398, -820));
const placasE = [mC(V(-1512, -560)), mC(V(-1510, -260))];
const percurso = {
  _: 'E2 Boca da Serpente (feita do zero pelo desenho do dono, 2026-10-06; gerado por tools/serpents_climb/percurso_e2.js)',
  largada: s.percursos['1'].largada,
  plataforma: Object.assign({}, s.percursos['1'].plataforma, {
    origem: PLAT_O, frente: [0, 1], comprimento: PLAT.comprimento, largura: PLAT.largura, placa: 'TEMPLO DA SERPENTE', entradas: [[1, PLAT.comprimento / 2, 12]] }),
  trechos: {
    A: saida(desce(A3, 22)),
    B: saida([...desce(B3.slice(0, -30), 22), ...desce(B3.slice(-30), 7)]),
    C: saida([...desce(C3.slice(0, -60), 18), ...desce(C3.slice(-60), 8)]),
  },
  ilhas_pista: [['B', ilhasB[0], ilhasB[1], 10, 23.5]],
  impulsos: [['A', 260], ['A', mA(V(-1520, 190)) - 40], ['B', 130], ['B', -62, 12], ['C', 300], ['C', ejetorC + 160],
    ['C', mC(V(15, -900))], ['C', mC(V(-1051, -1008))], ['C', placasE[1] + 60],
    ['C', -115, 16, 'fixo'], ['C', -100, 32, 'fixo'], ['C', -85, 16, 'fixo'], ['C', -70, 16, 'fixo'], ['C', -55, 16, 'fixo'], ['C', -40, 16, 'fixo'], ['C', -25, 16, 'fixo']],
  ejetores: [['C', -10, 22, 10, 1.7, true], ['A', mA(V(-1680, 470)), 25, 100], ['C', ejetorC, 25, 100], ['C', ejetorD, 25, 100]],
  zona_pouso: { largura: 16, comprimento: 240, transicao: 60 },
  largura_inicio: { largura: 20, comprimento: 170, transicao: 60 },
  checkpoints: { pontos: [['A', mA(V(-1680, 300))], ['A', MACHADOS + 20], ['B', 150], ['B', ilhasB[1] + 30], ['C', 300],
    ['C', mC(V(661, 413))], ['C', mC(V(241, -560))], ['C', mC(V(48, -1102))], ['C', TOCA_M + 120], ['C', mC(V(-914, -1380))],
    ['C', CUSP[1] + 30], ['C', mC(V(-1493, -794))], ['C', placasE[1] + 30]], fantasma_s: 3, raio: 6.5, altura: 6 },
  armadilhas: {
    laminas: [['A', FOGO + 21, 0, 4.4, 'fogo', 3, 14, -0.8], ['A', MACHADOS + 21, 0.5, 4.4, 'rocha', 3, 14, -0.8],
      // (pedido do dono: no lugar das lâminas antigas, sempre a montanha com túnel e machados)
      ['C', mC(V(398, -945)) + 21, 0.3, 4.3, 'rocha', 3, 14, -0.8], ['C', mC(V(-648, -1050)) + 21, 2.2, 4.3, 'rocha', 3, 14, -0.8]],
    lamina: { periodo: 4.3, amplitude: 62, comprimento: 9.5 },
    lancas: [['A', mA(V(-1590, 700)), 0], ['B', mB(V(-1045, 420)), 1], ['C', mC(V(560, 480)), 0.5], ['C', mC(V(-685, -1270)), 2]],
    lanca: { periodo: 4.6, mover_s: 0.3, fora_s: 1.7, comprimento: 12 },
    serpentes: [['B', mB(V(-500, 490)), 0], ['C', mC(V(707, 230)), 1.5]],
    serpente: { periodo: 5.6, fecha_s: 0.4, fechada_s: 1.3, abre_s: 1.1 },
    jatos: [['C', TOCA_M - 120, 1, 0], ['C', mC(V(-1512, -420)), -1, 1.5]],   // [trecho, m, lado, fase]
    jato: { periodo: 4, ligado_s: 1.6, forca: 32 },   // força dobrada (pedido do dono 2026-10-06)
    placas: [['A', mA(V(-1680, 420)), mA(V(-1680, 420)) + 60], ['B', mB(V(-420, 440)), mB(V(-420, 440)) + 50], ['C', placasE[0], placasE[1]]],
    placa: { comprimento: 4, tempo_s: 0.9, volta_s: 6, aderencia: 0.9 },
    cuspidoras: [['C', CUSP[0], CUSP[1], 9]],
    cuspidora: { alcance: 65, veneno_s: 3, intervalo: [5.0, 10.0], altura_cabeca: 5.0, erro_m: 5.0 },
    quedas: [['C', mC(V(239, -1158)), mC(V(15, -856)), [0.5, 1.4]], ['C', mC(V(-685, -1270)), mC(V(-1049, -1270)), [0.6, 1.6]]],
    queda: { intervalo: [1.2, 3.5], tamanho: [3, 6], tranco: 14 },
  },
};
function desce(pts, passo) {
  const out = [];
  let acc = Infinity;
  for (let i = 0; i < pts.length; i++) {
    if (i > 0) acc += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][2] - pts[i - 1][2]);
    if (acc >= passo || i === pts.length - 1) { out.push(pts[i]); acc = 0; }
  }
  return out;
}

// ------------------------------------------------------------------ terreno, rochas, cobra da toca, alvo
const e1 = s.montanhas.etapas['1'];
s.montanhas.etapas['2'] = {
  _: 'E2 (desenho do dono 2026-10-06): o mesmo vale da E1 (anel, terra de fora, montanha da toca), com o poço do alvo no buraco novo.',
  poco: POCO,
  preencher: e1.preencher,
  capsulas: e1.capsulas,
  rota: [add(ALVO, mul(U, 400)), add(ALVO, mul(U, 260)), add(ALVO, mul(U, 130))].map(p => p.map(Math.round)),
};
const se1 = s.selva.etapas['1'];
// Montanhas de rocha gigante (rosa): rochas inteiras soltas no vale (fundo 1), bem altas
const rosas = [[-50, 757, 300, 'penhasco_c', 20, 0.25, 0, 1.5], [-4, 17, 420, 'penhasco_a', 0, 0.25, 0, 1.25],
  [848, -134, 260, 'penhasco_b', 60, 0.25, 0, 1.6], [649, -663, 260, 'penhasco_c', 300, 0.25, 0, 1.5],
  [-821, -1065, 250, 'penhasco_a', 80, 0.25, 0, 1.6], [-1934, 584, 300, 'penhasco_b', 10, 0.25, 0, 1.4]]
  .map(r => [...r, 1]);
// Rocha gigante dentro da espiral da esquerda, 30 m acima da pista (pedido do dono): duas no tamanho natural,
// uma em cima da outra (esticar na vertical deixa a pedra riscada)
rosas.push([325, -348, 95, 'penhasco_c', 0, 0.12, 0, 1.15, 1], [325, -348, 80, 'penhasco_a', 140, 0.12, 0, 1.3, 1, 68], [325, -348, 75, 'penhasco_b', 250, 0.12, 0, 1.3, 1, 130]);   // 3 empilhadas: topo ~190 m   // cabe no laço (raio ~95)
const rochasE1 = se1.rochas.filter(r => r.length < 13);   // as encostadas na pista da E1 ficam lá
s.selva.etapas['2'] = {
  _: 'E2: o mesmo rio, cachoeira e paredões da E1; montanhas de rocha gigante onde o dono pintou de rosa; monólito com as cuspidoras na volta do sul.',
  rio: se1.rio, lagos: se1.lagos, cachoeira: se1.cachoeira,
  rochas_paredoes: true, rochas_livres: se1.rochas_livres,
  rochas: [...rochasE1, ...rosas, [Math.round(monolito[0]), Math.round(monolito[1]), 300, 'penhasco_c', 0, 0, 0, 1.3, 1, null, null, 19, ['C', CUSP[0] - 40, CUSP[1] + 40]]],
};
const toca = s.selva.cobra_toca;
toca.etapas = [...new Set([...toca.etapas, 1, 2])].sort();   // (as outras etapas são dos outros geradores)
toca.por_etapa = Object.assign(toca.por_etapa || {}, { 2: { trecho: 'C', metros: TOCA_M, lado: ladoToca } });
const et = mapa.sobrepor.etapas[1];
et.deslocamento = [ALVO[0], ALVO[1]];
et.altura = ALVO_Y;
et.diametro = 22;
delete et.vento;
et.tempo_mult = Math.round((A.total + B.total + C.total) / 8500 * 1.6 * 10) / 10;
et._poco = 'Alvo no ninho em cima da pirâmide do fundo do poço (montanhas.etapas.2.poco, PocoNinho).';
et._etapa = 'Feita do zero pelo desenho do dono (2026-10-06): montanhas de fogo e dos machados, plataforma, plataformas redondas, salto sobre o rio, espirais que sobem, cachoeira com a cobra, cuspidoras, rochas caindo, pisos que caem e reta final para o poço.';
s.percursos['2'] = percurso;

// ------------------------------------------------------------------ grava
function inline(v) { return Array.isArray(v) ? v.every(x => !(x && typeof x === 'object' && !Array.isArray(x)) && (!Array.isArray(x) || inline(x))) : false; }
function ser(v, nivel) {
  const tab = '\t'.repeat(nivel);
  if (Array.isArray(v)) {
    if (inline(v)) return '[' + v.map(x => ser(x, 0)).join(', ') + ']';
    return '[\n' + v.map(x => tab + '\t' + ser(x, nivel + 1)).join(',\n') + '\n' + tab + ']';
  }
  if (v && typeof v === 'object') {
    const ks = Object.keys(v);
    if (!ks.length) return '{}';
    return '{\n' + ks.map(k => tab + '\t' + JSON.stringify(k) + ': ' + ser(v[k], nivel + 1)).join(',\n') + '\n' + tab + '}';
  }
  return JSON.stringify(v);
}
const texto = fs.readFileSync(ARQ, 'utf8');
const ini = texto.lastIndexOf('{', texto.indexOf('"id": "serpents_climb"'));
let prof = 0, fimTxt = ini;
for (let i = ini; i < texto.length; i++) {
  const ch = texto[i];
  if (ch === '"') { i++; while (texto[i] !== '"') { if (texto[i] === '\\') i++; i++; } continue; }
  if (ch === '{') prof++;
  if (ch === '}') { prof--; if (prof === 0) { fimTxt = i + 1; break; } }
}
const nivel = (texto.slice(texto.lastIndexOf('\n', ini) + 1, ini).match(/\t/g) || []).length;
if (process.env.SO_CONFERIR) { console.log('(só conferência: nada gravado)'); process.exit(0); }
fs.writeFileSync(ARQ, texto.slice(0, ini) + ser(mapa, nivel) + texto.slice(fimTxt));
console.log('gravado em', ARQ);
