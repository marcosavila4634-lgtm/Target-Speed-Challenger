// Traçado do Extinction Day: tartaruga de retas/curvas (como o Frozen Peak) com mais três comandos:
//   ['H', x, z, y, rumo, k]  curva de Hermite até (x, y, z) chegando no rumo dado (graus, 0 = norte, 90 = leste)
//   ['ESP', cx, cz, r1, ang, dy]  espiral em volta de (cx, cz): varre `ang` graus (+ = horário visto de cima)
//                                  indo do raio atual até r1 (túnel por dentro do vulcão)
//   ['T0'] / ['T1']  começo e fim de túnel (o terreno fica por cima da estrada)
//   ['LOOP', raio, transição, desvio]  looping (Looping no jogo): a estrada fica plana e faz um "S" por baixo do laço,
//                                  da entrada até a saída (sem laje nesse pedaço: o piso é a fita do looping)
// e os de antes: ['R', comp, dy], ['C', raio, ang, dy], ['TO', x, z, y], ['S', vão, queda], ['EI', larg]/['EF'].
const D = Math.PI / 180;
const dirv = h => [Math.sin(h * D), -Math.cos(h * D)];
const rumo = (dx, dz) => Math.atan2(dx, -dz) / D;

// ------------------------------------------------------------------ vulcão (igual a Dino.vulcao no jogo)
const V = { x: -400, z: -1150, borda: 230, base: 1000, altura: 560, fundo: 430 };
function vulcao(x, z) {
  const r = Math.hypot(x - V.x, z - V.z);
  if (r >= V.base) return -1e9;
  if (r < V.borda) {
    const f = Math.min(Math.max((r - 120) / (V.borda - 120), 0), 1);
    return V.fundo + (V.altura - V.fundo) * f * f * (3 - 2 * f);
  }
  const t = (r - V.borda) / (V.base - V.borda);
  const s = t * t * (3 - 2 * t);
  return V.altura * Math.pow(1 - s, 1.4);
}

// Perfil do looping visto de lado (igual a Looping.perfil no jogo): a curvatura cresce de 0 a 1/r em `lt` m,
// fica constante e volta a 0 em `lt` m, girando 360°. Devolve o comprimento, o avanço até a saída e a altura.
function perfil_loop(r, lt) {
  const k = 1 / r, L = 2 * lt + (2 * Math.PI - k * lt) / k;
  const n = Math.round(L / 0.25); const passo = L / n;
  let x = 0, y = 0, th = 0, H = 0;
  for (let i = 0; i < n; i++) {
    const um = (i + 0.5) * passo;
    const kk = um < lt ? k * um / lt : (um > L - lt ? k * (L - um) / lt : k);
    th += kk * passo / 2; x += Math.cos(th) * passo; y += Math.sin(th) * passo; th += kk * passo / 2;
    H = Math.max(H, y);
  }
  return { L, x_fim: x, H };
}
// Saída do looping em relação à entrada (m à frente e m para a direita): o laço é uma hélice, a fita
// desloca `desvio` m de lado ao longo da volta para a perna de saída não bater na de entrada
function saida_loop(r, lt, desvio) {
  const pf = perfil_loop(r, lt);
  const tg = desvio / pf.L, c = 1 / Math.hypot(1, tg), s = tg * c;
  return { frente: pf.x_fim * c + desvio * s, lado: -pf.x_fim * s + desvio * c, L: pf.L, H: pf.H };
}

