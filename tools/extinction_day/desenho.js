// Desenho de cima (PNG) dos 4 percursos: estradas (túnel mais escuro), vulcão, cercados e alvos.
const fs = require('fs');
const png = require('./png.js');
module.exports = function (arquivo, mundo, percursos, extras = {}) {
  const X0 = -3000, X1 = 2100, Z0 = -2700, Z1 = 1900, E = 0.25;
  const W = Math.round((X1 - X0) * E), H = Math.round((Z1 - Z0) * E);
  const px = Buffer.alloc(W * H * 4);
  const set = (x, z, c, r = 0) => {
    const u = Math.round((x - X0) * E), v = Math.round((z - Z0) * E);
    for (let a = -r; a <= r; a++) for (let b = -r; b <= r; b++) {
      const uu = u + a, vv = v + b;
      if (uu < 0 || vv < 0 || uu >= W || vv >= H) continue;
      const i = (vv * W + uu) * 4; px[i] = c[0]; px[i + 1] = c[1]; px[i + 2] = c[2]; px[i + 3] = 255;
    }
  };
  const linha = (a, b, c, r = 1) => { const n = Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) * E * 2) + 1; for (let k = 0; k <= n; k++) set(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n, c, r); };
  const disco = (x, z, r, c) => { for (let a = -r; a <= r; a += 3) for (let b = -r; b <= r; b += 3) if (a * a + b * b <= r * r) set(x + a, z + b, c, 1); };
  for (let i = 0; i < W * H; i++) { px[i * 4] = 30; px[i * 4 + 1] = 45; px[i * 4 + 2] = 30; px[i * 4 + 3] = 255; }
  const v = mundo.vale;
  for (let x = v[0]; x <= v[2]; x += 4) for (let z = v[1]; z <= v[3]; z += 4) {
    const h = mundo.altura(x, z);
    const g = Math.min(255, 60 + h * 0.35);
    set(x, z, h > 6 ? [g, g * 0.75, g * 0.6] : [50, 85, 45]);
  }
  for (let x = -2500; x <= 2000; x += 500) linha([x, Z0], [x, Z1], [70, 90, 70], 0);
  for (let z = -2500; z <= 1500; z += 500) linha([X0, z], [X1, z], [70, 90, 70], 0);
  for (const l of mundo.lava || []) disco(l[0], l[1], l[2], [255, 90, 10]);
  const cores = [[255, 220, 40], [60, 200, 255], [255, 80, 200], [255, 120, 50]];
  percursos.forEach((p, k) => {
    const c = cores[k];
    for (const t of [p.A, p.B, p.C]) {
      let mm = 0;
      for (let i = 1; i < t.pts.length; i++) {
        const a = t.pts[i - 1], b = t.pts[i];
        mm += Math.hypot(b[0] - a[0], b[2] - a[2]);
        const tun = t.tuneis.some(q => mm >= q[0] && mm <= q[1]);
        linha([a[0], a[2]], [b[0], b[2]], tun ? c.map(v => v * 0.45) : c, 1);
      }
      for (const vv of t.vaos) disco(vv[0], vv[2], 10, [255, 255, 255]);
    }
    const rec = (o, h, comp, larg) => { const F = [Math.sin(h * Math.PI / 180), -Math.cos(h * Math.PI / 180)]; const L = [-F[1], F[0]]; for (let a = 0; a <= comp; a += 4) for (let b = -larg / 2; b <= larg / 2; b += 4) set(o[0] + F[0] * a + L[0] * b, o[2] + F[1] * a + L[1] * b, c.map(v => v * 0.5)); };
    rec(p.def.largada.o, p.def.largada.h, p.def.largada.comp, p.def.largada.larg);
    rec(p.def.plat.o, p.def.plat.h, p.def.plat.comp, p.def.plat.larg);
    const f = p.C.fim; linha([f.x, f.z], p.alvo, c.map(v => v * 0.8), 0);
    for (let a = 0; a < 360; a += 5) set(p.alvo[0] + Math.cos(a * Math.PI / 180) * 25, p.alvo[1] + Math.sin(a * Math.PI / 180) * 25, c, 2);
  });
  for (const e of extras.pontos || []) disco(e[0], e[1], e[2] || 12, e[3] || [255, 255, 255]);
  for (const e of extras.linhas || []) for (let i = 1; i < e.pts.length; i++) linha(e.pts[i - 1], e.pts[i], e.cor || [200, 200, 200], 0);
  fs.writeFileSync(arquivo, png(W, H, px));
};
