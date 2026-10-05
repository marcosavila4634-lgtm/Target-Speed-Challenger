// Aceleradores e molas ejetoras espalhados pela plataforma dos buracos do Extinction Day (pedido do dono,
// 2026-10-04, "estilo o de gelo"): 12 aceleradores vermelhos ao todo (os 3 que já havia + 9) e 10 molas.
// Posições sorteadas com semente fixa por etapa, longe dos buracos, da porta de entrada (que já é forrada
// de aceleradores pelo jogo), do corredor da saída e uns dos outros. Cada acelerador novo aponta para o
// buraco mais perto, com um desvio de até 20°.
//   node plataforma_extras.js   → imprime as linhas "impulsos" e "molas" de cada etapa (para conferir o jogo.json)
function sorteio(semente) {
  let a = semente >>> 0;
  return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
}

// k = etapa (0..3); s = lado da porta (+1/-1); xe = x do centro da porta; buracos [[x, lat, raio]]; base = aceleradores que já existem
function extras(k, s, xe, comp, larg, buracos, base, n_acel = 12, n_molas = 10) {
  const rnd = sorteio(7919 * (k + 1));
  const meia = larg / 2;
  const postos = base.map(i => [i[0], i[1], 4]);   // [x, lat, raio ocupado]
  const livre = (x, lat, raio) => {
    if (x < 9 || x > comp - 7 || Math.abs(lat) > meia - 7) return false;
    if (x > comp - 16 && Math.abs(lat) < 13) return false;                       // corredor da saída
    if (Math.abs(x - xe) < 15 && s * lat > meia - 19) return false;              // porta forrada de aceleradores
    for (const b of buracos) if (Math.hypot(x - b[0], lat - b[1]) < b[2] + raio + 1.5) return false;
    for (const p of postos) if (Math.hypot(x - p[0], lat - p[1]) < p[2] + raio + 1.5) return false;
    return true;
  };
  const sortear = (raio) => {
    for (let t = 0; t < 4000; t++) {
      const x = Math.round(9 + rnd() * (comp - 16)), lat = Math.round((rnd() * 2 - 1) * (meia - 7));
      if (livre(x, lat, raio)) { postos.push([x, lat, raio]); return [x, lat]; }
    }
    return null;
  };
  const impulsos = [], molas = [];
  for (let n = base.length; n < n_acel; n++) {
    const p = sortear(4);
    if (!p) break;
    let perto = null;
    for (const b of buracos) if (!perto || Math.hypot(b[0] - p[0], b[1] - p[1]) < Math.hypot(perto[0] - p[0], perto[1] - p[1])) perto = b;
    const ang = Math.atan2(perto[1] - p[1], perto[0] - p[0]) * 180 / Math.PI + (rnd() * 40 - 20);
    impulsos.push([p[0], p[1], Math.round(ang / 5) * 5, false]);
  }
  for (let n = 0; n < n_molas; n++) {
    const p = sortear(3.2);
    if (!p) break;
    molas.push([p[0], p[1], 9 + Math.round(rnd() * 3)]);
  }
  return { impulsos, molas };
}

module.exports = { extras };

if (require.main === module) {
  // As plataformas com piso como estão no jogo.json (E2 é o poço sem chão: sem aceleradores nem molas)
  const etapas = [
    { k: 0, s: -1, b: [[22, 22, 6], [30, -24, 6], [52, 0, 7], [70, 28, 6], [74, -20, 6], [88, 6, 5], [50, -18, 5]], i: [[34, -34, 35, false], [58, 40, 0, false], [76, -2, 0, false]] },
    { k: 2, s: 1, b: [[16, -22, 5.5], [22, 18, 6], [38, -6, 7], [42, 26, 5], [54, -26, 5.5], [58, 8, 6], [70, -14, 5], [74, 24, 5], [82, -30, 4.5], [50, 18, 5]], i: [[34, 34, -35, false], [58, -40, 0, false], [76, 2, 0, false]] },
    { k: 3, s: -1, b: [[18, 24, 6], [24, -22, 6.5], [40, 6, 7], [46, -30, 5.5], [58, 30, 6], [62, -10, 6.5], [74, 16, 5.5], [78, -26, 5], [88, 2, 5], [90, 32, 4.5], [92, -34, 4.5], [50, -18, 5]], i: [[34, -34, 35, false], [58, 40, 0, false], [76, -2, 0, false]] },
  ];
  const linha = a => JSON.stringify(a).replace(/,/g, ', ');
  for (const e of etapas) {
    const ex = extras(e.k, e.s, 50, 100, 100, e.b, e.i);
    console.log('E' + (e.k + 1));
    console.log('"impulsos": ' + linha(e.i.concat(ex.impulsos)) + ',');
    console.log('"molas": ' + linha(ex.molas));
  }
}
