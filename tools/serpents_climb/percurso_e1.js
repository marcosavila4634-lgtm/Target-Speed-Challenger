// Serpent's Climb, etapa 1 refeita pelo desenho do dono (2026-10-05, duas capturas da câmera livre F3):
//  - traçado novo (vermelho): largada → volta na pirâmide do oeste → grampos → plataforma → norte pelo
//    lago → leste → desce pelo flanco leste da pirâmide do leste e salta para o alvo (Pirâmide da Lua);
//  - anel de montanhas (marrom) em volta de tudo, com os dois braços do cânion por onde o rio sai;
//  - cobra 1 (a gigante que já existia) vai da largada até a pirâmide do alvo, dá a volta nela e volta;
//  - cobra 2 anda dentro da plataforma dos buracos e dá o bote; cobra 3 sai de uma toca numa montanha
//    colada na pista e atravessa a estrada.
// Os pontos de controle vieram dos traços nas fotos, projetados no chão pela câmera livre ajustada às
// pirâmides, ao lago e à largada (erro de ~15 px).
//
// Uso: node tools/serpents_climb/percurso_e1.js [config/jogo.json]   (reescreve só o bloco do serpents_climb)
const fs = require('fs');
const ARQ = process.argv[2] || __dirname + '/../../config/jogo.json';
const r1 = v => Math.round(v * 10) / 10;
const V = (x, z) => [x, z];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const mul = (a, k) => [a[0] * k, a[1] * k];
const len = a => Math.hypot(a[0], a[1]);
const nrm = a => mul(a, 1 / len(a));

// ------------------------------------------------------------------ curvas
// Catmull-Rom centrípeta pelos pontos, amostrada a ~1 m.
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
// Reamostra a cada `passo` m (pontos igualmente espaçados, ponta incluída).
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
// Alisa (média com os vizinhos) sem mexer nas pontas fixas (metros no começo e no fim).
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
    const d = len(sub(pts[i + 6], pts[i - 6]));
    const r = ang > 1e-4 ? d / ang : Infinity;
    if (r < menor) { menor = r; onde = pts[i]; }
  }
  return [menor, onde];
}
function tracar(ctrl, fixo0, fixo1, alisa = 60) {
  const fino = alisar(reamostrar(catmull(ctrl), 1).pts, alisa, fixo0, fixo1);
  return reamostrar(fino, 1);
}

// ------------------------------------------------------------------ traçado (pontos de controle [x, z])
const PLAT = { origem: [-1300, 100, -350], frente: [1, 0], comprimento: 100, largura: 100 };
const ALVO = [219, 56];
// Rampa final: a reta aponta para o alvo (u = do alvo para a rampa); saída a 540 m dele
const U = nrm(sub(V(765, -112), ALVO));
const SAIDA = add(ALVO, mul(U, 540));
const RETA_FINAL = add(ALVO, mul(U, 660));

