// Serpent's Climb, etapa 4 "Pedra do Sol" feita do zero pelo desenho do dono (2026-10-06, captura da câmera livre
// x -497 y 3361 z -1195): QUASE IMPOSSÍVEL (pedido do dono). Largada no sul-leste, volta em volta da Pirâmide da Lua,
// sobe em diagonal até o norte, grampo, desce de volta, laço do sul, plataforma, cachoeira da cobra da toca, salto,
// volta pelo sul, laço em volta da pirâmide grande e reta final para o poço do alvo encostado no paredão oeste.
// O alvo gira (etapas[3].giro) e tem vento; o tempo é curto.
// Uso: node tools/serpents_climb/percurso_e4.js [config/jogo.json]
const { gerar, V } = require('./etapa_lib');

const traco = [[530, -865], [579, -683], [728, -540], [877, -419], [961, -241], [942, -82], [806, -23], [584, -48], [378, -73],
  [100, -63], [-126, -17], [-192, 175], [-129, 369], [85, 446], [317, 393], [428, 181], [400, -116], [328, -348], [148, -419],
  [-69, -335], [-211, -200], [-330, -37], [-451, 129], [-574, 300], [-702, 445], [-858, 566],
  [-950, 640], [-1030, 625], [-1055, 555], [-1000, 480],                                           // grampo do norte
  [-833, 393], [-716, 194], [-558, -29], [-388, -220], [-171, -382], [21, -465], [185, -571], [277, -746], [248, -960],
  [145, -1059], [28, -1036], [-45, -855], [-90, -660], [-231, -581], [-335, -590], [-427, -599], [-553, -741], [-622, -976],
  [-661, -1227], [-779, -1378], [-940, -1408], [-1046, -1280], [-1066, -1053], [-987, -822], [-818, -659], [-707, -465],
  [-723, -234], [-888, -134], [-1139, -115], [-1363, -175], [-1447, -353], [-1377, -541], [-1216, -581], [-1086, -452],
  [-1074, -117], [-1055, 150], [-1109, 431], [-1130, 620], [-1150, 760], [-1200, 800]];

