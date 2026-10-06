// Biblioteca dos geradores de etapa do Serpent's Climb feitos pelo desenho do dono (percurso_e3.js, percurso_e4.js).
// Cada etapa dá: o traço inteiro (pontos [x, z] do desenho), onde fica a plataforma do meio e o salto, o alvo (poço com
// ninho) e uma função que monta os desafios pelos metros de cada trecho. Esta parte monta largada, trechos A/B/C,
// alturas, a reta final apontada para o alvo, confere (raio, rampa, folga onde a pista passa por cima dela mesma) e
// grava só a etapa no jogo.json.
const fs = require('fs');
const r1 = v => Math.round(v * 10) / 10;
const V = (x, z) => [x, z];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const mul = (a, k) => [a[0] * k, a[1] * k];
const len = a => Math.hypot(a[0], a[1]);
const nrm = a => mul(a, 1 / len(a));
const cruz = (a, b) => a[0] * b[1] - a[1] * b[0];
const suave = t => t * t * (3 - 2 * t);

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
const tracar = (ctrl, fixo0, fixo1, alisa = 40) => reamostrar(alisar(reamostrar(catmull(ctrl), 1).pts, alisa, fixo0, fixo1), 1);
function perfil(tr, fn) {
  const s = [0];
  for (let i = 1; i < tr.pts.length; i++) s.push(s[i - 1] + len(sub(tr.pts[i], tr.pts[i - 1])));
  return tr.pts.map((p, i) => [p[0], fn(s[i], tr.total, p), p[1]]);
}
function desce(pts, passo) {
  const out = [];
  let acc = Infinity;
  for (let i = 0; i < pts.length; i++) {
    if (i > 0) acc += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][2] - pts[i - 1][2]);
    if (acc >= passo || i === pts.length - 1) { out.push(pts[i]); acc = 0; }
  }
  return out;
}
const saida = p => p.map(q => [r1(q[0]), r1(q[1]), r1(q[2])]);

