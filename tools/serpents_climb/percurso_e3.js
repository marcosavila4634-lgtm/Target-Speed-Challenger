// Serpent's Climb, etapa 3 "Cachoeira do Jaguar" feita do zero pelo desenho do dono (2026-10-06, captura da câmera livre
// x -703 y 2629 z -994): largada própria ao norte da Pirâmide da Lua, volta nela, desce pelo leste, plataforma no canto
// do sul, passa na cachoeira da cobra da toca, salta, volta pelo sul, sobe pelo meio e pelo oeste e salta do norte
// para o buraco do alvo, ao lado da pirâmide grande. Montanhas-armadilha nos quatro pontos amarelos do desenho.
// Uso: node tools/serpents_climb/percurso_e3.js [config/jogo.json]
const { gerar, V } = require('./etapa_lib');

const traco = [[168, 417], [141, 286], [26, 201], [-40, 52], [8, -76], [156, -109], [288, -64], [350, 50], [345, 190], [331, 333],
  [401, 470], [518, 519], [638, 468], [687, 308], [653, 49], [714, -88], [841, -170], [913, -354], [863, -566], [713, -709],
  [572, -869], [465, -1005], [317, -1100], [167, -1118], [85, -1049], [36, -906], [-34, -746], [-136, -615], [-290, -569],
  [-335, -590], [-455, -610], [-572, -744], [-643, -922], [-676, -1152], [-735, -1329], [-838, -1390], [-954, -1342],
  [-1023, -1206], [-1031, -1037], [-983, -850], [-864, -763], [-734, -662], [-647, -505], [-574, -326], [-444, -151],
  [-330, 53], [-291, 288], [-361, 458], [-508, 508], [-652, 435], [-808, 233], [-893, 32], [-1018, -193], [-1125, -410],
  [-1243, -577], [-1378, -597], [-1448, -451], [-1527, -190], [-1651, 59], [-1797, 247], [-1845, 391], [-1752, 514],
  [-1511, 612], [-1323, 662], [-1240, 560]];
const AMARELOS = [V(650, 26), V(465, -1005), V(-808, 233), V(-639, -505)];

