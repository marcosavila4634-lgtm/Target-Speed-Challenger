// Desenrola a cobra escaneada (assets/MAPA SERPENTE/COBRAS/COBRAGIGANTE, enrolada e sem esqueleto)
// numa cobra RETA para o jogo dar ossos e fazê-la rastejar (scripts/mundo/serpente_gigante.gd).
// Uso: node tools/serpents_climb/endireitar_cobra.js <entrada.glb> <saida.glb> [glb com a textura de cor]
// Saída: cabeça em z = 0 olhando para -Z, corpo para +Z, barriga em y = 0, unidades do escaneamento.
// Como: distância geodésica na malha a partir de uma ponta = posição ao longo do corpo; a média dos
// vértices de cada fatia dá a linha do meio; cada vértice vira (lado, cima, ao longo) em volta dela.
const fs = require('fs');
const [entrada, saida, cor] = process.argv.slice(2);

function abrir(arq) {
  if (arq.endsWith('.gltf')) {   // .gltf com .bin e texturas soltas (pasta do Sketchfab)
    const jj = JSON.parse(fs.readFileSync(arq, 'utf8'));
    const pasta = require('path').dirname(arq);
    return { j: jj, bin: fs.readFileSync(pasta + '/' + jj.buffers[0].uri), pasta };
  }
  const b = fs.readFileSync(arq);
  const len = b.readUInt32LE(12);
  return { j: JSON.parse(b.slice(20, 20 + len).toString()), bin: b.slice(20 + len + 8) };
}
const ENT = abrir(entrada);
const { j, bin } = ENT;
function acc(i) {
  const a = j.accessors[i], bv = j.bufferViews[a.bufferView];
  const n = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 }[a.type];
  const sz = { 5126: 4, 5125: 4, 5123: 2, 5121: 1 }[a.componentType];
  const off = (bv.byteOffset || 0) + (a.byteOffset || 0), passo = bv.byteStride || sz * n;
  const out = a.componentType === 5126 ? new Float32Array(a.count * n) : new Uint32Array(a.count * n);
  for (let k = 0; k < a.count; k++) for (let c = 0; c < n; c++) {
    const o = off + k * passo + c * sz;
    out[k * n + c] = a.componentType === 5126 ? bin.readFloatLE(o) : a.componentType === 5125 ? bin.readUInt32LE(o) : a.componentType === 5123 ? bin.readUInt16LE(o) : bin[o];
  }
  return out;
}
function imagem(g, i) {
  const im0 = g.j.images[i];
  if (im0.uri) return { mime: im0.uri.endsWith('.png') ? 'image/png' : 'image/jpeg', dados: fs.readFileSync(g.pasta + '/' + im0.uri) };
  const im = g.j.images[i], bv = g.j.bufferViews[im.bufferView];
  return { mime: im.mimeType, dados: g.bin.slice(bv.byteOffset || 0, (bv.byteOffset || 0) + bv.byteLength) };
}

// Corpo: o Sketchfab parte a malha em pedaços de 65 mil vértices (malhas com o material 0)
const P = [], N = [], UV = [], I = [];
const olhos = { P: [], N: [], I: [] };
j.meshes.forEach((m) => m.primitives.forEach((p) => {
  const nome = j.materials[p.material].name;
  const pos = acc(p.attributes.POSITION), nor = acc(p.attributes.NORMAL), idx = acc(p.indices);
  if (p.material === 0) {
    const uv = acc(p.attributes.TEXCOORD_0), base = P.length / 3;
    for (const v of pos) P.push(v);
    for (const v of nor) N.push(v);
    for (const v of uv) UV.push(v);
    for (const v of idx) I.push(v + base);
  } else if (nome === 'material') {   // esfera de fora do olho (as de dentro ficam escondidas por ela)
    const base = olhos.P.length / 3;
    for (const v of pos) olhos.P.push(v);
    for (const v of nor) olhos.N.push(v);
    for (const v of idx) olhos.I.push(v + base);
  }
}));
const nv = P.length / 3;