// def: {n, nome, ctrl, plat: índice do ponto do traço onde fica a plataforma, salto: índice do ponto do salto,
//       alvo [x, z], plat_y, labio, topo, vao, desafios(ctx) → {armadilhas, impulsos, ejetores, ilhas_pista,
//       impulsos_re, rochas, cobra_toca, checkpoints_extra}, etapa: campos de etapas[n-1]}
function gerar(def) {
  const ARQ = process.argv[2] || __dirname + '/../../config/jogo.json';
  const ctrl = def.ctrl.map(p => p.slice());
  const ALVO = def.alvo, ALVO_Y = -165.5;
  const PLAT_Y = def.plat_y ?? 60, LABIO = def.labio ?? 120, TOPO = def.topo ?? 220, VAO = def.vao ?? 40;
  // Largada: os carros saem na direção do 1º trecho do traço
  const f0 = nrm(sub(ctrl[1], ctrl[0]));
  const larg_origem = sub(ctrl[0], mul(f0, 72));
  // Plataforma: centro no ponto `plat`; sai na direção em que a pista segue, entra pelo lado de onde ela vem
  const PC = ctrl[def.plat];
  const vem = nrm(sub(PC, ctrl[def.plat - 1]));
  const vai = nrm(sub(ctrl[def.plat + 1], PC));
  const L = 100;
  const lat = [-vai[1], vai[0]];   // frente × cima (Recinto.lateral) no plano [x, z]
  const lado = Math.sign(-(vem[0] * lat[0] + vem[1] * lat[1])) || 1;   // chega pelo lado oposto ao rumo de chegada
  const centroLado = add(PC, mul(lat, lado * (L / 2)));
  const ENTRA = add(centroLado, mul(lat, lado * 3));
  const ANTES = add(centroLado, mul(lat, lado * 70));
  const origem = sub(PC, mul(vai, L / 2));
  const SAI = add(PC, mul(vai, L / 2 + 1));
  const DEPOIS = add(PC, mul(vai, L / 2 + 70));
  // Salto: no ponto `salto`, na direção da pista ali
  const SJ = ctrl[def.salto];
  const dS = nrm(sub(ctrl[def.salto + 1], ctrl[def.salto - 1]));
  const LAB = sub(SJ, mul(dS, VAO / 2)), POU = add(SJ, mul(dS, VAO / 2));
  const ctrlA = [...ctrl.slice(0, def.plat - 1), ANTES, ENTRA];
  // Reta de 140 m até o lábio do salto (a curva fica antes dela, suavizada): sem isso o lábio caía numa quina
  // e o carro trancava (E4, 2026-10-06). Pontos do desenho a menos de 170 m do lábio saem.
  const meioB = ctrl.slice(def.plat + 2, def.salto - 1).filter(p => len(sub(p, LAB)) > 170);
  const ctrlB = [SAI, DEPOIS, ...meioB, sub(LAB, mul(dS, 140)), sub(LAB, mul(dS, 70)), LAB];
  const ctrlC0 = [POU, add(POU, mul(dS, 60)), add(POU, mul(dS, 130)), ...ctrl.slice(def.salto + 2)];
  const A = tracar(ctrlA, 140, 80);
  const B = tracar(ctrlB, 100, 20);   // alisa até perto do lábio (a reta final é de pontos alinhados: continua reta)
  const A3 = perfil(A, (s, Lt) => s < 200 ? 10 + 4 * s / 200 : 14 + (PLAT_Y - 14) * suave((s - 200) / (Lt - 200)));
  const B3 = perfil(B, (s, Lt) => {
    if (s < 110) return PLAT_Y + 3 * s / 110;
    const y = PLAT_Y + 3 + (LABIO - 2.3 - PLAT_Y - 3) * suave(Math.min(1, (s - 110) / (Lt - 14 - 110)));
    return s > Lt - 14 ? y + 2.3 * (s - (Lt - 14)) / 14 : y;
  });
  const PISO_POUSO = LABIO - 1.8 - 12;
  const fimTraco = ctrl[ctrl.length - 1];
  const U = nrm(sub(fimTraco, ALVO));
  let D = 560, C, C3, SAIDA;
  for (let it = 0; it < 5; it++) {
    SAIDA = add(ALVO, mul(U, D));
    const ctrlC = [...ctrlC0.slice(0, -1), add(ALVO, mul(U, D + 130)), add(ALVO, mul(U, D + 60)), SAIDA];
    C = tracar(ctrlC, 60, 150, 30);
    C3 = perfil(C, (s, Lt) => {
      if (s < 100) return LABIO - 1.8 - 12 * s / 100;
      if (s < 240) return PISO_POUSO;
      if (s < Lt - 45) return PISO_POUSO + (TOPO - PISO_POUSO) * suave((s - 240) / (Lt - 45 - 240));
      const t = (s - (Lt - 45)) / 45;
      return TOPO + 8 * t * t;
    });
    D = Math.round(540 * Math.sqrt((C3[C3.length - 1][1] - ALVO_Y) / 360));
  }
  const metros = (tr, p) => { let m = Infinity, k = 0; tr.pts.forEach((q, i) => { const d = len(sub(q, p)); if (d < m) { m = d; k = i; } }); return Math.round(k * tr.total / (tr.pts.length - 1)); };
  const naPista = (tr, m) => tr.pts[Math.max(0, Math.min(tr.pts.length - 1, Math.round(m / tr.total * (tr.pts.length - 1))))];
  const tr = { A, B, C };
  const ctx = {
    A, B, C, V, add, sub, mul, nrm, len, naPista,
    m: (nome, p) => metros(tr[nome], p),
    // trecho e metros do ponto do desenho mais perto de p (o trecho que passa mais perto)
    onde: p => { let melhor = null; for (const n of ['A', 'B', 'C']) { const m = metros(tr[n], p); const d = len(sub(naPista(tr[n], m), p)); if (!melhor || d < melhor[2]) melhor = [n, m, d]; } return [melhor[0], melhor[1]]; },
    total: n => Math.round(tr[n].total),
    // ponto ao lado da pista (lado +1 = direita de quem vai) a `dist` m do eixo, no meio de [m0, m1]
    aoLado: (nome, m0, m1, lado, dist) => {
      const t = tr[nome], p = naPista(t, (m0 + m1) / 2), d = nrm(sub(naPista(t, m1), naPista(t, m0)));
      return add(p, mul([-d[1], d[0]], -lado * dist)).map(Math.round);
    },
    // n rochas encostadas ao longo de [m0, m1] (acompanham a curva), de frente para a pista (cuspidoras)
    rochasArco: (nome, m0, m1, lado, n, larg = 130) => {
      const t = tr[nome], modelos = ['penhasco_a', 'penhasco_b', 'penhasco_c'], out = [];
      for (let k = 0; k < n; k++) {
        const mk = m0 + (k + 0.5) * (m1 - m0) / n;
        const p = naPista(t, mk), d = nrm(sub(naPista(t, mk + 15), naPista(t, mk - 15)));
        const o = mul([-d[1], d[0]], -lado);
        const q = add(p, mul(o, larg * 0.6));
        out.push([Math.round(q[0]), Math.round(q[1]), larg, modelos[k % 3], 0, 0, 0, 1.25, 1, null, Math.round(Math.atan2(o[1], o[0]) * 180 / Math.PI), 19, [nome, 0, 99999]]);   // encosta medindo o trecho inteiro (a curva não volta para dentro da rocha)
      }
      return out;
    },
  };
  // ------------------------------------------------------------ conferência
  console.log('E%d comprimentos A %d B %d C %d total %d m', def.n, A.total, B.total, C.total, A.total + B.total + C.total + VAO);
  for (const [n, t] of [['A', A], ['B', B], ['C', C]]) { const [r, o] = raioMinimo(t.pts); console.log('raio mínimo %s %d m em %s', n, r, o.map(Math.round)); }
  const declive = p => { let m = 0, o = null; for (let i = 1; i < p.length; i++) { const g = Math.abs(p[i][1] - p[i - 1][1]) / Math.max(len(sub([p[i][0], p[i][2]], [p[i - 1][0], p[i - 1][2]])), 0.01); if (g > m) { m = g; o = [p[i][0], p[i][2]]; } } return [m, o]; };
  for (const [n, t] of [['A', A3], ['B', B3.slice(0, -16)], ['C', C3.slice(0, -50)]]) { const [g, o] = declive(t); console.log('rampa máx %s %s%% em %s', n, (g * 100).toFixed(1), o.map(Math.round)); }
  console.log('saída da rampa', SAIDA.map(Math.round), 'altura', r1(C3[C3.length - 1][1]), 'distância ao alvo', D);
  {
    const todos = [...A3.map(p => ['A', p]), ...B3.map(p => ['B', p]), ...C3.map(p => ['C', p])];
    const lista = [];
    for (let i = 0; i < todos.length; i += 3) for (let j = i + 80; j < todos.length; j += 3) {
      const a = todos[i][1], b = todos[j][1];
      if (Math.abs(a[0] - b[0]) < 14 && Math.abs(a[2] - b[2]) < 14 && Math.abs(a[1] - b[1]) < 16) lista.push([todos[i][0], todos[j][0], Math.round(a[0]), Math.round(a[2]), r1(a[1]), r1(b[1])]);
    }
    console.log('cruzamentos com menos de 16 m de folga: %d %s', lista.length, JSON.stringify(lista.slice(0, 6)));
  }
  // ------------------------------------------------------------ grava
  const json = JSON.parse(fs.readFileSync(ARQ, 'utf8'));
  const mapa = json.mapas.find(m => m.id === 'serpents_climb');
  const s = mapa.sobrepor.mapa.subida;
  const p1 = s.percursos['1'];
  const d = def.desafios(ctx);
  const k = String(def.n);
  const percurso = {
    _: `E${def.n} ${def.nome} (feita do zero pelo desenho do dono, 2026-10-06; gerado por tools/serpents_climb/percurso_e${def.n}.js)`,
    largada: Object.assign({}, p1.largada, { origem: [Math.round(larg_origem[0]), 10, Math.round(larg_origem[1])], frente: f0.map(v => r1(v)) }),
    plataforma: Object.assign({}, p1.plataforma, { origem: [Math.round(origem[0]), PLAT_Y, Math.round(origem[1])], frente: vai.map(v => Math.round(v * 1000) / 1000),
      placa: def.placa || 'TEMPLO DA SERPENTE', entradas: [[lado, L / 2, 12]] }),
    trechos: { A: saida(desce(A3, 22)), B: saida([...desce(B3.slice(0, -30), 22), ...desce(B3.slice(-30), 7)]), C: saida([...desce(C3.slice(0, -60), 18), ...desce(C3.slice(-60), 8)]) },
    ilhas_pista: d.ilhas_pista || [],
    impulsos: d.impulsos,
    impulsos_re: d.impulsos_re || [],
    ejetores: [['C', -10, 22, 10, 1.7, true], ...(d.ejetores || [])],
    zona_pouso: { largura: 16, comprimento: 240, transicao: 60 },
    largura_inicio: { largura: 20, comprimento: 170, transicao: 60 },
    checkpoints: { pontos: d.checkpoints, fantasma_s: 3, raio: 6.5, altura: 6 },
    armadilhas: d.armadilhas,
  };
  if (!percurso.impulsos_re.length) delete percurso.impulsos_re;
  const e1 = s.montanhas.etapas['1'];
  s.montanhas.etapas[k] = { _: `E${def.n}: o mesmo vale da E1, com o poço do alvo no buraco desenhado.`, poco: [ALVO[0], ALVO[1], 40, -194],
    preencher: e1.preencher, capsulas: e1.capsulas, rota: [add(ALVO, mul(U, 400)), add(ALVO, mul(U, 260)), add(ALVO, mul(U, 130))].map(p => p.map(Math.round)) };
  const se1 = s.selva.etapas['1'];
  s.selva.etapas[k] = { _: `E${def.n}: o mesmo rio, cachoeira e paredões da E1; rochas das cuspidoras e montanhas novas.`,
    rio: se1.rio, lagos: se1.lagos, cachoeira: se1.cachoeira, rochas_paredoes: true, rochas_livres: se1.rochas_livres,
    rochas: [...se1.rochas.filter(r => r.length < 13), ...(d.rochas || [])] };
  if (d.cobra_toca) {
    const toca = s.selva.cobra_toca;
    toca.etapas = [...new Set([...toca.etapas, def.n])].sort();
    toca.por_etapa = toca.por_etapa || {};
    toca.por_etapa[k] = d.cobra_toca;
  }
  if (d.cobra_arena) s.selva.cobra_arena.etapas = [...new Set([...s.selva.cobra_arena.etapas, def.n])].sort();
  const et = mapa.sobrepor.etapas[def.n - 1];
  Object.assign(et, { nome: def.nome, deslocamento: ALVO, altura: ALVO_Y, diametro: def.diametro || 22,
    tempo_mult: Math.round((A.total + B.total + C.total) / 8500 * (def.tempo_fator || 1.6) * 10) / 10 }, def.etapa || {});
  et._poco = `Alvo no ninho em cima da pirâmide do fundo do poço (montanhas.etapas.${k}.poco, PocoNinho).`;
  s.percursos[k] = percurso;
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
      return '{\n' + ks.map(q => tab + '\t' + JSON.stringify(q) + ': ' + ser(v[q], nivel + 1)).join(',\n') + '\n' + tab + '}';
    }
    return JSON.stringify(v);
  }
  if (process.env.SO_CONFERIR) { console.log('(só conferência: nada gravado)'); return; }
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
  fs.writeFileSync(ARQ, texto.slice(0, ini) + ser(mapa, nivel) + texto.slice(fimTxt));
  console.log('gravado em', ARQ);
}
module.exports = { gerar, V };
