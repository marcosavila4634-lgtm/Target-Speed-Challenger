// Traçado do Frozen Peak: tartaruga de retas/curvas com marcas de salto (vão), gelo e estreito.
const D = Math.PI / 180;
const dirv = h => [Math.sin(h * D), -Math.cos(h * D)];
// Comandos: ['R', comp, dy], ['C', raio, ang(+dir), dy], ['TO', x, z, y],
// ['S', vao, queda] salto (rampinha + vão + pouso), ['GI', aderencia]/['GF'] gelo, ['EI', largura]/['EF'] estreito
function tartaruga(ini, cmds, nome) {
  let x = ini.x, z = ini.z, y = ini.y, h = ini.h;
  const pts = [[x, y, z]];
  const info = [], vaos = [], gelo = [], estreitos = [], segs = [], tags = {};
  let total = 0, m = 0;      // total = horizontal; m = 3D (como o jogo mede)
  let gi = null, ei = null;
  const reta = (comp, dy, passo = 30) => {
    const n = Math.max(1, Math.round(comp / passo));
    const d = dirv(h);
    for (let k = 1; k <= n; k++) pts.push([x + d[0] * comp * k / n, y + dy * k / n, z + d[1] * comp * k / n]);
    x += d[0] * comp; z += d[1] * comp; y += dy; total += comp; m += Math.hypot(comp, dy);
  };
  for (const c of cmds) {
    const m0 = m;
    // Etiqueta ('#nome' no fim do comando): guarda o metro em que o segmento começa
    if (typeof c[c.length - 1] === 'string' && c[c.length - 1][0] === '#') tags[c[c.length - 1]] = m0;
    if (c[0] === 'R') {
      reta(c[1], c[2]);
      info.push(`R ${c[1]} ${(100 * c[2] / c[1]).toFixed(1)}%`);
      segs.push([m0, m, `R ${c[1]}`, [x, y, z]]);
    } else if (c[0] === 'C') {
      const r = c[1], ang = c[2], dy = c[3];
      const s = Math.sign(ang);
      const nrm = [Math.cos(h * D), Math.sin(h * D)];
      const cx = x + nrm[0] * r * s, cz = z + nrm[1] * r * s;
      const n = Math.max(2, Math.round(Math.abs(ang) / 12));
      const comp = r * Math.abs(ang) * D;
      for (let k = 1; k <= n; k++) {
        const hk = h + ang * k / n;
        const nk = [Math.cos(hk * D), Math.sin(hk * D)];
        pts.push([cx - nk[0] * r * s, y + dy * k / n, cz - nk[1] * r * s]);
      }
      const hn = h + ang; const nn = [Math.cos(hn * D), Math.sin(hn * D)];
      x = cx - nn[0] * r * s; z = cz - nn[1] * r * s; y += dy; h = hn; total += comp; m += Math.hypot(comp, dy);
      info.push(`C r${r} ${ang}° ${comp.toFixed(0)}m ${(100 * dy / comp).toFixed(1)}%`);
      segs.push([m0, m, `C r${r} ${ang}`, [x, y, z]]);
    } else if (c[0] === 'TO') {
      const dx = c[1] - x, dz = c[2] - z;
      const comp = Math.hypot(dx, dz);
      const hh = Math.atan2(dx, -dz) / D;
      const err = ((hh - h + 540) % 360) - 180;
      const n = Math.max(1, Math.round(comp / 30));
      for (let k = 1; k <= n; k++) pts.push([x + dx * k / n, y + (c[3] - y) * k / n, z + dz * k / n]);
      info.push(`TO ${comp.toFixed(0)}m ${(100 * (c[3] - y) / comp).toFixed(1)}% erro_rumo ${err.toFixed(1)}°`);
      m += Math.hypot(comp, c[3] - y);
      x = c[1]; z = c[2]; y = c[3]; total += comp; h = hh;
      segs.push([m0, m, `TO`, [x, y, z]]);
    } else if (c[0] === 'S') {
      // Rampinha de 16 m subindo 1,6 m (10%), vão, pouso `queda` m abaixo do lábio e 20 m planos
      const vao = c[1], queda = c[2];
      reta(12, 1.2, 12);
      reta(4, 0.4, 4);
      const labio = [x, y, z];
      const m_labio = m;
      reta(3, 0.3, 3);                         // dentro do vão (invisível): segura a tangente do lábio
      reta(vao - 3, -(queda + 0.3), vao);      // até o começo do pouso
      vaos.push([labio[0], labio[1], labio[2], vao]);
      reta(20, 0, 20);
      info.push(`SALTO vão ${vao} queda ${queda}`);
      segs.push([m0, m, `SALTO vão ${vao} (lábio em m=${m_labio.toFixed(0)})`, [x, y, z]]);
    } else if (c[0] === 'GI') { gi = [m, c[1]];
    } else if (c[0] === 'GF') { gelo.push([Math.round(gi[0]), Math.round(m), gi[1]]); gi = null;
    } else if (c[0] === 'EI') { ei = [m, c[1]];
    } else if (c[0] === 'EF') { estreitos.push([Math.round(ei[0]), Math.round(m), ei[1]]); ei = null; }
  }
  return { pts, fim: { x, z, y, h }, total, m, info, nome, vaos, gelo, estreitos, segs, tags };
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
module.exports = { percurso, tartaruga, dirv };