function tartaruga(ini, cmds0, nome) {
  let x = ini.x, z = ini.z, y = ini.y, h = ini.h;
  const pts = [[x, y, z]];
  const info = [], vaos = [], estreitos = [], tuneis = [], segs = [], tags = {}, loops = [];
  // LOOP vira: reta curta, marca da entrada, "S" de dois arcos até a saída e outra reta curta (tudo plano).
  // Os primeiros e os últimos RETO m embaixo da fita seguem retos: os bots entram e saem alinhados com ela.
  const cmds = [];
  for (const c of cmds0) {
    if (c[0] !== 'LOOP') { cmds.push(c); continue; }
    const sd = saida_loop(c[1], c[2], c[3]);
    const RETO = 10;
    const th = 2 * Math.atan2(sd.lado, sd.frente - 2 * RETO);
    const rr = (sd.frente - 2 * RETO) / (2 * Math.sin(th));
    const tag = typeof c[c.length - 1] === 'string' && c[c.length - 1][0] === '#' ? [c[c.length - 1]] : [];
    cmds.push(['R', 12, 0], ['LOOP0', c[1], c[2], c[3], sd, ...tag], ['R', RETO, 0], ['CF', rr, th / D], ['CF', rr, -th / D], ['R', RETO, 0], ['R', 12, 0]);
  }
  let total = 0, m = 0, ei = null, t0 = null, rmin = 1e9;
  const reta = (comp, dy, passo = 30) => {
    const n = Math.max(1, Math.round(comp / passo));
    const d = dirv(h);
    for (let k = 1; k <= n; k++) pts.push([x + d[0] * comp * k / n, y + dy * k / n, z + d[1] * comp * k / n]);
    x += d[0] * comp; z += d[1] * comp; y += dy; total += comp; m += Math.hypot(comp, dy);
  };
  for (const c of cmds) {
    const m0 = m;
    if (typeof c[c.length - 1] === 'string' && c[c.length - 1][0] === '#') tags[c[c.length - 1]] = m0;
    if (c[0] === 'R') {
      reta(c[1], c[2]);
      info.push(`R ${c[1]} ${(100 * c[2] / c[1]).toFixed(1)}%`);
      segs.push([m0, m, `R ${c[1]}`, [x, y, z]]);
    } else if (c[0] === 'LOOP0') {
      loops.push([Math.round(m * 10) / 10, c[1], c[2], c[3], Math.round(c[4].frente * 10) / 10]);
      info.push(`LOOP r${c[1]} altura ${c[4].H.toFixed(0)} fita ${c[4].L.toFixed(0)}m saída +${c[4].frente.toFixed(1)} lado ${c[4].lado.toFixed(1)}`);
    } else if (c[0] === 'C' || c[0] === 'CF') {
      const r = c[1], ang = c[2], dy = c[0] === 'CF' ? 0 : c[3];
      const s = Math.sign(ang);
      const nrm = [Math.cos(h * D), Math.sin(h * D)];
      const cx = x + nrm[0] * r * s, cz = z + nrm[1] * r * s;
      const n = c[0] === 'CF' ? 6 : Math.max(2, Math.round(Math.abs(ang) / 12));
      const comp = r * Math.abs(ang) * D;
      for (let k = 1; k <= n; k++) {
        const hk = h + ang * k / n;
        const nk = [Math.cos(hk * D), Math.sin(hk * D)];
        pts.push([cx - nk[0] * r * s, y + dy * k / n, cz - nk[1] * r * s]);
      }
      const hn = h + ang; const nn = [Math.cos(hn * D), Math.sin(hn * D)];
      x = cx - nn[0] * r * s; z = cz - nn[1] * r * s; y += dy; h = hn; total += comp; m += Math.hypot(comp, dy);
      if (c[0] !== 'CF') rmin = Math.min(rmin, r);
      info.push(`C r${Math.round(r)}${ang}° ${comp.toFixed(0)}m ${(100 * dy / comp).toFixed(1)}%`);
      segs.push([m0, m, `C r${r} ${ang}`, [x, y, z]]);
    } else if (c[0] === 'TO') {
      const dx = c[1] - x, dz = c[2] - z;
      const comp = Math.hypot(dx, dz);
      const hh = rumo(dx, dz);
      const err = ((hh - h + 540) % 360) - 180;
      const n = Math.max(1, Math.round(comp / 30));
      for (let k = 1; k <= n; k++) pts.push([x + dx * k / n, y + (c[3] - y) * k / n, z + dz * k / n]);
      info.push(`TO ${comp.toFixed(0)}m ${(100 * (c[3] - y) / comp).toFixed(1)}% erro_rumo ${err.toFixed(1)}°`);
      m += Math.hypot(comp, c[3] - y);
      x = c[1]; z = c[2]; y = c[3]; total += comp; h = hh;
      segs.push([m0, m, `TO`, [x, y, z]]);
    } else if (c[0] === 'H') {
      // Hermite: (x, z) → (c1, c2) saindo no rumo h e chegando no rumo c4
      const [, xb, zb, yb, hb] = c;
      const k = c.length > 5 && typeof c[5] === 'number' ? c[5] : 0.5;
      const dist = Math.hypot(xb - x, zb - z);
      const da = dirv(h), db = dirv(hb);
      const p0 = [x, z], p1 = [xb, zb], m0v = [da[0] * dist * k * 2, da[1] * dist * k * 2], m1v = [db[0] * dist * k * 2, db[1] * dist * k * 2];
      const n = Math.max(4, Math.round(dist / 12));
      let comp = 0, prev = [x, z], hprev = h;
      for (let i = 1; i <= n; i++) {
        const t = i / n, t2 = t * t, t3 = t2 * t;
        const a = 2 * t3 - 3 * t2 + 1, b = t3 - 2 * t2 + t, cc = -2 * t3 + 3 * t2, d = t3 - t2;
        const q = [a * p0[0] + b * m0v[0] + cc * p1[0] + d * m1v[0], a * p0[1] + b * m0v[1] + cc * p1[1] + d * m1v[1]];
        const seg = Math.hypot(q[0] - prev[0], q[1] - prev[1]);
        const hq = rumo(q[0] - prev[0], q[1] - prev[1]);
        const dh = Math.abs(((hq - hprev + 540) % 360) - 180);
        if (i > 1 && dh > 0.01) rmin = Math.min(rmin, seg / (dh * D));
        hprev = hq;
        comp += seg;
        prev = q;
        pts.push([q[0], y + (yb - y) * t, q[1]]);
      }
      info.push(`H ${comp.toFixed(0)}m ${(100 * (yb - y) / comp).toFixed(1)}%`);
      m += Math.hypot(comp, yb - y);
      x = xb; z = zb; y = yb; h = hb; total += comp;
      segs.push([m0, m, `H`, [x, y, z]]);
    } else if (c[0] === 'ESP') {
      const [, cx, cz, r1, ang, dy] = c;
      const r0 = Math.hypot(x - cx, z - cz);
      const a0 = Math.atan2(z - cz, x - cx);
      const n = Math.max(6, Math.round(Math.abs(ang) / 2.5));
      let comp = 0, px = x, pz = z;
      for (let k = 1; k <= n; k++) {
        const f = k / n;
        const r = r0 + (r1 - r0) * (f * f * (3 - 2 * f));
        const a = a0 + ang * D * f;
        const q = [cx + Math.cos(a) * r, cz + Math.sin(a) * r];
        comp += Math.hypot(q[0] - px, q[1] - pz);
        px = q[0]; pz = q[1];
        pts.push([q[0], y + dy * f, q[1]]);
      }
      const a1 = a0 + ang * D;
      // rumo da tangente no fim (sentido do giro)
      const tg = [-Math.sin(a1) * Math.sign(ang), Math.cos(a1) * Math.sign(ang)];
      h = rumo(tg[0], tg[1]);
      rmin = Math.min(rmin, Math.min(r0, r1));
      info.push(`ESP r${r0.toFixed(0)}→${r1} ${ang}° ${comp.toFixed(0)}m ${(100 * dy / comp).toFixed(1)}%`);
      m += Math.hypot(comp, dy);
      x = px; z = pz; y += dy; total += comp;
      segs.push([m0, m, `ESP`, [x, y, z]]);
    } else if (c[0] === 'S') {
      const vao = c[1], queda = c[2];
      reta(12, 1.2, 12);
      reta(4, 0.4, 4);
      const labio = [x, y, z];
      const m_labio = m;
      reta(3, 0.3, 3);
      reta(vao - 3, -(queda + 0.3), vao);
      vaos.push([labio[0], labio[1], labio[2], vao]);
      reta(20, 0, 20);
      info.push(`SALTO vão ${vao} queda ${queda}`);
      segs.push([m0, m, `SALTO vão ${vao} (lábio em m=${m_labio.toFixed(0)})`, [x, y, z]]);
    } else if (c[0] === 'EI') { ei = [m, c[1]];
    } else if (c[0] === 'EF') { estreitos.push([Math.round(ei[0]), Math.round(m), ei[1]]); ei = null;
    } else if (c[0] === 'T0') { t0 = m;
    } else if (c[0] === 'T1') { tuneis.push([Math.round(t0), Math.round(m)]); t0 = null; }
  }
  if (t0 !== null) tuneis.push([Math.round(t0), Math.round(m) + 1]);
  return { pts, fim: { x, z, y, h }, total, m, info, nome, vaos, estreitos, tuneis, segs, tags, rmin, loops };
}

