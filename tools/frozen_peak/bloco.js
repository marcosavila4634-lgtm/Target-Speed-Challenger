// Monta o bloco do mapa Frozen Peak e insere no config/jogo.json.  node bloco.js <caminho do jogo.json>
const fs = require('fs');
const { ps } = require('./cursos.js');
const r1 = v => Math.round(v * 10) / 10;
const pts = t => t.pts.map(p => [r1(p[0]), r1(p[1]), r1(p[2])]);
const dirv = h => [Math.round(Math.sin(h * Math.PI / 180)), Math.round(-Math.cos(h * Math.PI / 180))];
const D = Math.PI / 180;

// ------------------------------------------------------------------ armadilhas e checkpoints por etapa
const armas = [
  { // E1 Geleira Azul (fácil): bolas de neve na chegada à fortaleza, um pingente e dois martelos lentos
    bolas: [['A', '#a6+35', '#a6+365', 0.0]], bola: { periodo: 11.0, velocidade: 12, raio: 2.0, padrao: 'alterna' },
    pingentes: [['A', '#a4+20', 0.0]], pingente: { periodo: 5.4, mover_s: 0.3, fora_s: 1.7, comprimento: 12, altura: 9.5 },
    martelos: [['B', '#b2+12', 0.0], ['C', '#c4+30', 1.1]], martelo: { periodo: 4.6, amplitude: 60, comprimento: 9.5 },
    yetis: [['A', 450], ['A', 824], ['B', 130], ['C', 360], ['C', 1300]], yeti: { segura_s: 5.0, descanso_s: 3.0 },
    // Pedido do dono (2026-10-03, no trecho da foto dele): duas focas em geleiras cospem gelo na faixa delas
    focas: [['A', 285, 0], ['B', 570, 1.2], ['C', 1180, 2]], foca: { periodo: 5.0, cuspe_s: 1.3, congela_s: 4.0 },
    impulsos: [['B', -62, 12], ['C', -100]],
    cps: [['A', '#a3+80'], ['A', '#a5+38'], ['B', '#b3+22'], ['C', 180], ['C', '#c3+35'], ['C', '#c5+45']] },
  { // E2 Passo do Yeti (médio): bolas de neve na espiral, gelo fino, prensa, turbina
    bolas: [['A', '#a4+90', '#a4+570', 0.0]], bola: { periodo: 9.5, velocidade: 13, raio: 2.0, padrao: 'alterna' },
    pingentes: [['A', '#a3+22', 0.0]], pingente: { periodo: 5.0, mover_s: 0.28, fora_s: 1.7, comprimento: 12, altura: 9.5 },
    placas: [['B', '#b0+50', '#b0+90']], placa: { tempo_s: 0.9, volta_s: 5.0, comprimento: 4.0, aderencia: 0.55 },
    martelos: [['B', '#b2+8', 0.6], ['C', '#c4+30', 2.0]], martelo: { periodo: 4.1, amplitude: 62, comprimento: 9.5 },
    yetis: [['A', 300], ['C', 110], ['C', 330]], yeti: { segura_s: 5.0, descanso_s: 3.0 },
    focas: [['B', 500, 0], ['C', 1583, 1.5]], foca: { periodo: 5.0, cuspe_s: 1.3, congela_s: 4.0 },
    prensas: [['C', '#c2+38', 0.0]], prensa: { periodo: 6.0, fecha_s: 0.4, fechada_s: 1.3, abre_s: 1.1, comprimento: 9 },
    turbinas: [['C', '#c6+35', 1, 0.0]], turbina: { periodo: 5.0, ligado_s: 1.8, forca: 23, comprimento: 14 },
    impulsos: [['B', -62, 12], ['C', -100]],
    cps: [['A', '#a1+45'], ['A', '#a3+60'], ['A', '#a5+15'], ['B', '#b3+22'], ['B', '#b7+25'], ['C', 180], ['C', '#c2+80'], ['C', '#c5+28'], ['C', '#c6+75']] },
  { // E3 Garganta de Cristal (difícil): tudo, com ritmo mais rápido
    martelos: [['A', '#a0+60', 0.0], ['B', '#b4+6', 1.3], ['C', '#c5+135', 0.4]], martelo: { periodo: 3.7, amplitude: 64, comprimento: 9.5 },
    yetis: [['A', 195], ['B', 496], ['C', 400]], yeti: { segura_s: 5.0, descanso_s: 3.0 },
    focas: [['C', 250, 0], ['C', 110, 1.0]], foca: { periodo: 5.0, cuspe_s: 1.3, congela_s: 4.0 },
    pingentes: [['A', '#a2+116', 0.0], ['C', '#c5+55', 2.0]], pingente: { periodo: 4.5, mover_s: 0.25, fora_s: 1.6, comprimento: 12, altura: 9.5 },
    prensas: [['A', '#a4+26', 0.0]], prensa: { periodo: 5.4, fecha_s: 0.35, fechada_s: 1.4, abre_s: 1.0, comprimento: 9 },
    turbinas: [['A', '#a5+55', 1, 0.0], ['C', '#c6+68', -1, 2.2]], turbina: { periodo: 5.0, ligado_s: 1.8, forca: 25, comprimento: 14 },
    placas: [['A', '#a7+30', '#a7+70']], placa: { tempo_s: 0.8, volta_s: 5.0, comprimento: 4.0, aderencia: 0.5 },
    bolas: [['A', '#a7+118', '#a7+258', 0.0]], bola: { periodo: 8.0, velocidade: 14, raio: 2.0, padrao: 'sorteio' },
    impulsos: [['B', -62, 12], ['C', -100]],
    cps: [['A', '#a2+150'], ['A', '#a4+60'], ['A', '#a5+18'], ['A', '#a7+6'], ['A', '#a9+20'], ['B', '#b1+28'], ['B', '#b5+20'], ['C', 180], ['C', '#c3+25'], ['C', '#c5+13'], ['C', '#c6+23']] },
  { // E4 Pico da Tempestade (muito difícil): tudo junto e mais rápido
    pingentes: [['A', '#a4+4', 0.0], ['C', '#c4+70', 1.5]], pingente: { periodo: 4.0, mover_s: 0.22, fora_s: 1.5, comprimento: 12, altura: 9.5 },
    bolas: [['A', '#a6+120', '#a6+540', 0.0]], bola: { periodo: 8.0, velocidade: 15, raio: 2.0, padrao: 'alterna' },
    martelos: [['B', '#b5+20', 0.0], ['C', '#c7+230', 0.9], ['C', '#c7+380', 0.3]], martelo: { periodo: 3.3, amplitude: 66, comprimento: 9.5 },
    yetis: [['B', 440], ['B', 798], ['C', 110], ['C', 380]], yeti: { segura_s: 5.0, descanso_s: 3.0 },
    focas: [['A', 330, 0], ['A', 861, 1], ['C', 250, 2]], foca: { periodo: 5.0, cuspe_s: 1.3, congela_s: 4.0 },
    turbinas: [['C', '#c3+63', 1, 0.0]], turbina: { periodo: 4.6, ligado_s: 1.7, forca: 22, comprimento: 14 },
    placas: [['C', '#c7+130', '#c7+170']], placa: { tempo_s: 0.7, volta_s: 5.5, comprimento: 4.0, aderencia: 0.5 },
    prensas: [['C', '#c9+80', 1.7]], prensa: { periodo: 5.6, fecha_s: 0.3, fechada_s: 1.2, abre_s: 0.9, comprimento: 9 },
    impulsos: [['B', -62, 12], ['C', -58]],
    cps: [['A', '#a2+20'], ['A', '#a4+38'], ['A', '#a5+21'], ['A', '#a6+285'], ['A', '#a7+7'], ['B', '#b3+30'], ['B', '#b6+15'], ['C', 180], ['C', '#c2+6'], ['C', '#c4+16'], ['C', '#c7+10'], ['C', '#c7+290'], ['C', '#c8+16']] },
];
// Posições por etiqueta ('#nome+metros' = metros depois do começo do segmento etiquetado no traçado)
ps.forEach((p, k) => {
  const res = (T, v) => {
    if (typeof v !== 'string') return v;
    const m = v.match(/^(#\w+)([+-]\d+)?$/);
    if (!m || p[T].tags[m[1]] === undefined) { console.log(`!! E${k + 1} etiqueta desconhecida ${T} ${v}`); process.exit(1); }
    return Math.round(p[T].tags[m[1]] + Number(m[2] || 0));
  };
  const a = armas[k];
  for (const tipo of ['martelos', 'pingentes', 'prensas', 'turbinas', 'focas']) for (const it of a[tipo] || []) it[1] = res(it[0], it[1]);
  for (const tipo of ['bolas', 'placas']) for (const it of a[tipo] || []) { it[1] = res(it[0], it[1]); it[2] = res(it[0], it[2]); }
  for (const c of a.cps) c[1] = res(c[0], c[1]);
});
const TIPOS = ['martelos', 'pingentes', 'prensas', 'turbinas', 'placas', 'bolas', 'focas', 'yetis'];
// Conferência: armadilha/checkpoint em cima de vão, gelo, estreito ou outra armadilha
ps.forEach((p, k) => {
  const a = armas[k];
  const zonas = [];   // [trecho, m0, m1, nome]
  for (const t of [p.A, p.B, p.C]) {
    for (const s of t.segs) if (s[2].startsWith('SALTO')) zonas.push([t.nome, s[0] - 100, s[1], 'salto']);
    for (const g of t.gelo) zonas.push([t.nome, g[0], g[1], 'gelo']);
    for (const e of t.estreitos) zonas.push([t.nome, e[0] - 14, e[1] + 14, 'estreito']);
  }
  const itens = [];
  for (const tipo of TIPOS) for (const it of a[tipo] || []) {
    const comp = tipo === 'bolas' || tipo === 'placas' ? it[2] - it[1] : (tipo === 'martelos' ? 2 : (tipo === 'prensas' ? 9 : 14));
    itens.push([it[0], it[1], it[1] + comp, tipo]);
  }
  for (const it of itens) for (const z of zonas) {
    if (it[0] === z[0] && it[2] > z[1] && it[1] < z[2] && !(z[3] === 'estreito' && it[3] === 'turbinas') && !(it[3] === 'bolas' && z[3] !== 'salto'))
      console.log(`!! E${k + 1} ${it[3]} ${it[0]} ${it[1]}-${it[2]} em cima de ${z[3]} ${z[1]}-${z[2]}`);
  }
  for (let i = 0; i < itens.length; i++) for (let j = i + 1; j < itens.length; j++)
    if (itens[i][0] === itens[j][0] && itens[i][2] + 25 > itens[j][1] && itens[i][1] < itens[j][2] + 25) console.log(`!! E${k + 1} armadilhas coladas`, itens[i], itens[j]);
  for (const c of a.cps) {
    for (const it of itens) if (c[0] === it[0] && c[1] > it[1] - 45 && c[1] < it[2] + 20 && it[3] !== 'bolas') console.log(`!! E${k + 1} checkpoint ${c} perto de ${it[3]} ${it[1]}`);
    for (const z of zonas) if (c[0] === z[0] && z[3] !== 'gelo' && c[1] > (z[3] === 'salto' ? z[1] + 40 : z[1]) && c[1] < z[2] + 8) console.log(`!! E${k + 1} checkpoint ${c} em ${z[3]} ${z[1]}-${z[2]}`);
    const T = p[c[0]]; if (c[1] > T.m - 40 || c[1] < 15) console.log(`!! E${k + 1} checkpoint ${c} na ponta do trecho (${T.m.toFixed(0)})`);
  }
});

// ------------------------------------------------------------------ percursos
const vagas = [[4, -39, 0], [4, -28, 0], [4, -17, 0], [4, -6, 0], [4, 6, 0], [4, 17, 0], [4, 28, 0], [4, 39, 0],
  [16, -41, 90], [30, -41, 90], [44, -41, 90], [58, -41, 90], [16, 41, -90], [30, 41, -90], [44, 41, -90], [58, 41, -90]];
const buracos = [
  (s) => [[22, -22 * s, 6], [30, 24 * s, 6], [52, 0, 7], [70, -28 * s, 6], [74, 20 * s, 6], [88, -6 * s, 5]],
  (s) => [[18, -20 * s, 5.5], [24, 20 * s, 6], [42, -4 * s, 7], [46, 28 * s, 5], [60, -26 * s, 5.5], [64, 10 * s, 6], [78, -12 * s, 5], [80, 24 * s, 5]],
  (s) => [[16, -22 * s, 5.5], [22, 18 * s, 6], [38, -6 * s, 7], [42, 26 * s, 5], [54, -26 * s, 5.5], [58, 8 * s, 6], [70, -14 * s, 5], [74, 24 * s, 5], [82, -30 * s, 4.5]],
  (s) => [[18, -24 * s, 6], [24, 22 * s, 6.5], [40, -6 * s, 7], [46, 30 * s, 5.5], [58, -30 * s, 6], [62, 10 * s, 6.5], [74, -16 * s, 5.5], [78, 26 * s, 5], [88, -2 * s, 5], [90, -32 * s, 4.5], [92, 34 * s, 4.5]],
];
const imp_plat = (s, comp) => [[comp * 0.34, 34 * s, -35 * s, false], [comp * 0.58, -40 * s, 0, false], [comp * 0.76, 2 * s, 0, false]];
const placas = ['FORTALEZA AZUL', 'FORTALEZA DO YETI', 'FORTALEZA DE CRISTAL', 'FORTALEZA DA TEMPESTADE'];
const zonas_pouso = [{ largura: 16, comprimento: 240, transicao: 60 }, { largura: 15, comprimento: 230, transicao: 60 }, { largura: 15, comprimento: 220, transicao: 50 }, { largura: 14, comprimento: 210, transicao: 50 }];
const ader_plat = [1.0, 0.75, 0.6, 0.5];
const meio_fio = [110, 100, 150, 80];
const percursos = {};
ps.forEach((p, k) => {
  const L = p.def.largada, P = p.def.plat, a = armas[k];
  const arm = {};
  for (const c of ['martelos', 'martelo', 'pingentes', 'pingente', 'prensas', 'prensa', 'bolas', 'bola', 'turbinas', 'turbina', 'placas', 'placa', 'focas', 'foca', 'yetis', 'yeti']) if (a[c]) arm[c] = a[c];
  const vaos = [], gelo = [], estreitos = [];
  for (const t of [p.A, p.B, p.C]) {
    for (const v of t.vaos) vaos.push([t.nome, r1(v[0]), r1(v[1]), r1(v[2]), v[3]]);
    for (const g of t.gelo) gelo.push([t.nome, g[0], g[1], g[2]]);
    // Pedido do dono: o pouso de TODO salto é de gelo (dificulta segurar o carro) — os 20 m do pouso e mais 14 m
    for (const sg of t.segs) if (sg[2].startsWith('SALTO')) gelo.push([t.nome, Math.round(sg[1] - 21), Math.round(sg[1] + 14), 0.3]);
    for (const e of t.estreitos) estreitos.push([t.nome, e[0], e[1], e[2]]);
  }
  // ... e o pouso do salto grande (fim do B → começo do C)
  gelo.push(["C", 0, 70, 0.35]);
  const plat = { origem: P.o, frente: dirv(P.h), comprimento: P.comp, largura: P.larg, saida_largura: 10, muro_altura: 2.6, grade_altura: 8.5, placa: placas[k],
    entradas: [[P.s, P.xe, 12]], buracos: buracos[k](P.s).map(b => [Math.round(b[0] * P.comp / 100), Math.round(b[1] * P.larg / 100), b[2]]),
    impulsos: imp_plat(P.s, P.comp).map(i => [Math.round(i[0]), Math.round(i[1] * P.larg / 100), i[2], i[3]]) };
  if (ader_plat[k] < 1) plat.aderencia = ader_plat[k];
  percursos[String(k + 1)] = {
    _: p.def.nome,
    largada: { origem: L.o, frente: dirv(L.h), comprimento: L.comp, largura: L.larg, saida_largura: 10, muro_altura: 2.6, grade_altura: 7.4, placa: 'FROZEN PEAK', ...(k === 1 ? { placa_imagem: 'res://assets/frozen/extruturas/placa_passo_do_yeti.png' } : {}), impulsos: [[52, 0, 0, true]], vagas },
    plataforma: plat,
    trechos: { A: pts(p.A), B: pts(p.B), C: pts(p.C) },
    vaos, gelo, estreitos,
    impulsos: a.impulsos,
    zona_pouso: zonas_pouso[k],
    largura_inicio: { largura: 20, comprimento: 170, transicao: 60 },
    meio_fio_inicio: meio_fio[k],
    checkpoints: { pontos: a.cps, fantasma_s: 3.0, raio: 6.5, altura: 6.0 },
    armadilhas: { ...arm, yetis_plataforma: { quantidade: [3, 4, 5, 6][k], intervalo_s: [3.6, 3.2, 2.8, 2.4][k], alcance: 70, sem_pq_s: 5.0 } },
  };
  // Pedido do dono (2026-10-03): plataforma sem buracos de fogo, piso todo de gelo
  percursos[String(k + 1)].plataforma = { ...plat, buracos: [], aderencia: 0.3 };
});

// ------------------------------------------------------------------ alvos e obstáculos do voo
const alvos = ps.map(p => p.alvo.map(Math.round));
const rampas = ps.map(p => [p.C.fim.x, p.C.fim.y, p.C.fim.z]);
// Anel de agulhas de gelo em volta do alvo: raio R, agulhas de raio r a cada `passo` m, com portões
// (ângulo em graus medido de +x para +z, largura livre em m).
const pontes_tmp = [];
function anel(c, R, r, h, passo, portoes) {
  const n = Math.round(2 * Math.PI * R / passo);
  const lista = [];
  // Ponte no alto de cada portão: liga as duas agulhas que o ladeiam [x1, z1, x2, z2, y, raio]
  for (const g of portoes) {
    const meio = (g[1] * 0.5 + r) / R / D;
    const p1 = [Math.round(c[0] + Math.cos((g[0] - meio) * D) * R), Math.round(c[1] + Math.sin((g[0] - meio) * D) * R)];
    const p2 = [Math.round(c[0] + Math.cos((g[0] + meio) * D) * R), Math.round(c[1] + Math.sin((g[0] + meio) * D) * R)];
    lista.push([p1[0], p1[1], r, h], [p2[0], p2[1], r, h]);
    pontes_tmp.push([p1[0], p1[1], p2[0], p2[1], h + 12, r]);
  }
  for (let k = 0; k < n; k++) {
    const a = 2 * Math.PI * k / n;
    let livre = false;
    for (const g of portoes) {
      let d = Math.abs(((a / D - g[0] + 540) % 360) - 180) * D * R;   // arco até o centro do portão
      if (d < g[1] * 0.5 + r * 2.6) livre = true;
    }
    if (!livre) lista.push([Math.round(c[0] + Math.cos(a) * R), Math.round(c[1] + Math.sin(a) * R), r, h]);
  }
  return lista;
}
const ponto = (c, R, ang) => [Math.round(c[0] + Math.cos(ang * D) * R), Math.round(c[1] + Math.sin(ang * D) * R)];
// Muralha quadrada (cidadela) em volta do alvo, com a abertura na face que dá para a rampa
const etapas_gelo = {};
const rotas = {};
const rotas_alt = {};
{ // E1: anel de agulhas com um portão largo virado para a rampa (ao sul: +z = 90°)
  const c = alvos[0];
  etapas_gelo['1'] = { _: 'Anel de agulhas de gelo em volta do alvo, com um portão de 70 m virado para a rampa.', pilares: anel(c, 260, 20, 250, 47, [[90, 70]]), pontes: pontes_tmp.splice(0) };
  rotas['1'] = [[c[0], c[1] + 400], ponto(c, 260, 90), [c[0], c[1] + 120]];
}
{ // E2: cidadela de gelo; a muralha virada para a rampa (sul) tem três furos REDONDOS (pedido do dono):
  // no meio um bem pequeno (8 m, o do paredão do Climb to Death), que dá no corredor reto até o alvo; à
  // esquerda e à direita, dois grandes (52 m), fáceis, que dão nos corredores de fora — duas divisórias
  // obrigam quem entra por eles a ir até o fundo e voltar para o meio (caminho mais comprido).
  const c = alvos[1];
  const mx = 240, zf = c[1] + 390, zt = c[1] - 200, topo = 290, esp = 12, lado_f = 150, div = 70, y_f = 197;
  etapas_gelo['2'] = { _: 'Cidadela de gelo em volta do alvo. Na muralha virada para a rampa: furo redondo de 8 m no meio (corredor reto e curto até o alvo) e dois furos redondos de 52 m à esquerda e à direita (corredores de fora: o caminho é mais comprido, contornando as divisórias).',
    muralhas: [
      { a: [c[0] - mx, zf], b: [c[0] + mx, zf], altura: topo, espessura: esp, aberturas: [{ centro: mx - lado_f, y: y_f, raio: 26 }, { centro: mx, y: y_f, raio: 4 }, { centro: mx + lado_f, y: y_f, raio: 26 }] },
      { a: [c[0] - mx, zt], b: [c[0] + mx, zt], altura: topo, espessura: esp },
      { a: [c[0] - mx, zt], b: [c[0] - mx, zf], altura: topo, espessura: esp },
      { a: [c[0] + mx, zt], b: [c[0] + mx, zf], altura: topo, espessura: esp },
      { a: [c[0] - div, c[1] + 120], b: [c[0] - div, zf], altura: topo, espessura: 8, torres: false },
      { a: [c[0] + div, c[1] + 120], b: [c[0] + div, zf], altura: topo, espessura: 8, torres: false },
    ] };
  // Bots: pelos furos grandes (cada um sorteia o lado); o do meio fica para quem tem mão
  const lado = sx => [[c[0] + sx * lado_f, zf + 110, y_f + 8], [c[0] + sx * lado_f, zf + 12, y_f], [c[0] + sx * lado_f, zf - 40, y_f - 5], [c[0] + sx * lado_f, c[1] + 250], [c[0] + sx * 60, c[1] + 70]];
  rotas['2'] = lado(-1);
  rotas_alt['2'] = [lado(1)];
}
{ // E3: dois anéis de agulhas, portões desencontrados (voo em S); a rampa fica a leste (+x = 0°)
  const c = alvos[2];
  etapas_gelo['3'] = { _: 'Floresta de agulhas em dois anéis em volta do alvo: portões de 46 m desencontrados (voo em S). Entre as outras agulhas sobram frestas de ~25 m.',
    pilares: [...anel(c, 330, 15, 262, 55, [[8, 46]]), ...anel(c, 190, 13, 240, 50, [[-22, 46]])], pontes: pontes_tmp.splice(0) };
  rotas['3'] = [ponto(c, 400, 6), ponto(c, 330, 8), ponto(c, 260, -8), ponto(c, 190, -22), ponto(c, 120, -14)];
}
{ // E4: fenda (corredor em curva) que dá na cidadela da tempestade; a rampa fica a oeste
  const c = alvos[3];
  const topo = 290, esp = 12, meia = 28;
  const linha = [[c[0] - 600, c[1]], [c[0] - 500, c[1]], [c[0] - 390, c[1] + 46], [c[0] - 279, c[1] + 46]];
  const muralhas = [];
  // Paredes do corredor: cada trecho da linha, deslocado para os dois lados
  for (const s of [-1, 1]) {
    const desl = linha.map((q, i) => {
      const a = linha[Math.max(i - 1, 0)], b = linha[Math.min(i + 1, linha.length - 1)];
      const dx = b[0] - a[0], dz = b[1] - a[1], l = Math.hypot(dx, dz);
      return [Math.round(q[0] - dz / l * meia * s), Math.round(q[1] + dx / l * meia * s)];
    });
    // Boca em funil (104 m de largura afinando até os 56 m do corredor): dá para acertar a entrada logo depois da rampa
    muralhas.push({ a: [c[0] - 690, c[1] + 54 * s], b: desl[0], altura: topo, espessura: esp, torres: false });
    for (let i = 1; i < desl.length; i++) muralhas.push({ a: desl[i - 1], b: desl[i], altura: topo, espessura: esp, torres: false });
  }
  const xo = c[0] - 279, xl = c[0] + 282, zn = c[1] - 280, zs = c[1] + 280, zb = c[1] + 46;
  muralhas.push({ a: [xo, zn], b: [xo, zs], altura: topo, espessura: esp, aberturas: [{ centro: zb - zn, largura: meia * 2 - esp, y0: 0, y1: 999 }] });
  muralhas.push({ a: [xl, zn], b: [xl, zs], altura: topo, espessura: esp });
  muralhas.push({ a: [xo, zn], b: [xl, zn], altura: topo, espessura: esp });
  muralhas.push({ a: [xo, zs], b: [xl, zs], altura: topo, espessura: esp });
  // Pontes com o logo no alto da boca e do fim do corredor (marcam a passagem para quem vem voando)
  const pontes = [[linha[0][0], linha[0][1] - meia, linha[0][0], linha[0][1] + meia, topo + 10, esp * 0.5], [linha[3][0], linha[3][1] - meia, linha[3][0], linha[3][1] + meia, topo + 10, esp * 0.5]];
  etapas_gelo['4'] = { _: 'Fenda da Tempestade: corredor de 56 m entre dois paredões de gelo, com uma curva, que desemboca na cidadela em volta do alvo.', muralhas, pontes };
  // Traçado de corrida pela fenda: abre por fora antes da curva, tangencia o canto de dentro e sai alinhado com a porta da cidadela
  rotas['4'] = [[c[0] - 690, c[1] - 6], [c[0] - 600, c[1] - 8], [c[0] - 515, c[1] + 8], [c[0] - 400, c[1] + 40], [c[0] - 300, c[1] + 46], [c[0] - 200, c[1] + 36]];
}
for (const k of Object.keys(rotas)) rotas[k] = Object.assign({ capsulas: [], rota: rotas[k] }, rotas_alt[k] ? { rotas_alt: rotas_alt[k] } : {});

// Torres dos cantos da fortaleza da própria etapa x estrada (a estrada só entra pelo meio do lado e sai pelo meio da frente)
ps.forEach((p, k) => {
  const P = p.def.plat; const F = [Math.sin(P.h * D), -Math.cos(P.h * D)]; const L = [-F[1], F[0]];
  for (const cx of [-4, P.comp + 4]) for (const s of [-1, 1]) {
    const q = [P.o[0] + F[0] * cx + L[0] * s * (P.larg / 2 + 4), P.o[2] + F[1] * cx + L[1] * s * (P.larg / 2 + 4)];
    for (const tr of [p.A, p.B, p.C]) for (const pt of tr.pts) if (Math.hypot(pt[0] - q[0], pt[2] - q[1]) < 24 && pt[1] < P.o[1] + 40) console.log(`!! E${k + 1} estrada ${tr.nome} a ${Math.hypot(pt[0] - q[0], pt[2] - q[1]).toFixed(0)} m de uma torre da própria fortaleza (${q.map(Math.round)})`);
  }
});
// Fortalezas (plataformas) x estradas das outras etapas
ps.forEach((p, k) => ps.forEach((q, j) => {
  if (j === k) return;
  const P = q.def.plat; const F = [Math.sin(P.h * D), -Math.cos(P.h * D)];
  const cx = P.o[0] + F[0] * P.comp / 2, cz = P.o[2] + F[1] * P.comp / 2;
  for (const t of [p.A, p.B, p.C]) for (const pt of t.pts) if (Math.hypot(pt[0] - cx, pt[2] - cz) < 110) console.log(`!! estrada E${k + 1} ${t.nome} a ${Math.hypot(pt[0] - cx, pt[2] - cz).toFixed(0)} m da fortaleza E${j + 1}`);
}));

// Outdoors gigantes: candidatos [x, z, giro em graus, altura do painel, altura das pernas]; fica só
// o que estiver longe de toda estrada (70 m), dos voos (160 m) e dos alvos
const cand = [[-1620, 640, 60, 12, 26], [680, 520, 10, 12, 26], [-430, 500, 20, 12, 24], [-1850, -200, 100, 12, 26], [-20, -380, 0, 13, 30],
  [-1150, 150, 140, 12, 26], [300, 300, 200, 12, 26], [-1900, -1300, 60, 13, 30], [900, -200, 250, 12, 26], [-300, -1700, 0, 14, 34], [-1500, 950, 20, 12, 24], [1100, 500, 270, 12, 24]];
const seg = (p, a, b) => { const dx = b[0] - a[0], dz = b[1] - a[1]; const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / (dx * dx + dz * dz))); return Math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dz * t); };
const outdoors = cand.filter(o => {
  for (const p of ps) {
    for (const t of [p.A, p.B, p.C]) for (const pt of t.pts) if (Math.hypot(pt[0] - o[0], pt[2] - o[1]) < 70) return false;
    for (const R of [p.def.largada, p.def.plat]) if (Math.hypot(R.o[0] - o[0], R.o[2] - o[1]) < 150) return false;
  }
  for (let k = 0; k < 4; k++) if (seg(o, [rampas[k][0], rampas[k][2]], alvos[k]) < 160 || Math.hypot(alvos[k][0] - o[0], alvos[k][1] - o[1]) < 420) return false;
  return true;
});
console.log('outdoors', outdoors.length, 'de', cand.length);