gerar({
  n: 4, nome: 'Pedra do Sol', placa: 'TEMPLO DO SOL NEGRO',
  ctrl: traco, plat: 40, salto: 46, alvo: V(-1980, 500),
  plat_y: 120, labio: 165, topo: 300, vao: 55, diametro: 18, tempo_fator: 1.3,
  etapa: { _etapa: 'QUASE IMPOSSÍVEL (desenho do dono 2026-10-06): 8 montanhas-armadilha (fogo e machados) mais rápidas, aceleradores contrários, pisos que caem longos, 3 grupos de cuspidoras, chuva de rochas, cobra da toca e da plataforma, salto longo, tempo curto e a Pedra do Sol girando com vento.' },
  desafios: c => {
    const mont = [[V(728, -540), 'fogo'], [V(240, -68), 'rocha'], [V(-160, 80), 'fogo'], [V(-400, 60), 'rocha'], [V(-640, -60), 'fogo'],
      [V(-640, -1110), 'rocha'], [V(-1040, -960), 'fogo'], [V(-1065, 10), 'rocha']].map(([p, tipo], k) => {
      const [t, m] = c.onde(p);
      return [t, m + 21, (k * 0.9) % 3.2, 3.3, tipo, 3, 13, -0.55];
    });
    const ilhas1 = [c.m('A', V(-126, -17)) - 260, c.m('A', V(-126, -17)) - 30];
    const ilhas2 = [c.m('C', V(-1139, -115)) + 20, c.m('C', V(-1363, -175)) - 20];
    const cusp = [['A', c.m('A', V(877, -419)), c.m('A', V(942, -82)), 9], ['C', c.m('C', V(-661, -1227)), c.m('C', V(-1046, -1280)), 10],
      ['C', c.m('C', V(-1447, -353)), c.m('C', V(-1216, -581)), 8]];
    const placas = [['A', c.m('A', V(-574, 300)), c.m('A', V(-858, 566))], ['B', c.m('B', V(-45, -855)) - 80, c.m('B', V(-45, -855)) + 40],
      ['C', c.m('C', V(-987, -822)), c.m('C', V(-707, -465))], ['C', c.m('C', V(-1055, 150)) + 60, c.m('C', V(-1130, 620)) - 30]];
    const toca = c.onde(V(-335, -590));
    const evitar = [...mont.map(([t, m]) => [t, m - 75, m + 40]), ['A', ilhas1[0] - 20, ilhas1[1] + 20], ['C', ilhas2[0] - 20, ilhas2[1] + 20],
      ...placas.map(([t, a, b]) => [t, a - 10, b + 10]), [toca[0], toca[1] - 40, toca[1] + 40]];
    const livre = (t, m) => !evitar.some(([t2, a, b]) => t2 === t && m >= a && m <= b);
    // Poucos pontos de volta (quase impossível): a cada ~900 m
    const checkpoints = [];
    for (const t of ['A', 'B', 'C']) for (let m = t === 'C' ? 320 : 200; m < c.total(t) - 150; m += 900) {
      let mm = m;
      while (!livre(t, mm) && mm < c.total(t) - 150) mm += 20;
      if (livre(t, mm)) checkpoints.push([t, mm]);
    }
    const re = (p, lat) => { const [t, m] = c.onde(p); return [t, m, lat, 2.4, 24]; };
    return {
      armadilhas: {
        laminas: mont,
        lamina: { periodo: 3.3, amplitude: 66, comprimento: 9.5 },
        lancas: [['A', c.m('A', V(961, -241)), 0], ['A', c.m('A', V(85, 446)), 1.2], ['B', c.m('B', V(185, -571)), 0.5],
          ['C', c.m('C', V(-779, -1378)), 1.8], ['C', c.m('C', V(-888, -134)), 0.3]],
        lanca: { periodo: 3.6, mover_s: 0.25, fora_s: 1.9, comprimento: 14 },
        serpentes: [['A', c.m('A', V(400, -116)), 0], ['B', c.m('B', V(248, -960)), 1.6], ['C', c.m('C', V(-1109, 431)), 2.4]],
        serpente: { periodo: 4.6, fecha_s: 0.3, fechada_s: 1.5, abre_s: 0.9 },
        jatos: [['A', c.m('A', V(-129, 369)), 1, 0], ['A', c.m('A', V(-1030, 625)), -1, 1], ['C', c.m('C', V(-723, -234)), 1, 2], ['C', c.m('C', V(-1086, -452)), -1, 0.5]],
        jato: { periodo: 3.4, ligado_s: 1.8, forca: 21 },
        placas, placa: { comprimento: 4, tempo_s: 0.6, volta_s: 7, aderencia: 0.85 },
        cuspidoras: cusp,
        cuspidora: { alcance: 70, veneno_s: 4, intervalo: [3.0, 6.0], altura_cabeca: 5.0, erro_m: 3.0 },
        quedas: [['C', c.m('C', V(-622, -976)), c.m('C', V(-1066, -1053)), [0.25, 0.7]], ['B', c.m('B', V(277, -746)), c.m('B', V(28, -1036)), [0.4, 1.0]]],
        queda: { intervalo: [1.0, 3.0], tamanho: [3.5, 7], tranco: 18 },
      },
      ilhas_pista: [['A', ...ilhas1, 9, 24], ['C', ...ilhas2, 9, 24]],
      impulsos: [['A', 260], ['B', 130], ['B', -62, 12], ['C', 320], ['C', ilhas2[0] - 60],
        ['C', -115, 16, 'fixo'], ['C', -100, 32, 'fixo'], ['C', -85, 16, 'fixo'], ['C', -70, 16, 'fixo'], ['C', -55, 16, 'fixo'], ['C', -40, 16, 'fixo'], ['C', -25, 16, 'fixo']],
      impulsos_re: [re(V(806, -23), -2.6), re(V(-192, 175), 2.6), re(V(-716, 194), -2.6), re(V(-1066, -1053), 2.6), re(V(-1074, -117), -2.6), re(V(-1150, 760), 2.6)],
      ejetores: [['A', c.m('A', V(-451, 129)) - 40, 25, 100], ['B', c.m('B', V(-90, -660)), 25, 100], ['C', c.m('C', V(-818, -659)), 25, 100]],
      checkpoints,
      rochas: [...c.rochasArco('C', c.m('C', V(-1447, -353)), c.m('C', V(-1216, -581)), 1, 3, 100)],
      cobra_toca: { trecho: toca[0], metros: toca[1], lado: 1, detecta: 80 },
      cobra_arena: true,
    };
  },
});