// Solda (vértices repetidos nas costuras da textura e entre os pedaços) e vizinhança
const mapa = new Map(), sold = new Int32Array(nv);
let ns = 0;
for (let i = 0; i < nv; i++) {
  const k = Math.round(P[i * 3] * 1e5) + ',' + Math.round(P[i * 3 + 1] * 1e5) + ',' + Math.round(P[i * 3 + 2] * 1e5);
  let v = mapa.get(k);
  if (v === undefined) { v = ns++; mapa.set(k, v); }
  sold[i] = v;
}
const rep = new Int32Array(ns).fill(-1);
for (let i = 0; i < nv; i++) if (rep[sold[i]] < 0) rep[sold[i]] = i;
const viz = Array.from({ length: ns }, () => []);
const dist3 = (a, b) => Math.hypot(P[a * 3] - P[b * 3], P[a * 3 + 1] - P[b * 3 + 1], P[a * 3 + 2] - P[b * 3 + 2]);
for (let t = 0; t < I.length; t += 3) for (let e = 0; e < 3; e++) {
  const a = sold[I[t + e]], b = sold[I[t + (e + 1) % 3]];
  if (a === b) continue;
  const d = dist3(rep[a], rep[b]);
  viz[a].push(b, d); viz[b].push(a, d);
}
function dijkstra(origem) {
  const d = new Float64Array(ns).fill(Infinity);
  const heap = [[0, origem]];
  d[origem] = 0;
  while (heap.length) {
    const topo = heap[0], ult = heap.pop();
    if (heap.length) {
      heap[0] = ult;
      let i = 0;
      for (;;) {
        let m = i; const l = 2 * i + 1, r = l + 1;
        if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
        if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
        if (m === i) break;
        [heap[i], heap[m]] = [heap[m], heap[i]]; i = m;
      }
    }
    const [du, u] = topo;
    if (du > d[u]) continue;
    const vz = viz[u];
    for (let k = 0; k < vz.length; k += 2) {
      const nd = du + vz[k + 1];
      if (nd < d[vz[k]]) {
        d[vz[k]] = nd;
        let i = heap.push([nd, vz[k]]) - 1;
        while (i > 0) { const p = (i - 1) >> 1; if (heap[p][0] <= heap[i][0]) break; [heap[i], heap[p]] = [heap[p], heap[i]]; i = p; }
      }
    }
  }
  return d;
}
const longe = (d) => { let m = 0; for (let i = 1; i < ns; i++) if (d[i] > d[m] && d[i] < Infinity) m = i; return m; };
let ponta = longe(dijkstra(0));
let geo = dijkstra(ponta);
// A cabeça é a ponta perto dos olhos: a geodésica passa a contar a partir dela
const co = [0, 0, 0];
for (let i = 0; i < olhos.P.length; i += 3) for (let c = 0; c < 3; c++) co[c] += olhos.P[i + c] / (olhos.P.length / 3);
const outra = longe(geo);
if (olhos.P.length) {
  const ate = (v) => Math.hypot(P[rep[v] * 3] - co[0], P[rep[v] * 3 + 1] - co[1], P[rep[v] * 3 + 2] - co[2]);
  if (ate(outra) < ate(ponta)) { ponta = outra; geo = dijkstra(ponta); }
} else {
  // Sem olho separado: a cabeça é a ponta mais grossa (espalhamento dos vértices nos 4% de cada ponta)
  const tot = geo[outra];
  const grossura = (perto) => {
    const c = [0, 0, 0], vs = [];
    for (let v = 0; v < ns; v++) if (perto(geo[v] / tot)) vs.push(rep[v]);
    for (const r of vs) for (let k = 0; k < 3; k++) c[k] += P[r * 3 + k] / vs.length;
    let d = 0;
    for (const r of vs) d += Math.hypot(P[r * 3] - c[0], P[r * 3 + 1] - c[1], P[r * 3 + 2] - c[2]) / vs.length;
    return d;
  };
  const g0 = grossura((t) => t < 0.04), g1 = grossura((t) => t > 0.96);
  console.log('grossura das pontas', g0.toFixed(4), g1.toFixed(4));
  if (g1 > g0) { ponta = outra; geo = dijkstra(ponta); }
}
const total = geo[longe(geo)];