// Esporões de montanha entrando no vale (quebram o contorno reto): só ficam os que não chegam perto
// de nenhuma estrada, cercado, alvo ou voo de nenhuma etapa
const cand_esp = [
  { a: [-1750, -2050], b: [-1720, -1640], raio: [190, 120], altura: 230 }, { a: [-360, -2050], b: [-380, -1640], raio: [170, 110], altura: 210 },
  { a: [560, -2050], b: [590, -1660], raio: [170, 105], altura: 220 }, { a: [-2400, -1350], b: [-1960, -1330], raio: [180, 115], altura: 220 },
  { a: [-2400, 80], b: [-1980, 110], raio: [180, 120], altura: 200 }, { a: [-2400, 620], b: [-2030, 600], raio: [150, 100], altura: 180 },
  { a: [-1280, 1250], b: [-1300, 860], raio: [170, 110], altura: 200 }, { a: [470, 1250], b: [450, 930], raio: [160, 105], altura: 190 },
  { a: [-150, 1250], b: [-130, 960], raio: [150, 100], altura: 170 }, { a: [1450, -250], b: [1230, -230], raio: [150, 90], altura: 200 },
  { a: [-1000, -2050], b: [-1020, -1720], raio: [160, 110], altura: 200 }, { a: [-2400, -820], b: [-2050, -800], raio: [150, 100], altura: 190 },
];
const esporoes = cand_esp.filter(e => {
  const d = p => seg(p, e.a, e.b);
  const folga = Math.max(e.raio[0], e.raio[1]) + 70;
  for (const p of ps) {
    for (const tr of [p.A, p.B, p.C]) for (const pt of tr.pts) if (d([pt[0], pt[2]]) < folga) return false;
    for (const R of [p.def.largada, p.def.plat]) if (d([R.o[0], R.o[2]]) < folga + 90) return false;
  }
  for (let k = 0; k < 4; k++) {
    if (d(alvos[k]) < folga + 420) return false;
    for (let q = 0; q <= 10; q++) if (d([rampas[k][0] + (alvos[k][0] - rampas[k][0]) * q / 10, rampas[k][2] + (alvos[k][1] - rampas[k][2]) * q / 10]) < folga + 150) return false;
  }
  if (d([1160, 930]) < folga + 40 || d([1160, -620]) < folga + 40 || d([1160, 150]) < folga + 40) return false;
  return true;
});
console.log('esporões', esporoes.length, 'de', cand_esp.length);
// Balões: os cinco altos de sempre e mais uns vinte baixos, perto das estradas (pedido do dono: "mais balões e
// mais próximos") — 110 m ou mais de qualquer estrada, fora dos voos, dos alvos e das fortalezas. [x, y, z, escala]
const baloes = [[-900, 420, -200], [300, 470, 300], [-300, 520, -1500], [800, 430, -500], [-1700, 450, 300]];
{
  let rnd = 4242; const rand = () => { rnd = (rnd * 16807) % 2147483647; return rnd / 2147483647; };
  const todos = [];
  for (const q of ps) for (const t of [q.A, q.B, q.C]) for (const pt of t.pts) todos.push(pt);
  ps.forEach((q, k) => {
    for (const t of [q.A, q.B, q.C]) for (let i = 4; i < t.pts.length - 2; i += 9) {
      const a = t.pts[i - 1], b = t.pts[i + 1], pt = t.pts[i];
      const dx = b[0] - a[0], dz = b[2] - a[2], l = Math.hypot(dx, dz) || 1;
      const sd = rand() < 0.5 ? -1 : 1, off = 125 + rand() * 80;
      const x = pt[0] - dz / l * off * sd, z = pt[2] + dx / l * off * sd, y = pt[1] + 45 + rand() * 60;
      let ok = true;
      for (const o of todos) if (Math.hypot(o[0] - x, o[2] - z) < 110 && Math.abs(o[1] - y) < 130) { ok = false; break; }
      for (let j = 0; j < 4 && ok; j++) {
        if (seg([x, z], [rampas[j][0], rampas[j][2]], alvos[j]) < 190 || Math.hypot(alvos[j][0] - x, alvos[j][1] - z) < 420) ok = false;
        for (const R of [ps[j].def.largada, ps[j].def.plat]) if (Math.hypot(R.o[0] - x, R.o[2] - z) < 150) ok = false;
      }
      if (x < -2150 || x > 1200 || z < -1800 || z > 1000) ok = false;
      if (baloes.some(o => Math.hypot(o[0] - x, o[2] - z) < 230)) ok = false;
      if (ok) baloes.push([Math.round(x), Math.round(y), Math.round(z), r1(1.6 + rand() * 0.9)]);
    }
  });
  console.log('balões', baloes.length);
}
const mapa = {
  id: 'frozen_peak',
  imagem: 'res://assets/ui/mapa_frozen_peak.jpg',
  nome: 'Frozen Peak',
  tipo: 'subida',
  ambiente: 'gelo',
  descricao: 'Montanha de gelo: saltos sobre vãos, gelo que escorrega, passagens estreitas e alvos que não param.',
  _ambiente: 'Mesmas regras do Climb to Death (corrida com checkpoints, ressurge no último checkpoint, só os primeiros 30% pontuam, ejetor a corrida toda, freio). Novidades: vãos na estrada (saltos), trechos estreitos, gelo vivo (aderência menor), armadilhas de gelo (scripts/mundo/armadilhas.gd, seção Frozen Peak), alvos de formas diferentes sempre em movimento (Alvo._montar_livre) e obstáculos de gelo no voo. Cenário: scripts/mundo/gelo.gd e enfeites_gelo.gd.',
  sobrepor: {
    bots: { agressividade: [0.65, 1.0], meta: { nome: 'Subir, derrubar e pontuar', _meta: 'Pedido do dono (2026-10-03): o comportamento dos bots do Extinction Day vale em todos os mapas — atacam quem está no caminho, se defendem (pulo com o ejetor ou freada), revidam quem bate e pousam devagar. O nível dos bots (Configurações) multiplica tudo isso.', ataques: { chao: 1.6, ar: 1.0, alvo: 1.0 }, defesa: 1.0, revide: 1.6, pouso_lento: true, espera: 0.4, velocidade: 1.0 } },
    mapa: {
      _distancia: 'Da rampa final até o alvo.',
      distancia_saida_alvo: 800,
      alvo_altura: 60,
      semente_terreno: 9041,
      _nivel_agua: 'Nível do gelo do lago e do rio (cair neles elimina).',
      nivel_agua: 4,
      subida: {
        _subida: 'Frozen Peak. Mundo: x = leste, z = sul. Cada etapa tem um percurso (percursos.N: largada, plataforma, trechos A/B/C, vaos, gelo, estreitos, impulsos, checkpoints e armadilhas), gerado pelo traçado (tartaruga de retas e curvas) com rampa de no máx. ~8%. As chaves de percursos.N sobrepõem as de subida.',
        _vaos: 'percursos.N.vaos: [trecho, x, y, z do lábio da rampinha, comprimento do vão em m] — dali em diante não há piso. estreitos: [trecho, m inicial, m final, largura]. gelo: [trecho, m inicial, m final, aderência (1 = normal)]. plataforma.aderencia: piso de gelo no cercado dos buracos.',
        tema: 'gelo',
        largura_estrada: 10,
        meio_fio_inicio: 100,
        impulso_velocidade: 16,
        _rota: 'Os bots seguem montanhas.etapas.N.rota ([x, z] ou [x, z, altura]) no sentido do lançamento da rampa final.',
        rota_pela_rampa: true,
        _vale: 'Chão do vale glacial dentro do retângulo [x_min, z_min, x_max, z_max]; fora, paredões de rocha e gelo e depois os maciços nevados.',
        vale: [-2250, -1900, 1300, 1100],
        barreiras: { fileiras: [] },
        vegetacao: [0, 0, 0],
        montanhas: { face: 50, fixas: esporoes, etapas: rotas },
        checkpoints: { fantasma_s: 3.0, raio: 6.5, altura: 6.0 },
        percursos,
        gelo: {
          penhasco: 270,
          _lagos: 'Lagos congelados [x, z, raio] e o rio que sai do maior.',
          lagos: [[-700, 420, 230], [600, -900, 150]],
          rio: { pontos: [[-700, 640], [-760, 800], [-820, 1100], [-900, 2000], [-950, 3600]], meia_largura: 22 },
          _vilas: 'Vilas de chalés: [x, z, quantidade, raio].',
          vilas: [[-1100, 620, 14, 110], [150, 780, 10, 90], [1050, 250, 9, 80]],
          teleferico: { a: [1160, 40, 930], b: [1160, 190, -620], cabines: 8 },
          _outdoors: 'Outdoors gigantes do logo no chão do vale: [x, z, giro em graus, altura do painel, altura das pernas].',
          outdoors,
          baloes,
          _dirigiveis: 'Dirigíveis dando voltas sobre o vale: [x do centro, altura, z do centro, raio da volta, velocidade em m/s (negativa = sentido contrário), comprimento].',
          dirigiveis: [[-475, 385, -400, 900, 9, 110], [-1250, 335, -350, 520, -8, 85], [420, 350, -150, 470, 8, 90], [-600, 345, 420, 430, -7, 80]],
          seracs: 150,
          rochas: 800,
          pinheiros: 5200,
          _araucarias: 'Araucárias gigantes cobertas de gelo (50 a 95 m), em bosques (pedido do dono).',
          araucarias: 1500,
          _etapas: 'Obstáculos do voo por etapa: pilares = agulhas de gelo [x, z, raio, altura]; pontes = treliça com o logo no alto de um portão [x1, z1, x2, z2, y, raio das agulhas]; muralhas = {a, b (xz), altura, espessura, aberturas: [{centro (m ao longo desde a), largura, y0, y1}]}.',
          etapas: etapas_gelo,
        },
      },
    },
    alvo: { _zonas: 'Alvo de uma zona só: tocar em qualquer parte vale 10 pontos (como no Climb to Death).', zonas: [[10, 15.0]] },
    regras: { corrida: { fracao_pontuam: 0.3, pontos: [10, 5, 3] }, ejetor_sempre: true, freios_instalados: true },
    fisica: { ejetor_recarga: 5.0 },
    _partida: 'Percursos de 3,8 a 4,2 km com saltos, gelo e armadilhas: 8 min por etapa (etapas[].tempo_mult: a 3 tem +10% e a 4, +20%).',
    partida: { tempo_segundos: 480 },
    _etapas: 'forma: disco | cruz | anel | triangulo; gelo: true = tampo de gelo fixo numa mesa de gelo, com aderencia baixa. trajeto: linha (vaivém sobre cabos: comprimento, periodo, direcao em graus, 0 = norte, 90 = oeste), circulo (carrossel: raio, periodo), vertical (elevador: amplitude, periodo), oito (drone: comprimento, largura, periodo, direcao).',
    etapas: [
      { nome: 'Geleira Azul', forma: 'disco', diametro: 28, deslocamento: alvos[0], altura: 60, trajeto: { tipo: 'linha', comprimento: 70, periodo: 40, direcao: 90 },
        _etapa: 'Fácil: saltos curtos, um trecho de gelo, uma chicane estreita, bolas de neve e martelos lentos. Alvo redondo num carrinho sobre cabos, atrás de um anel de agulhas com portão largo.' },
      { nome: 'Passo do Yeti', forma: 'disco', gelo: true, aderencia: 0.14, diametro: 140, deslocamento: alvos[1], altura: 55,
        vento: { direcao: 90, forca: 1.5, rajada: 2.0, periodo: 7.0 },
        _etapa: 'Médio: espiral com bolas de neve, salto duplo, gelo fino que quebra, prensa e turbina. Alvo (pedido do dono, no lugar da cruz que girava e jogava os carros para fora): disco FIXO de gelo com 140 m (5x os normais), que escorrega — o pneu quase não segura e o zigue-zague freia pouco. Fica dentro de uma cidadela de gelo com três furos redondos na muralha.' },
      { nome: 'Garganta de Cristal', tempo_mult: 1.1, forma: 'anel', diametro: 36, furo: 14, deslocamento: alvos[2], altura: 52, trajeto: { tipo: 'vertical', amplitude: 36, periodo: 36 },
        vento: { direcao: 0, forca: 3.0, rajada: 3.0, periodo: 5.0 },
        _etapa: 'Difícil: ziguezague de montanha com gelo nas curvas fechadas, todas as armadilhas e vento de lado. Alvo em anel subindo e descendo numa torre, atrás de dois anéis de agulhas.' },
      { nome: 'Pico da Tempestade', tempo_mult: 1.2, forma: 'triangulo', diametro: 26, lado: 26, deslocamento: alvos[3], altura: 60, trajeto: { tipo: 'oito', comprimento: 70, largura: 34, periodo: 44, direcao: 0 },
        vento: { direcao: 180, forca: 3.5, rajada: 3.5, periodo: 4.5 },
        _etapa: 'Muito difícil: saltos em sequência, o Fio da Navalha (estreito com turbina), duas espirais, nevasca. Alvo triangular num drone fazendo um oito, no fim de uma fenda entre paredões de gelo.' },
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
  const ini = jogo.indexOf(',\n\t\t{\n\t\t\t"id": "frozen_peak"');
  if (ini >= 0) jogo = jogo.slice(0, ini) + jogo.slice(jogo.indexOf(marca));
  const pos = jogo.indexOf(marca);
  if (pos < 0) { console.log('marca não achada'); process.exit(1); }
  jogo = jogo.slice(0, pos) + ',\n' + txt + jogo.slice(pos);
  JSON.parse(jogo);
  fs.writeFileSync(caminho, jogo);
  console.log('inserido', txt.length);
}
for (let k = 0; k < 4; k++) console.log(ps[k].def.nome, 'alvo', alvos[k], 'rampa', rampas[k].map(Math.round), 'agulhas', (etapas_gelo[k + 1].pilares || []).length, 'muralhas', (etapas_gelo[k + 1].muralhas || []).length);