const ctrlA = [
  V(-1590, 908), V(-1590, 860), V(-1590, 810), V(-1594, 775),           // sai da largada para o norte
  V(-1625, 735), V(-1690, 725), V(-1770, 755), V(-1855, 800),           // oeste, até a pirâmide do oeste
  V(-1960, 782), V(-2030, 700), V(-2028, 595), V(-1960, 512),           // volta por fora dela
  V(-1860, 492), V(-1760, 512), V(-1640, 575), V(-1500, 600),           // e segue para leste
  V(-1360, 588), V(-1200, 550), V(-1020, 480), V(-860, 420),
  V(-760, 360), V(-725, 290), V(-760, 220), V(-850, 180),               // grampo
  V(-980, 178), V(-1120, 186), V(-1270, 194), V(-1420, 186),
  V(-1530, 150), V(-1565, 85), V(-1530, 25), V(-1450, -10),             // grampo do oeste
  V(-1370, -45), V(-1300, -95), V(-1262, -160), V(-1250, -215),
  V(-1250, -255), V(-1250, -297),                                         // entra na plataforma pela lateral sul
];
const ctrlB = [
  V(-1199, -350), V(-1150, -350), V(-1100, -352), V(-1040, -362),       // sai pela frente da plataforma
  V(-960, -385), V(-880, -430), V(-830, -500), V(-815, -590),
  V(-840, -680), V(-900, -770), V(-965, -860), V(-1005, -945),
  V(-1016, -990), V(-1020, -1030),                                         // reta do salto (norte)
];
const VAO = 30;   // vão do salto entre B e C
const ctrlC0 = [V(-1020, -1030 - VAO)];
const ctrlC = [
  ...ctrlC0, V(-1022, -1080), V(-1026, -1140), V(-1028, -1200),           // pouso, ainda reto
  V(-1005, -1290), V(-940, -1360), V(-850, -1395), V(-760, -1370),       // contorna o sul do lago
  V(-695, -1300), V(-668, -1200), V(-660, -1100), V(-650, -1000),
  V(-625, -900), V(-590, -800), V(-545, -715), V(-480, -650),            // desce ao lado do rio
  V(-400, -622), V(-330, -614), V(-260, -610),                            // reta da toca da cobra 3
  V(-170, -625), V(-100, -680), V(-60, -770), V(-30, -880),
  V(-5, -990), V(30, -1080), V(100, -1140), V(185, -1150), V(250, -1110), // grampo do norte
  V(300, -1020), V(350, -920), V(430, -790), V(530, -680),
  V(630, -605), V(740, -565), V(830, -530), V(885, -470),                 // passa ao norte da pirâmide do leste
  V(905, -380), V(905, -300), V(902, -240),                                // desce pelo flanco leste
  [RETA_FINAL[0] + 50, RETA_FINAL[1] - 55], RETA_FINAL,                    // vira para o alvo
  add(ALVO, mul(U, 600)), SAIDA,
];
const A = tracar(ctrlA, 140, 90);
const B = tracar(ctrlB, 100, 70);
const C = tracar(ctrlC, 60, 150, 50);

// ------------------------------------------------------------------ alturas (rampa de no máx. ~8,5%)
function perfil(tr, fn) {
  const s = [0];
  for (let i = 1; i < tr.pts.length; i++) s.push(s[i - 1] + len(sub(tr.pts[i], tr.pts[i - 1])));
  return tr.pts.map((p, i) => [p[0], fn(s[i], tr.total), p[1]]);
}
const suave = t => t * t * (3 - 2 * t);
// A: 10 → 100; os primeiros 200 m quase planos (os 16 carros saem juntos)
const A3 = perfil(A, (s, L) => s < 200 ? 10 + 6 * s / 200 : 16 + 84 * ((s - 200) / (L - 200)));
// B: plano 110 m na saída da plataforma, sobe até a beirada do salto e o lábio levanta 2,3 m nos últimos 14 m
const LABIO = 150;
const B3 = perfil(B, (s, L) => {
  if (s < 110) return 100 + 3 * s / 110;
  const y = 103 + (LABIO - 2.3 - 103) * suave(Math.min(1, (s - 110) / (L - 14 - 110)));
  return s > L - 14 ? y + 2.3 * (s - (L - 14)) / 14 : y;
});
// C: rampa de pouso (desce 12% nos primeiros 100 m), plano, sobe devagar e chuta na rampa final
const PISO_POUSO = LABIO - 1.8 - 12;
const TOPO = 186;
const C3 = perfil(C, (s, L) => {
  if (s < 100) return LABIO - 1.8 - 12 * s / 100;
  if (s < 220) return PISO_POUSO;
  if (s < L - 45) return PISO_POUSO + (TOPO - PISO_POUSO) * suave((s - 220) / (L - 45 - 220));
  const t = (s - (L - 45)) / 45;
  return TOPO + 8 * t * t;   // chute da rampa final
});
const saida = p => p.map(q => [r1(q[0]), r1(q[1]), r1(q[2])]);
const metros = (tr, ponto) => {   // metros do começo do trecho até a amostra mais perto de `ponto`
  let melhor = Infinity, k = 0;
  tr.pts.forEach((p, i) => { const d = len(sub(p, ponto)); if (d < melhor) { melhor = d; k = i; } });
  return Math.round(k * tr.total / (tr.pts.length - 1));
};
const naPista = (tr, m) => tr.pts[Math.round(m / tr.total * (tr.pts.length - 1))];