// Linha do meio: média dos vértices por fatia de geodésica, alisada
const FATIA = 0.004;
const nf = Math.ceil(total / FATIA) + 1;
let C = Array.from({ length: nf }, () => [0, 0, 0, 0]);
for (let v = 0; v < ns; v++) {
  const k = Math.min(Math.floor(geo[v] / FATIA), nf - 1), r = rep[v];
  C[k][0] += P[r * 3]; C[k][1] += P[r * 3 + 1]; C[k][2] += P[r * 3 + 2]; C[k][3]++;
}
C = C.filter((c) => c[3] > 0).map((c) => [c[0] / c[3], c[1] / c[3], c[2] / c[3]]);
for (let passada = 0; passada < 6; passada++) {
  const D = C.map((c) => c.slice());
  for (let k = 1; k < C.length - 1; k++) for (let c = 0; c < 3; c++) D[k][c] = (C[k - 1][c] + 2 * C[k][c] + C[k + 1][c]) / 4;
  C = D;
}
const nc = C.length;
const S = new Float64Array(nc);
for (let k = 1; k < nc; k++) S[k] = S[k - 1] + Math.hypot(C[k][0] - C[k - 1][0], C[k][1] - C[k - 1][1], C[k][2] - C[k - 1][2]);
const norm = (v) => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
const cruz = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const esc = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
// Base em cada ponto da linha: T (cabeça → cauda), U (para cima, o corpo está deitado no chão), L = U x T
const BASE = C.map((c, k) => {
  const a = C[Math.max(k - 1, 0)], b = C[Math.min(k + 1, nc - 1)];
  const T = norm([b[0] - a[0], b[1] - a[1], b[2] - a[2]]);
  const U = norm([-T[1] * T[0], 1 - T[1] * T[1], -T[1] * T[2]]);
  return { T, U, L: cruz(U, T) };
});
// Ponto → [lado, cima, ao longo] em volta da linha do meio, e a base usada (para girar a normal)
function reto(p, k0) {
  let melhor = null;
  for (let k = Math.max(k0 - 5, 0); k < Math.min(k0 + 5, nc - 1); k++) {
    const a = C[k], b = C[k + 1];
    const ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], ap = [p[0] - a[0], p[1] - a[1], p[2] - a[2]];
    let t = esc(ap, ab) / esc(ab, ab);
    if (!(k === 0 && t < 0) && !(k === nc - 2 && t > 1)) t = Math.min(Math.max(t, 0), 1);   // as pontas passam do fim da linha
    const q = [a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t];
    const d = Math.hypot(p[0] - q[0], p[1] - q[1], p[2] - q[2]);
    if (!melhor || d < melhor.d) melhor = { d, k, t, q };
  }
  const { k, t, q } = melhor, tt = Math.min(Math.max(t, 0), 1);
  const mix = (n) => norm([0, 1, 2].map((c) => BASE[k][n][c] * (1 - tt) + BASE[k + 1][n][c] * tt));
  const T = mix('T'), u = mix('U'), e = esc(u, T);
  const U = norm([u[0] - e * T[0], u[1] - e * T[1], u[2] - e * T[2]]), L = cruz(U, T);
  const d = [p[0] - q[0], p[1] - q[1], p[2] - q[2]];
  return { xyz: [esc(d, L), esc(d, U), S[k] + (S[k + 1] - S[k]) * t], T, U, L };
}
const fatia_de = (g) => Math.min(Math.round(g / total * (nc - 1)), nc - 1);
const RP = new Float32Array(nv * 3), RN = new Float32Array(nv * 3);
for (let i = 0; i < nv; i++) {
  const r = reto([P[i * 3], P[i * 3 + 1], P[i * 3 + 2]], fatia_de(geo[sold[i]]));
  RP.set(r.xyz, i * 3);
  const n = [N[i * 3], N[i * 3 + 1], N[i * 3 + 2]];
  RN.set(norm([esc(n, r.L), esc(n, r.U), esc(n, r.T)]), i * 3);
}
const OP = new Float32Array(olhos.P.length), ON = new Float32Array(olhos.P.length);
for (let i = 0; i < olhos.P.length; i += 3) {
  const p = [olhos.P[i], olhos.P[i + 1], olhos.P[i + 2]];
  let k0 = 0, dm = Infinity;
  for (let k = 0; k < Math.min(40, nc); k++) { const d = Math.hypot(p[0] - C[k][0], p[1] - C[k][1], p[2] - C[k][2]); if (d < dm) { dm = d; k0 = k; } }
  const r = reto(p, k0);
  OP.set(r.xyz, i);
  const n = [olhos.N[i], olhos.N[i + 1], olhos.N[i + 2]];
  ON.set(norm([esc(n, r.L), esc(n, r.U), esc(n, r.T)]), i);
}
// Focinho em z = 0 e barriga em y = 0 ao longo de todo o corpo (perfil do ponto mais baixo, alisado)
let z0 = Infinity, z1 = -Infinity;
for (let i = 0; i < nv; i++) { z0 = Math.min(z0, RP[i * 3 + 2]); z1 = Math.max(z1, RP[i * 3 + 2]); }
const comp = z1 - z0, NP = 400;
let baixo = new Float64Array(NP).fill(Infinity);
const larg = new Float64Array(NP);
for (let i = 0; i < nv; i++) {
  const k = Math.min(Math.floor((RP[i * 3 + 2] - z0) / comp * NP), NP - 1);
  baixo[k] = Math.min(baixo[k], RP[i * 3 + 1]);
  larg[k] = Math.max(larg[k], Math.abs(RP[i * 3]));
}
for (let k = 1; k < NP; k++) if (baixo[k] === Infinity) baixo[k] = baixo[k - 1];
const raio = Math.max(...larg);
const borda = Math.ceil(raio * 2.5 / (comp / NP));   // focinho e ponta da cauda: não achatar o arredondado
for (let k = 0; k < borda; k++) { baixo[k] = baixo[borda]; baixo[NP - 1 - k] = baixo[NP - 1 - borda]; }
for (let passada = 0; passada < 12; passada++) {
  const b = baixo.slice();
  for (let k = 1; k < NP - 1; k++) b[k] = (baixo[k - 1] + 2 * baixo[k] + baixo[k + 1]) / 4;
  baixo = b;
}
const chao = (z) => { const f = Math.min(Math.max((z - z0) / comp * NP - 0.5, 0), NP - 1.001), k = Math.floor(f); return baixo[k] + (baixo[k + 1] - baixo[k]) * (f - k); };
for (const A of [RP, OP]) for (let i = 0; i < A.length; i += 3) { A[i + 1] -= chao(A[i + 2]); A[i + 2] -= z0; }