gerar({
  n: 3, nome: 'Cachoeira do Jaguar', placa: 'TEMPLO DO JAGUAR',
  ctrl: traco, plat: 23, salto: 31, alvo: V(-1270, -145),
  plat_y: 75, labio: 125, topo: 235, vao: 45, diametro: 22, tempo_fator: 1.5,
  etapa: { _etapa: 'Difícil (desenho do dono 2026-10-06): 4 montanhas-armadilha (fogo e machados), cobra da toca, cobra da plataforma, cuspidoras, rochas caindo, pisos que caem, plataformas redondas, aceleradores contrários; alvo no poço, com vento.' },
  desafios: c => {
    const am = AMARELOS.map(p => c.onde(p));
    const cusp1 = [c.m('A', V(913, -354)) - 60, c.m('A', V(713, -709))];
    const cusp2 = [c.m('C', V(-735, -1329)), c.m('C', V(-1023, -1206))];
    const ilhas1 = [c.m('C', V(-444, -151)) + 10, c.m('C', V(-330, 53)) - 10];
    const ilhas2 = [c.m('C', V(-1527, -190)), c.m('C', V(-1600, -60))];
    const placas = [['A', c.m('A', V(26, 201)), c.m('A', V(-40, 52))], ['B', c.m('B', V(-34, -746)) - 30, c.m('B', V(-34, -746)) + 60],
      ['C', c.m('C', V(-1651, 59)), c.m('C', V(-1845, 391))], ['C', c.m('C', V(-361, 458)), c.m('C', V(-508, 508))]];
    const toca = c.onde(V(-335, -590));
    const evitar = [...am.map(([t, m]) => [t, m - 70, m + 40]), ['C', ilhas1[0] - 20, ilhas1[1] + 20], ['C', ilhas2[0] - 20, ilhas2[1] + 20],
      ...placas.map(([t, a, b]) => [t, a - 10, b + 10]), [toca[0], toca[1] - 40, toca[1] + 40]];
    const livre = (t, m) => !evitar.some(([t2, a, b]) => t2 === t && m >= a && m <= b);
    const checkpoints = [];
    for (const t of ['A', 'B', 'C']) for (let m = t === 'C' ? 300 : 160; m < c.total(t) - 150; m += 620) {
      let mm = m;
      while (!livre(t, mm) && mm < c.total(t) - 150) mm += 20;
      if (livre(t, mm)) checkpoints.push([t, mm]);
    }
    for (const [t, m] of am) checkpoints.push([t, m + 50]);
    checkpoints.sort((a, b) => a[0].localeCompare(b[0]) || a[1] - b[1]);
    const lado = (t, m0, m1, l, d) => c.aoLado(t, m0, m1, l, d);
    return {
      armadilhas: {
        laminas: [[...am[0], 0, 4.0, 'fogo', 3, 14, -0.7], [...am[1], 0.4, 4.0, 'rocha', 3, 14, -0.7], [...am[2], 1.1, 3.8, 'fogo', 3, 13, -0.6], [...am[3], 0.2, 3.8, 'rocha', 3, 13, -0.6],
          // no lugar das lâminas antigas, a montanha com machados (pedido do dono)
          ['A', c.m('A', V(401, 470)), 0.5, 3.8, 'rocha', 3, 13, -0.6], ['C', c.m('C', V(-1378, -597)), 2.6, 3.6, 'rocha', 3, 13, -0.6]].map(x => [x[0], Math.round(x[1] + (x.length > 4 ? 21 : 0)), ...x.slice(2)]),
        lamina: { periodo: 3.9, amplitude: 64, comprimento: 9.5 },
        lancas: [['A', c.m('A', V(841, -170)), 0], ['B', c.m('B', V(85, -1049)) + 40, 1], ['C', c.m('C', V(-1125, -410)), 0.5], ['C', c.m('C', V(-1797, 247)), 2]],
        lanca: { periodo: 4.2, mover_s: 0.3, fora_s: 1.8, comprimento: 12 },
        serpentes: [['C', c.m('C', V(-983, -850)), 0], ['C', c.m('C', V(-1243, -577)), 2.5]],
        serpente: { periodo: 5.2, fecha_s: 0.35, fechada_s: 1.4, abre_s: 1.0 },
        jatos: [['A', c.m('A', V(638, 468)), 1, 0], ['C', c.m('C', V(-291, 288)), -1, 1.2], ['C', c.m('C', V(-1752, 514)), 1, 2.4]],
        jato: { periodo: 3.8, ligado_s: 1.7, forca: 18 },
        placas, placa: { comprimento: 4, tempo_s: 0.8, volta_s: 6, aderencia: 0.9 },
        cuspidoras: [['A', ...cusp1, 8], ['C', ...cusp2, 8]],
        cuspidora: { alcance: 65, veneno_s: 3.5, intervalo: [4.0, 8.0], altura_cabeca: 5.0, erro_m: 4.5 },
        quedas: [['C', c.m('C', V(-676, -1152)), c.m('C', V(-1031, -1037)), [0.4, 1.1]]],
        queda: { intervalo: [1.2, 3.5], tamanho: [3, 6], tranco: 16 },
      },
      ilhas_pista: [['C', ...ilhas1, 10, 23.5], ['C', ...ilhas2, 10, 23.5]],
      impulsos: [['A', 260], ['A', c.m('A', V(518, 519))], ['B', 130], ['B', -62, 12], ['C', 300], ['C', ilhas1[0] - 60], ['C', ilhas2[0] - 60],
        ['C', c.m('C', V(-330, 53)) + 80], ['C', c.m('C', V(-1448, -451))],
        ['C', -115, 16, 'fixo'], ['C', -100, 32, 'fixo'], ['C', -85, 16, 'fixo'], ['C', -70, 16, 'fixo'], ['C', -55, 16, 'fixo'], ['C', -40, 16, 'fixo'], ['C', -25, 16, 'fixo']],
      impulsos_re: [['C', c.m('C', V(-574, -326)), -2.6, 2.4, 20], ['C', c.m('C', V(-1018, -193)), 2.6, 2.4, 20]],
      ejetores: [['A', c.m('A', V(8, -76)), 25, 100], ['C', c.m('C', V(-1031, -1037)) + 40, 25, 100], ['C', c.m('C', V(-1511, 612)), 25, 100]],
      checkpoints,
      rochas: [...c.rochasArco('A', ...cusp1, 1, 4, 100)], // (as do sul usam a encosta do morro)
      cobra_toca: { trecho: toca[0], metros: toca[1], lado: 1 },
      cobra_arena: true,
    };
  },
});