// Ponto e rumo para entrar numa espiral em volta de (cx, cz) no raio r, no ângulo a (graus, de +x para +z),
// girando no sentido s (+1 horário visto de cima = ângulo crescendo)
function na_espiral(cx, cz, r, a, s) {
  const x = cx + Math.cos(a * D) * r, z = cz + Math.sin(a * D) * r;
  const tg = [-Math.sin(a * D) * s, Math.cos(a * D) * s];
  return [x, z, rumo(tg[0], tg[1])];
}

function percurso(def) {
  const L = def.largada; const F = dirv(L.h);
  const exitA = { x: L.o[0] + F[0] * (L.comp + 2), z: L.o[2] + F[1] * (L.comp + 2), y: L.o[1], h: L.h };
  const A = tartaruga(exitA, def.A, 'A');
  const P = def.plat; const Fp = dirv(P.h); const Lat = [-Fp[1], Fp[0]];
  const ent = [P.o[0] + Fp[0] * P.xe + Lat[0] * P.s * (P.larg / 2 + 3), P.o[2] + Fp[1] * P.xe + Lat[1] * P.s * (P.larg / 2 + 3)];
  const errA = Math.hypot(A.fim.x - ent[0], A.fim.z - ent[1]);
  const B = tartaruga({ x: P.o[0] + Fp[0] * (P.comp + 1), z: P.o[2] + Fp[1] * (P.comp + 1), y: P.o[1], h: P.h }, def.B, 'B');
  const d = dirv(B.fim.h);
  const C = tartaruga({ x: B.fim.x + d[0] * 30, z: B.fim.z + d[1] * 30, y: B.fim.y - 1.8, h: B.fim.h }, def.C, 'C');
  const dc = dirv(C.fim.h);
  const alvo = [C.fim.x + dc[0] * def.dist, C.fim.z + dc[1] * def.dist];
  return { def, A, B, C, ent, errA, alvo, exitA };
}
module.exports = { percurso, tartaruga, dirv, rumo, na_espiral, vulcao, V, D, perfil_loop, saida_loop };