// ---- grava o .glb
const partes = [];
let tam = 0;
const views = [], accs = [];
function junta(buf, alvo) {
  const pad = (4 - buf.length % 4) % 4;
  views.push(Object.assign({ buffer: 0, byteOffset: tam, byteLength: buf.length }, alvo ? { target: alvo } : {}));
  partes.push(buf, Buffer.alloc(pad));
  tam += buf.length + pad;
  return views.length - 1;
}
function attr(arr, tipo, n) {
  const f = arr instanceof Float32Array;
  const a = { bufferView: junta(Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength), f ? 34962 : 34963), componentType: f ? 5126 : 5125, count: arr.length / n, type: tipo };
  if (tipo === 'VEC3') {
    a.min = [Infinity, Infinity, Infinity]; a.max = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < arr.length; i++) { a.min[i % 3] = Math.min(a.min[i % 3], arr[i]); a.max[i % 3] = Math.max(a.max[i % 3], arr[i]); }
  }
  accs.push(a);
  return accs.length - 1;
}
const prims = [
  { attributes: { POSITION: attr(RP, 'VEC3', 3), NORMAL: attr(RN, 'VEC3', 3), TEXCOORD_0: attr(new Float32Array(UV), 'VEC2', 2) }, indices: attr(new Uint32Array(I), 'SCALAR', 1), material: 0 },
];
if (olhos.P.length) prims.push({ attributes: { POSITION: attr(OP, 'VEC3', 3), NORMAL: attr(ON, 'VEC3', 3) }, indices: attr(new Uint32Array(olhos.I), 'SCALAR', 1), material: 1 });
const g0 = ENT, gc = cor ? abrir(cor) : g0;
const im_cor = imagem(gc, gc.j.textures[gc.j.materials[0].pbrMetallicRoughness.baseColorTexture.index].source);
const im_rel = imagem(g0, j.textures[j.materials[0].normalTexture.index].source);
const images = [im_cor, im_rel].map((im) => ({ mimeType: im.mime, bufferView: junta(im.dados) }));
const doc = {
  asset: { version: '2.0', generator: 'tools/serpents_climb/endireitar_cobra.js', extras: j.asset.extras },
  scene: 0, scenes: [{ nodes: [0] }], nodes: [{ name: 'CobraGigante', mesh: 0 }],
  meshes: [{ name: 'cobra_reta', primitives: prims }],
  materials: [
    { name: 'pele', pbrMetallicRoughness: { baseColorTexture: { index: 0 }, metallicFactor: 0, roughnessFactor: 0.3 }, normalTexture: { index: 1 } },
    { name: 'olho', pbrMetallicRoughness: { baseColorFactor: [0.01, 0.01, 0.01, 1], metallicFactor: 0, roughnessFactor: 0.05 } },
  ],
  textures: [{ sampler: 0, source: 0 }, { sampler: 0, source: 1 }], samplers: [{ magFilter: 9729, minFilter: 9987, wrapS: 10497, wrapT: 10497 }],
  images, accessors: accs, bufferViews: views, buffers: [{ byteLength: tam }],
};
let js = Buffer.from(JSON.stringify(doc));
js = Buffer.concat([js, Buffer.alloc((4 - js.length % 4) % 4, 0x20)]);
const cab = Buffer.alloc(12), cj = Buffer.alloc(8), cb = Buffer.alloc(8);
cab.writeUInt32LE(0x46546c67, 0); cab.writeUInt32LE(2, 4); cab.writeUInt32LE(12 + 8 + js.length + 8 + tam, 8);
cj.writeUInt32LE(js.length, 0); cj.writeUInt32LE(0x4e4f534a, 4);
cb.writeUInt32LE(tam, 0); cb.writeUInt32LE(0x004e4942, 4);
fs.writeFileSync(saida, Buffer.concat([cab, cj, js, cb, ...partes]));
console.log('vértices', nv, 'soldados', ns, 'comprimento', comp.toFixed(3), 'meia-largura máx.', raio.toFixed(4), 'proporção', (comp / raio / 2).toFixed(1));
console.log('meia-largura ao longo (cabeça → cauda):', Array.from({ length: 20 }, (_, k) => larg[Math.floor(k * NP / 20)].toFixed(4)).join(' '));