// ------------------------------------------------------------------ anel de montanhas (marrom)
// Anel fechado (o dono mandou preencher com terra tudo o que fica fora dele: montanhas.etapas.1.preencher).
// No oeste e no sul ele encosta na beirada do vale (passa por fora da volta na pirâmide do oeste).
const anel = [
  [V(-60, 1000), V(20, 627), 70, 190], [V(20, 627), V(508, 596), 75, 200], [V(508, 596), V(840, 420), 75, 210],
  [V(840, 420), V(1060, 60), 80, 220], [V(1060, 60), V(1075, -380), 80, 230], [V(1075, -380), V(880, -760), 80, 220],
  [V(880, -760), V(560, -1080), 75, 210], [V(560, -1080), V(370, -1270), 70, 200], [V(370, -1270), V(104, -1330), 65, 190],
  [V(104, -1330), V(-230, -1320), 60, 180], [V(-230, -1320), V(-371, -1480), 60, 190], [V(-371, -1480), V(-524, -1724), 65, 200],
  [V(-524, -1724), V(-870, -1830), 50, 200],
  [V(-870, -1830), V(-1062, -1617), 70, 200], [V(-1062, -1617), V(-1245, -1376), 70, 210], [V(-1245, -1376), V(-1336, -1159), 70, 200],
  [V(-1336, -1159), V(-1501, -981), 70, 200], [V(-1501, -981), V(-1580, -896), 65, 190], [V(-1580, -896), V(-1494, -705), 65, 190],
  [V(-1494, -705), V(-1568, -310), 65, 200], [V(-1568, -310), V(-1640, -90), 60, 190], [V(-1640, -90), V(-1800, 40), 60, 190],
  [V(-1800, 40), V(-2000, 200), 65, 200], [V(-2000, 200), V(-2110, 383), 65, 210],
  [V(-2110, 383), V(-2135, 735), 40, 200], [V(-2135, 735), V(-1975, 965), 45, 190], [V(-1975, 965), V(-1739, 1070), 50, 190],
  [V(-1739, 1070), V(-1437, 1144), 50, 190], [V(-1437, 1144), V(-1266, 1048), 50, 190],
  [V(-1266, 1048), V(-1081, 881), 70, 190], [V(-1081, 881), V(-788, 768), 70, 200], [V(-788, 768), V(-522, 728), 70, 190],
  [V(-522, 728), V(-430, 860), 65, 190], [V(-430, 860), V(-420, 1050), 65, 190],
];
// Montanha da toca da cobra 3: colada na lateral norte da reta (-400..-260, z ≈ -615), parede quase reta
const TOCA_M = metros(C, V(-330, -614));
const tocaP = naPista(C, TOCA_M);
const tocaT = nrm(sub(naPista(C, TOCA_M + 10), naPista(C, TOCA_M - 10)));
let tocaN = [tocaT[1], -tocaT[0]];                  // lateral: para o lado da montanha (norte)
if (tocaN[1] > 0) tocaN = mul(tocaN, -1);
const RAIO_TOCA = 85;
const eixo = add(tocaP, mul(tocaN, RAIO_TOCA + 9));
const montanhaToca = { _: 'Montanha da toca da cobra 3 (parede reta colada na pista)', a: add(eixo, mul(tocaT, -55)).map(Math.round), b: add(eixo, mul(tocaT, 55)).map(Math.round), raio: [RAIO_TOCA, RAIO_TOCA], altura: 250, face: 12, liso: true };

// ------------------------------------------------------------------ cobra 1: largada → pirâmide do alvo → volta
const ida = reamostrar(catmull([V(-1470, 870), V(-1420, 885), V(-1350, 860), V(-1300, 800), V(-1262, 700), V(-1240, 590), V(-1225, 470),
  V(-1180, 360), V(-1160, 240), V(-1125, 120), V(-1070, 20), V(-990, -35), V(-880, -40), V(-655, -10), V(-380, 55), V(-150, 120), V(40, 125)]), 1);
const OFS = 16;
function deslocar(pts, d) {
  return pts.map((p, i) => {
    const t = nrm(sub(pts[Math.min(i + 1, pts.length - 1)], pts[Math.max(i - 1, 0)]));
    return add(p, mul([-t[1], t[0]], d));
  });
}
const idaD = reamostrar(deslocar(ida.pts, OFS), 45).pts;
const voltaD = reamostrar(deslocar(ida.pts, -OFS), 45).pts.reverse();
// Volta inteira na pirâmide do alvo (meia-base 75): círculo de 125 m, sentido horário visto de cima
const centro = ALVO;
const aIda = Math.atan2(idaD[idaD.length - 1][1] - centro[1], idaD[idaD.length - 1][0] - centro[0]);
const aVolta = Math.atan2(voltaD[0][1] - centro[1], voltaD[0][0] - centro[0]);
const giro = [];
let fim = aVolta;
while (fim > aIda - 0.3) fim -= 2 * Math.PI;   // dá a volta inteira antes de voltar
for (let a = aIda - 0.35; a > fim + 0.35; a -= 0.32) giro.push(add(centro, mul([Math.cos(a), Math.sin(a)], 125)));
// Ponta da largada: meia volta larga
const p0 = idaD[0], p1 = voltaD[voltaD.length - 1];
const meio = mul(add(p0, p1), 0.5);
const giro0 = [add(meio, [-40, 30]), add(meio, [-55, -5])];
const rotaCobra1 = [...idaD.slice(0, -1), ...giro, ...voltaD.slice(1), ...giro0].map(p => p.map(Math.round));

