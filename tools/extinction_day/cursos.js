// Percursos das 4 etapas do Extinction Day (traçado com gen.js). node cursos.js → resumo e mapa.png
const { percurso, na_espiral, vulcao, V } = require('./gen.js');
const desenhar = require('./desenho.js');
const KICK = [['R', 18, 2.4], ['R', 14, 2.3]];
const RAMPA = [['R', 22, 4.3], ['R', 18, 5.9]];
const CHICANE = (larg, r, a, dy, lado = 1) => [['EI', larg], ['C', r, a * lado, dy * 0.25], ['C', r, -2 * a * lado, dy * 0.5], ['C', r, a * lado, dy * 0.25], ['EF']];
const ESP = (r0, a, s) => na_espiral(V.x, V.z, r0, a, s);

// E1: entra no flanco sul do vulcão, dá a volta por dentro (oeste, norte) e sai a leste
const e1_in = ESP(690, 118, 1);
const e3_in = ESP(800, 160, 1);
const defs = [
  { nome: 'E1 Boca do Vulcão', dist: 800,
    largada: { o: [-60, 10, 1180], h: 0, comp: 70, larg: 90 },
    A: [['R', 120, 4, '#a0'], ['C', 180, -40, 10, '#a1'], ['R', 130, 10, '#a2'], ['C', 180, 70, 16, '#a3'], ['R', 60, 4, '#a4'], ['C', 180, -30, 7, '#a5'],
      ...CHICANE(6.0, 34, 55, 7), ['R', 80, 6, '#a6'], ['H', -249, -247, 100, 0, 0.5, '#a7']],
    plat: { o: [-199, 100, -300], h: 270, comp: 100, larg: 100, s: -1, xe: 50 },
    B: [['R', 30, 2, '#b0'], ['H', e1_in[0], e1_in[1], 128, e1_in[2], 0.45, '#b1'], ['T0'], ['ESP', V.x, V.z, 430, 92, 12, '#b2'], ['R', 10, 0.6, '#b3'], ...KICK],
    C: [['R', 25, -1.0, '#c0'], ['ESP', V.x, V.z, 430, 46, 14, '#c1'], ['ESP', V.x, V.z, 430, 22, 8, '#c2'], ['ESP', V.x, V.z, 680, 30, 22, '#c3'], ['T1'], ['C', 240, -38, 12, '#c4'], ['R', 120, 8, '#c5'], ...RAMPA] },
  { nome: 'E2 Noite da Aurora', dist: 800,
    largada: { o: [1750, 10, 1620], h: 0, comp: 70, larg: 90 },
    A: [['R', 140, 5, '#a0'], ['C', 200, -35, 10, '#a1'], ['R', 180, 14, '#a2'], ['C', 200, 35, 10, '#a3'], ['R', 120, 9, '#a4'], ...CHICANE(6.0, 32, 60, 7),
      ['R', 150, 11, '#a5'], ['C', 260, 25, 8, '#a6'], ['R', 80, 5, '#a7'], ['H', 1750, 209, 101.3, 0, 0.5, '#a8'], ['R', 100, 6, '#a9'], ...KICK],
    // Plataforma sem chão (poço de lava): a estrada termina numa rampinha 32 m acima do portão da saída, 27 m antes do muro do fundo e apontada para o portão; atravessa-se de paraquedas
    plat: { o: [1750, 80, 50], h: 0, comp: 100, larg: 100, s: -1, xe: 50, sem_piso: true },
    B: [['R', 150, 5, '#b0'], ['C', 150, -90, 12, '#b1'], ['H', 1033, -170, 131, 270, 0.5, '#b2'], ['R', 200, 14, '#b4'], ['R', 60, 3, '#b5'], ...KICK],
    C: [['R', 25, -1.0, '#c0'], ['R', 75, -7], ['R', 40, -2], ['R', 60, 0, '#c1'], ['C', 200, -90, 13, '#c2'], ['R', 420, 22, '#c3'], ...CHICANE(5.6, 30, 65, 7, -1), ['R', 450, 14, '#c4'],
      ['C', 200, -90, 12, '#c5'], ['R', 330, 8, '#c6'], ['C', 200, -90, 11, '#c7'], ['R', 90, 5, '#c8'], ...RAMPA] },
  { nome: 'E3 Fuga da Encosta', dist: 800,
    largada: { o: [-2650, 10, 250], h: 0, comp: 70, larg: 90 },
    A: [['R', 150, 5, '#a0'], ['C', 220, 35, 12, '#a1'], ['R', 200, 15, '#a2'], ...CHICANE(6.0, 32, 60, 7), ['R', 150, 11, '#a3'], ['C', 220, -35, 12, '#a4'],
      ['R', 150, 10, '#a5'], ['H', -1750, -647, 100, 0, 0.5, '#a6']],
    plat: { o: [-1800, 100, -700], h: 90, comp: 100, larg: 100, s: 1, xe: 50 },
    B: [['R', 40, 2, '#b0'], ['H', e3_in[0], e3_in[1], 136, e3_in[2], 0.5, '#b1'], ['ESP', V.x, V.z, 650, 70, 72, '#b2'], ['R', 10, 0.5, '#b3'], ...KICK],
    C: [['R', 25, -1.0, '#c0'], ['R', 60, -6], ['R', 40, -2], ['C', 180, -115, 0, '#c1'], ['R', 520, -42, '#c2'], ['R', 100, -5, '#c3'], ['C', 240, -40, 8, '#c4'], ['R', 120, 9, '#c5'],
      ...CHICANE(5.6, 30, 65, 7), ['R', 60, 4, '#c6'], ['C', 300, -34, 12, '#c7'], ['R', 200, 14, '#c8'], ...RAMPA] },
  { nome: 'E4 Impacto', dist: 800,
    largada: { o: [-2650, 10, 1550], h: 0, comp: 70, larg: 90 },
    A: [['R', 160, 6, '#a0'], ['C', 200, 40, 12, '#a1'], ['R', 180, 14, '#a2'], ['C', 200, -40, 12, '#a3'], ...CHICANE(6.0, 30, 60, 7), ['R', 160, 12, '#a4'], ['C', 200, 30, 8, '#a5'],
      ['R', 100, 6, '#a6'], ['H', -2203, 450, 100, 90, 0.5, '#a7']],
    plat: { o: [-2150, 100, 500], h: 0, comp: 100, larg: 100, s: -1, xe: 50 },
    B: [['R', 100, 4, '#b0'], ['C', 220, 90, 14, '#b1'], ['R', 240, 14, '#b2'], ['C', 260, 40, 12, '#b3'], ['R', 160, 9, '#b4'], ['R', 60, 3, '#b5'], ...KICK],
    C: [['R', 25, -1.0, '#c0'], ['R', 75, -7], ['R', 40, -2], ['R', 60, 0, '#c1'], ['C', 200, 50, 10, '#c2'], ['R', 190, 13.5, '#c3'], ...CHICANE(5.4, 28, 70, 7, -1), ['R', 220, 16, '#c4'],
      ['R', 50, 0, '#l0'], ['LOOP', 18, 35, 14, '#l1'], ['R', 45, 0, '#l2'],   // looping com aceleradores (pedido do dono)
      ['C', 180, 90, 18, '#c5'], ['R', 160, 12, '#c6'], ['R', 60, 4, '#c8'], ...RAMPA] },
];
const ps = defs.map(percurso);
const mundo = {
  vale: [-2800, -2500, 1900, 1700],
  altura: (x, z) => Math.max(6.5, vulcao(x, z)),
};
// Folga da estrada para o vulcão: fora do túnel a estrada precisa passar acima da encosta; dentro,
// a encosta tem de cobrir o túnel (rocha por cima)
function conferir(p, k) {
  for (const t of [p.A, p.B, p.C]) {
    let mm = 0, pior_fora = 1e9, pior_dentro = 1e9, onde_f = null, onde_d = null;
    for (let i = 0; i < t.pts.length; i++) {
      if (i > 0) mm += Math.hypot(t.pts[i][0] - t.pts[i - 1][0], t.pts[i][2] - t.pts[i - 1][2]);
      const [x, y, z] = t.pts[i];
      const h = vulcao(x, z);
      const tun = t.tuneis.some(q => mm >= q[0] && mm <= q[1]);
      if (!tun && y - h < pior_fora) { pior_fora = y - h; onde_f = [Math.round(mm), Math.round(x), Math.round(z), Math.round(y), Math.round(h)]; }
      if (tun && h - y < pior_dentro) { pior_dentro = h - y; onde_d = [Math.round(mm), Math.round(x), Math.round(z), Math.round(y), Math.round(h)]; }
    }
    console.log(`  E${k + 1} ${t.nome}: raio mín ${t.rmin.toFixed(0)}  folga fora ${pior_fora.toFixed(0)} ${JSON.stringify(onde_f)}  rocha no túnel ${pior_dentro > 1e8 ? '-' : pior_dentro.toFixed(0)} ${JSON.stringify(onde_d)} túneis ${JSON.stringify(t.tuneis)}`);
  }
}
if (require.main === module || process.env.VERBOSO) {
  ps.forEach((p, k) => {
    const tun = [p.A, p.B, p.C].reduce((s, t) => s + t.tuneis.reduce((a, q) => a + q[1] - q[0], 0), 0);
    console.log(`== ${p.def.nome}: A ${p.A.m.toFixed(0)} B ${p.B.m.toFixed(0)} C ${p.C.m.toFixed(0)} total ${(p.A.m + p.B.m + p.C.m).toFixed(0)} túnel ${tun} | erro entrada plat ${p.errA.toFixed(1)} m | rampa (${p.C.fim.x.toFixed(0)},${p.C.fim.y.toFixed(0)},${p.C.fim.z.toFixed(0)}) h${p.C.fim.h.toFixed(0)} alvo (${p.alvo.map(v => v.toFixed(0))})`);
    for (const t of [p.A, p.B, p.C]) {
      console.log(`  ${t.nome}: ` + t.info.join(' | '));
      if (process.env.SEGS) for (const s of t.segs) console.log(`       ${s[0].toFixed(0).padStart(5)}-${s[1].toFixed(0).padStart(5)}  ${s[2]}  -> (${s[3].map(v => v.toFixed(0))})`);
    }
    conferir(p, k);
  });
  desenhar(__dirname + '/mapa.png', mundo, ps);
}
module.exports = { ps, mundo, defs };
