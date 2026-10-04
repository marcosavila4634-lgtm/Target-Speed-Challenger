const fs = require('fs');
const png = require('./png.js');
module.exports = function (arquivo, mundo, percursos) {
  const X0 = -2500, X1 = 1500, Z0 = -2100, Z1 = 1300, E = 0.3;
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
  for (let i = 0; i < W * H; i++) { px[i * 4] = 40; px[i * 4 + 1] = 50; px[i * 4 + 2] = 70; px[i * 4 + 3] = 255; }
  const v = mundo.vale;
  for (let x = v[0]; x <= v[2]; x += 3) for (let z = v[1]; z <= v[3]; z += 3) set(x, z, [90, 105, 125]);
  for (let x = -2000; x <= 1000; x += 500) linha([x, Z0], [x, Z1], [110, 125, 145], 0);
  for (let z = -2000; z <= 1000; z += 500) linha([X0, z], [X1, z], [110, 125, 145], 0);
  linha([0, Z0], [0, Z1], [160, 170, 190], 0); linha([X0, 0], [X1, 0], [160, 170, 190], 0);
  for (const l of mundo.lagos || []) disco(l[0], l[1], l[2], [70, 130, 190]);
  for (const m of mundo.mesas || []) disco(m[0], m[1], m[2], [170, 180, 200]);
  for (const c of mundo.capsulas || []) { const n = 40; for (let k = 0; k <= n; k++) { const t = k / n; disco(c.a[0] + (c.b[0] - c.a[0]) * t, c.a[1] + (c.b[1] - c.a[1]) * t, c.r, c.cor || [140, 150, 170]); } }
  const cores = [[255, 220, 40], [255, 90, 60], [60, 255, 120], [230, 80, 255]];
  percursos.forEach((p, k) => {
    const c = cores[k];
    for (const t of [p.A, p.B, p.C]) {
      for (let i = 1; i < t.pts.length; i++) linha([t.pts[i - 1][0], t.pts[i - 1][2]], [t.pts[i][0], t.pts[i][2]], c, 1);
      for (const vv of t.vaos) disco(vv[0], vv[2], 12, [255, 255, 255]);
    }
    const rec = (o, h, comp, larg) => { const F = [Math.sin(h * Math.PI / 180), -Math.cos(h * Math.PI / 180)]; const L = [-F[1], F[0]]; for (let a = 0; a <= comp; a += 4) for (let b = -larg / 2; b <= larg / 2; b += 4) set(o[0] + F[0] * a + L[0] * b, o[2] + F[1] * a + L[1] * b, c.map(v => v * 0.5)); };
    rec(p.def.largada.o, p.def.largada.h, p.def.largada.comp, p.def.largada.larg);
    rec(p.def.plat.o, p.def.plat.h, p.def.plat.comp, p.def.plat.larg);
    const f = p.C.fim; linha([f.x, f.z], p.alvo, c.map(v => v * 0.7), 0);
    for (let a = 0; a < 360; a += 5) set(p.alvo[0] + Math.cos(a * Math.PI / 180) * 20, p.alvo[1] + Math.sin(a * Math.PI / 180) * 20, c, 2);
  });
  fs.writeFileSync(arquivo, png(W, H, px));
};