// ------------------------------------------------------------------ cobra 2: volta dentro da plataforma
// [x a partir da entrada da frente, lateral (+ = sul)]; buracos (x, lat, r): (22,-22,6) (30,24,6) (52,0,7) (70,-28,6) (74,20,6) (88,-6,5)
// Achada por busca (corpo de 9 m de grossura a pelo menos 0,3 m dos buracos e da cerca, sem se cruzar; 351 m)
const voltaArena = [[23, 13], [11, -19], [20, -37], [55, -17], [55, -32], [67, -39], [81, -33], [77, -1], [75, -1], [85, 17], [85, 35], [52, 28], [56, 36], [14, 32], [21, 6]];

// ------------------------------------------------------------------ conferência
const lA = A.total, lB = B.total, lC = C.total;
console.log('comprimentos A %d B %d C %d total %d m', lA, lB, lC, lA + lB + lC + VAO);
for (const [n, t] of [['A', A], ['B', B], ['C', C]]) { const [r, o] = raioMinimo(t.pts); console.log('raio mínimo %s %d m em %s', n, r, o.map(Math.round)); }
const declive = p => { let m = 0; for (let i = 1; i < p.length; i++) m = Math.max(m, Math.abs(p[i][1] - p[i - 1][1]) / Math.max(len(sub([p[i][0], p[i][2]], [p[i - 1][0], p[i - 1][2]])), 0.01)); return m; };
console.log('rampa máx A %s%% B %s%% C(até o chute) %s%%', (declive(A3) * 100).toFixed(1), (declive(B3.slice(0, -16)) * 100).toFixed(1), (declive(C3.slice(0, -50)) * 100).toFixed(1));
const pir = [[-1250, -350, 150], [700, -350, 130], [-1700, -1420, 120], [219, 56, 75], [-1880, 650, 70], [950, 760, 60], [-150, -1450, 80]];
for (const [n, t] of [['A', A3], ['B', B3], ['C', C3]]) for (const [px, pz, mb] of pir) {
  let menor = Infinity;
  for (const q of t) menor = Math.min(menor, Math.max(Math.abs(q[0] - px), Math.abs(q[2] - pz)) - mb);
  if (menor < 40 && !(px === -1250)) console.log('  %s passa a %d m da pirâmide (%d,%d)', n, menor, px, pz);
}
// distância das estradas às montanhas do anel (borda)
const distSeg = (p, a, b) => { const ab = sub(b, a); const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / (ab[0] ** 2 + ab[1] ** 2))); return len(sub(p, add(a, mul(ab, t)))); };
let pior = Infinity, piorOnde = null;
for (const t of [A3, B3, C3]) for (const q of t) for (const [a, b, r] of anel) { const d = distSeg([q[0], q[2]], a, b) - r; if (d < pior) { pior = d; piorOnde = [q[0], q[2]]; } }
console.log('folga mínima estrada → pé do anel: %d m em %s', pior, piorOnde.map(Math.round));
console.log('saída da rampa', SAIDA.map(Math.round), 'altura', C3[C3.length - 1][1], 'distância ao alvo', Math.round(len(sub(SAIDA, ALVO))));
console.log('toca da cobra 3: C %d m em %s, eixo da montanha %s', TOCA_M, tocaP.map(Math.round), eixo.map(Math.round));
// cruzamentos da cobra 1 com a estrada (altura da estrada ali)
for (const [n, t] of [['A', A3], ['B', B3], ['C', C3]]) for (let i = 1; i < t.length; i++) for (let k = 1; k < rotaCobra1.length; k++) {
  const a = [t[i - 1][0], t[i - 1][2]], b = [t[i][0], t[i][2]], c = rotaCobra1[k - 1], d = rotaCobra1[k];
  const den = (b[0] - a[0]) * (d[1] - c[1]) - (b[1] - a[1]) * (d[0] - c[0]);
  if (Math.abs(den) < 1e-9) continue;
  const u = ((c[0] - a[0]) * (d[1] - c[1]) - (c[1] - a[1]) * (d[0] - c[0])) / den, v = ((c[0] - a[0]) * (b[1] - a[1]) - (c[1] - a[1]) * (b[0] - a[0])) / den;
  if (u >= 0 && u <= 1 && v >= 0 && v <= 1) console.log('  cobra 1 cruza %s em (%d,%d) com a estrada a %d m', n, a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, t[i][1]);
}

