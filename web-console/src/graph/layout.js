/**
 * Flow layout for the evidence graph.
 *
 * Accounts are placed in columns by their flow level (money moves left to right: senders to the
 * root on the left, recipients on the right). Inside each column, accounts are ordered by the
 * barycentre of their neighbours so connected accounts sit near each other and lines cross less.
 */
export function layoutGraph(nodes, edges, {colGap = 230, rowGap = 78, padX = 120, padY = 80, minWidth = 960, minHeight = 560} = {}) {
  const byLevel = new Map();
  for (const n of nodes) {
    if (!byLevel.has(n.level)) byLevel.set(n.level, []);
    byLevel.get(n.level).push(n.id);
  }
  const levels = [...byLevel.keys()].sort((a, b) => a - b);
  const neighbours = new Map(nodes.map(n => [n.id, new Set()]));
  for (const e of edges) {
    neighbours.get(e.source)?.add(e.target);
    neighbours.get(e.target)?.add(e.source);
  }
  const rank = new Map();
  const index = () => levels.forEach(l => byLevel.get(l).forEach((id, i, col) => rank.set(id, (i + 0.5) / col.length)));
  levels.forEach(l => byLevel.get(l).sort());
  index();
  for (let sweep = 0; sweep < 8; sweep++) {
    for (const l of (sweep % 2 ? [...levels].reverse() : levels)) {
      const col = byLevel.get(l);
      const score = new Map(col.map(id => {
        const ns = [...neighbours.get(id)];
        return [id, ns.length ? ns.reduce((s, x) => s + rank.get(x), 0) / ns.length : rank.get(id)];
      }));
      col.sort((a, b) => score.get(a) - score.get(b) || a.localeCompare(b));
      col.forEach((id, i) => rank.set(id, (i + 0.5) / col.length));
    }
  }
  const tallest = Math.max(1, ...levels.map(l => byLevel.get(l).length));
  const width = Math.max(minWidth, padX * 2 + (levels.length - 1) * colGap);
  const height = Math.max(minHeight, padY * 2 + (tallest - 1) * rowGap);
  const x0 = (width - (levels.length - 1) * colGap) / 2;
  const pos = new Map();
  levels.forEach((l, ci) => {
    const col = byLevel.get(l);
    const span = (col.length - 1) * rowGap;
    col.forEach((id, i) => pos.set(id, {x: x0 + ci * colGap, y: height / 2 - span / 2 + i * rowGap}));
  });
  return {pos, width, height, columns: levels.map((level, ci) => ({level, x: x0 + ci * colGap, count: byLevel.get(level).length}))};
}

/** Point where the ray from p toward q leaves p's box (pill-shaped nodes), plus a small gap. */
function toward(p, q, box, gap) {
  const dx = q.x - p.x, dy = q.y - p.y, len = Math.hypot(dx, dy) || 1;
  const ux = dx / len, uy = dy / len;
  const tx = Math.abs(ux) > 1e-6 ? (box.w / 2) / Math.abs(ux) : Infinity;
  const ty = Math.abs(uy) > 1e-6 ? (box.h / 2) / Math.abs(uy) : Infinity;
  const r = Math.min(tx, ty) + gap;
  return {x: p.x + ux * r, y: p.y + uy * r};
}

/** Curved paths; parallel transfers between the same two accounts fan out instead of overlapping. */
export function edgeGeometry(edges, pos, boxOf) {
  const groups = new Map();
  for (const e of edges) {
    const k = [e.source, e.target].sort().join('\u0000');
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(e);
  }
  const out = new Map();
  for (const list of groups.values()) {
    list.forEach((e, i) => {
      const a = pos.get(e.source), b = pos.get(e.target);
      if (!a || !b) return;
      const canonical = e.source < e.target ? 1 : -1;
      const dx = b.x - a.x, dy = b.y - a.y, len = Math.hypot(dx, dy) || 1;
      let bend = (i - (list.length - 1) / 2) * 26 * canonical;
      if (Math.abs(dx) < 1) bend += 60;          // same column: arc out to the side
      else if (dx < 0) bend += 46;               // money flowing back upstream: arc above
      const nx = -dy / len, ny = dx / len;
      const c = {x: (a.x + b.x) / 2 + nx * bend, y: (a.y + b.y) / 2 + ny * bend};
      const s = toward(a, c, boxOf(e.source), 2);
      const t = toward(b, c, boxOf(e.target), 5);
      out.set(e.key, {d: `M${s.x},${s.y} Q${c.x},${c.y} ${t.x},${t.y}`, lx: (s.x + 2 * c.x + t.x) / 4, ly: (s.y + 2 * c.y + t.y) / 4});
    });
  }
  return out;
}

export function levelLabel(level) {
  if (level === 0) return 'Traced account';
  const n = Math.abs(level);
  return level < 0 ? `${n} hop${n > 1 ? 's' : ''} before` : `${n} hop${n > 1 ? 's' : ''} after`;
}