// ------------------------------------------------------------------ grava no jogo.json
const pA = tr => saida(tr).filter((_, i, arr) => true);
const desce = (pts, passo) => {   // ~1 ponto a cada `passo` m (o jogo refaz a curva por eles)
  const out = [];
  let acc = Infinity;
  for (let i = 0; i < pts.length; i++) {
    if (i > 0) acc += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][2] - pts[i - 1][2]);
    if (acc >= passo || i === pts.length - 1) { out.push(pts[i]); acc = 0; }
  }
  return out;
};
const trechos = { A: saida(desce(A3, 22)), B: saida(desce(B3, 22)), C: saida(desce(C3, 22)) };
// os últimos metros do lábio e do chute com pontos mais juntos (o perfil muda rápido)
trechos.B = saida([...desce(B3.slice(0, -30), 22), ...desce(B3.slice(-30), 7)]);
trechos.C = saida([...desce(C3.slice(0, -60), 22), ...desce(C3.slice(-60), 8)]);
const mC = m => Math.round(m);
const percurso = {
  _: 'E1 Escadaria do Sol (traçado do dono, 2026-10-05; gerado por tools/serpents_climb/percurso_e1.js)',
  largada: null, plataforma: null,   // preenchidos com os atuais
  trechos,
  // (a placa nunca fica antes de curva: no A, todo curvo, a de 60 m ia parar a 1,4 km)
  impulsos: [['A', mC(metros(A, V(-1400, 588)))], ['B', -62, 12], ['C', 330], ['C', mC(metros(C, V(330, -970)))], ['C', -100]],
  zona_pouso: { largura: 16, comprimento: 260, transicao: 60 },
  largura_inicio: { largura: 20, comprimento: 170, transicao: 60 },
  checkpoints: { pontos: [['A', mC(metros(A, V(-1990, 640)))], ['A', mC(metros(A, V(-1100, 520)))], ['A', mC(metros(A, V(-1300, 194)))], ['B', 150], ['C', 300],
    ['C', mC(TOCA_M - 160)], ['C', mC(TOCA_M + 120)], ['C', mC(metros(C, V(185, -1150)))], ['C', mC(metros(C, V(905, -380)))]], fantasma_s: 3, raio: 6.5, altura: 6 },
  armadilhas: {
    laminas: [['B', mC(metros(B, V(-835, -650))), 0], ['C', mC(metros(C, V(-660, -1150))), 1.1], ['C', mC(metros(C, V(-45, -830))), 2.2]],
    lamina: { periodo: 4.6, amplitude: 60, comprimento: 9.5 },
    pedra: { periodo: 11, velocidade: 12, raio: 2, padrao: 'alterna' },
  },
};

// Serializa no estilo do jogo.json: objetos em linhas (tab), listas só de números/textos/listas numa linha só.
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
const jogo = JSON.parse(texto);
const mapa = jogo.mapas.find(m => m.id === 'serpents_climb');
const s = mapa.sobrepor.mapa.subida;
const velho = s.percursos['1'];
percurso.largada = velho.largada;
percurso.plataforma = velho.plataforma;
s.percursos['1'] = percurso;
s.montanhas.etapas['1'] = {
  _: 'Escadaria do Sol (desenho do dono, 2026-10-05): anel de montanhas em volta do percurso, com os braços do cânion por onde o rio sai para o sul, e a montanha da toca da cobra 3 colada na pista.',
  preencher: { _: 'Terra preenchida (pedido do dono): dentro do vale e fora deste contorno (o eixo do anel) o chão sobe a um platô coberto de mata.',
    contorno: [[-60, 1000], ...anel.slice(1, 12).map(c => c[0]), [-524, -1724], ...anel.slice(13, 32).map(c => c[0]), [-522, 728], [-430, 860], [-420, 1050], [-400, 1300], [-80, 1300]].map(p => p.map(Math.round)),
    altura: 200 },
  capsulas: [...anel.map(([a, b, r, h]) => ({ a: a.map(Math.round), b: b.map(Math.round), raio: [r, r], altura: h })), montanhaToca],
  rota: [add(ALVO, mul(U, 400)), add(ALVO, mul(U, 260)), add(ALVO, mul(U, 130))].map(p => p.map(Math.round)),
};
// estela que ficava embaixo da volta na pirâmide do oeste
s.selva.estelas = s.selva.estelas.map(e => (e[0] === -1880 && e[1] === 520) ? [-1790, 420, 0] : e);
const sg = s.selva.serpente_gigante;
s.selva._serpente_gigante = 'Serpente gigante (cobra 1) rastejando pela mata, só enfeite: não ataca e não tem colisão. etapas: em quais aparece; comprimento e grossura em m; velocidade em m/s; serpenteio [amplitude, comprimento de onda] em m (some perto das estradas); rota: volta fechada [x, z] — na E1 (desenho do dono) vai da largada até a pirâmide do alvo, dá a volta nela e volta pelo outro lado; onde cruza a estrada tem de ser entre dois pilares e com a estrada alta o bastante (com 7 m de grossura a cobra tem 5,4 m de altura: estrada a mais de 14,5 m de altitude).';
s.selva.serpente_gigante = { etapas: sg.etapas, comprimento: sg.comprimento, grossura: sg.grossura, velocidade: sg.velocidade, serpenteio: [5, 85], inicio: 0, rota: rotaCobra1 };
s.selva._cobra_arena = 'Cobra 2 (pedido do dono): anda dentro da plataforma dos buracos (volta: pontos [x da frente, lateral] da plataforma) e dá o bote no carro que chegar a menos de `alcance` m da cabeça: o carro explode e volta ao checkpoint; depois ela descansa `descanso` s antes do próximo bote.';
s.selva.cobra_arena = { etapas: [1], comprimento: 120, grossura: 9, velocidade: 7, alcance: 20, descanso: 3, volta: voltaArena };   // 3x maior (pedido do dono)
s.selva._cobra_toca = 'Cobra 3 (pedido do dono): sai de uma toca na montanha colada na pista (trecho, metros, lado: -1 = esquerda de quem sobe; a montanha está em montanhas.etapas.N.capsulas), atravessa a estrada e volta para a toca. Com a cabeça perto da pista é muito agressiva: bote em quem passar a menos de `alcance` m, e quem encosta no corpo também explode. ciclo: [escondida, saindo, fora, voltando] em s (fixo: os bots planejam a passagem).';
s.selva.cobra_toca = { etapas: [1], trecho: 'C', metros: TOCA_M, lado: Math.sign(tocaN[0] * -tocaT[1] + tocaN[1] * tocaT[0]), comprimento: 95, grossura: 5, alcance: 14, alem: 9, ciclo: [3.4, 1.5, 1.6, 2.1] };
// Percurso ~2x mais longo: a E1 ganha tempo
mapa.sobrepor.etapas[0].tempo_mult = 1.6;
mapa.sobrepor.etapas[0]._etapa = 'Fácil (traçado novo do dono, ~8,5 km): lâminas lentas, a cobra da plataforma e a cobra da toca. Alvo no topo da Pirâmide da Lua.';

// recoloca só o objeto do mapa no texto (o resto do arquivo fica como está)
const ini = texto.lastIndexOf('{', texto.indexOf('"id": "serpents_climb"'));
let prof = 0, fimTxt = ini;
for (let i = ini; i < texto.length; i++) {
  const ch = texto[i];
  if (ch === '"') { i++; while (texto[i] !== '"') { if (texto[i] === '\\') i++; i++; } continue; }
  if (ch === '{') prof++;
  if (ch === '}') { prof--; if (prof === 0) { fimTxt = i + 1; break; } }
}
const nivel = (texto.slice(texto.lastIndexOf('\n', ini) + 1, ini).match(/\t/g) || []).length;
fs.writeFileSync(ARQ, texto.slice(0, ini) + ser(mapa, nivel) + texto.slice(fimTxt));
console.log('gravado em', ARQ);
