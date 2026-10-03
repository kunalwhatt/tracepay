import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {AlertTriangle, ArrowRight, Crosshair, FileCheck2, Maximize2, Network, Pause, Play, Users, ZoomIn, ZoomOut} from 'lucide-react';
import {api, EVIDENCE, fmtDate, fmtTime, money, moneyCompact, shortId} from '../lib.js';
import {edgeGeometry, layoutGraph, levelLabel} from './layout.js';

const HOP_CHOICES = [1, 2, 3, 4];

export default function GraphExplorer({token, initialRoot = '', onOpenAccount}) {
  const [rootInput, setRootInput] = useState(initialRoot);
  const [hops, setHops] = useState(3);
  const [graph, setGraph] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [selected, setSelected] = useState(null);          // {type:'node'|'edge', id}
  const [hoverEdge, setHoverEdge] = useState(null);
  const [cutoff, setCutoff] = useState(null);               // index into time-sorted edges; null = all
  const [playing, setPlaying] = useState(false);

  const trace = useCallback(async (root = rootInput, depth = hops) => {
    const ref = String(root || '').trim();
    if (!ref) return;
    setBusy(true); setError('');
    try {
      const g = await api(`/api/v1/graph/paths/${encodeURIComponent(ref)}?max_hops=${depth}&limit=800`, {}, token);
      setGraph(g); setSelected(null); setCutoff(null); setPlaying(false); setRootInput(ref);
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }, [rootInput, hops, token]);

  useEffect(() => { if (initialRoot) { setRootInput(initialRoot); trace(initialRoot, hops); } }, [initialRoot]);

  const edges = graph?.edges || [];
  const nodes = graph?.nodes || [];
  const visibleCount = cutoff == null ? edges.length : cutoff + 1;
  const visibleEdges = useMemo(() => edges.slice(0, visibleCount), [edges, visibleCount]);
  const activeNodes = useMemo(() => {
    const s = new Set(graph ? [graph.root] : []);
    visibleEdges.forEach(e => { s.add(e.source); s.add(e.target); });
    return s;
  }, [visibleEdges, graph]);

  useEffect(() => {
    if (!playing) return;
    if ((cutoff ?? -1) >= edges.length - 1) { setPlaying(false); return; }
    const id = setTimeout(() => setCutoff(c => (c == null ? 0 : c + 1)), 650);
    return () => clearTimeout(id);
  }, [playing, cutoff, edges.length]);

  const startReplay = () => { if (!edges.length) return; if (cutoff == null || cutoff >= edges.length - 1) setCutoff(0); setPlaying(true); };

  return <section className="gx">
    <div className="section-title">
      <div><div className="eyebrow">TEMPORAL INTELLIGENCE</div><h2>Graph analysis</h2></div>
      <form className="gx-search" onSubmit={e => { e.preventDefault(); trace(); }}>
        <input value={rootInput} onChange={e => setRootInput(e.target.value)} placeholder="Account to trace, e.g. tp.a.collect@tracepay" aria-label="Account to trace"/>
        <div className="gx-hops" role="group" aria-label="Hop limit">
          {HOP_CHOICES.map(h => <button type="button" key={h} className={h === hops ? 'on' : ''} onClick={() => { setHops(h); if (graph) trace(rootInput, h); }}>{h} hop{h > 1 ? 's' : ''}</button>)}
        </div>
        <button className="btn" type="submit" disabled={busy || !rootInput.trim()}>{busy ? 'Tracing…' : 'Trace'}</button>
      </form>
    </div>
    {error && <div className="gx-error"><AlertTriangle size={16}/>{error}</div>}
    {!graph && !busy && <GraphEmpty/>}
    {graph && <>
      <div className="gx-layout">
        <div className="gx-stage">
          {nodes.length <= 1
            ? <div className="gx-stage-empty"><Network size={28}/><b>No transfers found for {graph.root}</b><span>Check the spelling, or ingest a dataset that contains this account. An empty result means no persisted record mentions it, not that it never transacted.</span></div>
            : <Canvas graph={graph} edges={edges} visibleCount={visibleCount} activeNodes={activeNodes}
                      selected={selected} setSelected={setSelected} hoverEdge={hoverEdge} setHoverEdge={setHoverEdge}/>}
          <Replay edges={edges} cutoff={cutoff} setCutoff={c => { setPlaying(false); setCutoff(c); }} playing={playing}
                  onPlay={startReplay} onPause={() => setPlaying(false)} visibleCount={visibleCount}/>
        </div>
        <SidePanel graph={graph} selected={selected} setSelected={setSelected}
                   onRetrace={id => trace(id, hops)} onOpenAccount={onOpenAccount}/>
      </div>
      <Timeline edges={edges} visibleCount={visibleCount} selected={selected} setSelected={setSelected}/>
    </>}
  </section>;
}

function GraphEmpty() {
  return <div className="gx-intro">
    <Network size={26}/>
    <div>
      <h3>Trace how money moved around one account</h3>
      <p>Enter a Trace.Pay ID or any account reference from an ingested dataset. Senders appear on the left, recipients on the right, and every line is one persisted record you can open.</p>
    </div>
  </div>;
}

function Canvas({graph, edges, visibleCount, activeNodes, selected, setSelected, hoverEdge, setHoverEdge}) {
  const svgRef = useRef(null);
  const [view, setView] = useState({k: 1, x: 0, y: 0});
  const [size, setSize] = useState({w: 960, h: 560});
  const drag = useRef(null);

  // Fit the layout to the real canvas size so labels render at their true pixel size.
  useEffect(() => {
    const svg = svgRef.current;
    if (!svg || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(([entry]) => {
      const {width, height} = entry.contentRect;
      if (width > 0 && height > 0) setSize(s => (Math.abs(s.w - width) > 4 || Math.abs(s.h - height) > 4 ? {w: width, h: height} : s));
    });
    ro.observe(svg);
    return () => ro.disconnect();
  }, []);
  const levelCount = useMemo(() => new Set(graph.nodes.map(n => n.level)).size, [graph]);
  const layout = useMemo(() => layoutGraph(graph.nodes, graph.edges, {
    minWidth: size.w, minHeight: size.h, padX: 90, padY: 70,
    colGap: Math.min(290, Math.max(222, (size.w - 200) / Math.max(1, levelCount - 1))), rowGap: 74,
  }), [graph, size, levelCount]);
  // Pill-shaped nodes sized to their label; the traced account is taller and lime.
  const boxOf = useCallback(id => ({w: Math.min(200, Math.max(92, shortId(id, 26).length * 6.5 + 28)), h: id === graph.root ? 40 : 34}), [graph.root]);
  const geometry = useMemo(() => edgeGeometry(graph.edges, layout.pos, boxOf), [graph, layout, boxOf]);
  const maxAmount = Math.max(1, ...edges.map(e => Number(e.amount)));

  useEffect(() => setView({k: 1, x: 0, y: 0}), [graph]);

  // Focus: when an account is selected, dim everything that does not touch it.
  const focus = useMemo(() => {
    if (!selected) return null;
    if (selected.type === 'node') {
      const keys = new Set(edges.filter(e => e.source === selected.id || e.target === selected.id).map(e => e.key));
      const ids = new Set([selected.id]);
      edges.forEach(e => { if (keys.has(e.key)) { ids.add(e.source); ids.add(e.target); } });
      return {keys, ids};
    }
    const e = edges.find(x => x.key === selected.id);
    return e ? {keys: new Set([e.key]), ids: new Set([e.source, e.target])} : null;
  }, [selected, edges]);

  const toViewBox = (clientX, clientY) => {
    const svg = svgRef.current;
    const pt = svg.createSVGPoint(); pt.x = clientX; pt.y = clientY;
    return pt.matrixTransform(svg.getScreenCTM().inverse());
  };
  useEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;
    const onWheel = ev => {
      ev.preventDefault();
      const p = toViewBox(ev.clientX, ev.clientY);
      setView(v => {
        const k = Math.min(4, Math.max(0.35, v.k * (ev.deltaY < 0 ? 1.12 : 1 / 1.12)));
        return {k, x: p.x - (p.x - v.x) * (k / v.k), y: p.y - (p.y - v.y) * (k / v.k)};
      });
    };
    svg.addEventListener('wheel', onWheel, {passive: false});
    return () => svg.removeEventListener('wheel', onWheel);
  }, []);
  const zoom = factor => setView(v => {
    const cx = layout.width / 2, cy = layout.height / 2, k = Math.min(4, Math.max(0.35, v.k * factor));
    return {k, x: cx - (cx - v.x) * (k / v.k), y: cy - (cy - v.y) * (k / v.k)};
  });
  const onPointerDown = ev => {
    if (ev.target.closest('[data-hit]')) return;
    drag.current = {x: ev.clientX, y: ev.clientY, view, moved: false};
    ev.currentTarget.setPointerCapture(ev.pointerId);
  };
  const onPointerMove = ev => {
    if (!drag.current) return;
    const rect = svgRef.current.getBoundingClientRect();
    const scale = Math.max(layout.width / rect.width, layout.height / rect.height);
    const dx = (ev.clientX - drag.current.x) * scale, dy = (ev.clientY - drag.current.y) * scale;
    if (Math.abs(dx) + Math.abs(dy) > 3) drag.current.moved = true;
    setView({...drag.current.view, x: drag.current.view.x + dx, y: drag.current.view.y + dy});
  };
  const onPointerUp = () => { if (drag.current && !drag.current.moved) setSelected(null); drag.current = null; };

  const hovered = hoverEdge && edges.find(e => e.key === hoverEdge);
  const hoveredGeo = hovered && geometry.get(hovered.key);

  return <div className="gx-canvas">
    <div className="gx-tools">
      <button onClick={() => zoom(1.2)} aria-label="Zoom in"><ZoomIn size={16}/></button>
      <button onClick={() => zoom(1 / 1.2)} aria-label="Zoom out"><ZoomOut size={16}/></button>
      <button onClick={() => setView({k: 1, x: 0, y: 0})} aria-label="Fit graph"><Maximize2 size={15}/></button>
    </div>
    <Legend graph={graph}/>
    <svg ref={svgRef} viewBox={`0 0 ${layout.width} ${layout.height}`} className="gx-svg" role="img"
         aria-label={`Transfer graph around ${graph.root}: ${graph.nodes.length} accounts, ${graph.edges.length} transfers`}
         onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerUp} onPointerLeave={() => { drag.current = null; }}>
      <defs>
        {Object.entries(EVIDENCE).map(([state, s]) => <marker key={state} id={`gx-arrow-${state}`} viewBox="0 0 10 10" refX="8.5" refY="5"
          markerWidth="9" markerHeight="9" markerUnits="userSpaceOnUse" orient="auto"><path d="M0,0.8 L10,5 L0,9.2 z" fill={s.color}/></marker>)}
        <pattern id="gx-dots" width="26" height="26" patternUnits="userSpaceOnUse"><circle cx="1" cy="1" r="1" fill="rgba(91,46,255,.10)"/></pattern>
      </defs>
      <rect width={layout.width} height={layout.height} fill="url(#gx-dots)"/>
      <g transform={`translate(${view.x},${view.y}) scale(${view.k})`}>
        {layout.columns.map(c => <g key={c.level} className={`gx-col ${c.level === 0 ? 'root' : ''}`}>
          <line x1={c.x} x2={c.x} y1={34} y2={layout.height - 44}/>
          <text x={c.x} y={layout.height - 20} textAnchor="middle">{levelLabel(c.level)}</text>
          <text x={c.x} y={layout.height - 6} textAnchor="middle" className="gx-col-count">{c.count} account{c.count === 1 ? '' : 's'}</text>
        </g>)}
        {edges.map((e, i) => {
          const geo = geometry.get(e.key); if (!geo) return null;
          const style = EVIDENCE[e.evidence_state] || EVIDENCE.observed;
          const visible = i < visibleCount;
          const dim = (focus && !focus.keys.has(e.key)) || !visible;
          const isSel = selected?.type === 'edge' && selected.id === e.key;
          return <g key={e.key} className={`gx-edge ${dim ? 'dim' : ''} ${visible ? '' : 'future'} ${isSel ? 'sel' : ''}`} data-hit
                    onClick={ev => { ev.stopPropagation(); setSelected({type: 'edge', id: e.key}); }}
                    onMouseEnter={() => setHoverEdge(e.key)} onMouseLeave={() => setHoverEdge(null)}>
            <path d={geo.d} className="gx-edge-hit"/>
            <path d={geo.d} stroke={style.color} strokeWidth={1.4 + 4 * Math.sqrt(Number(e.amount) / maxAmount)} strokeDasharray={style.dash || undefined}
                  markerEnd={`url(#gx-arrow-${e.evidence_state})`} fill="none" className="gx-edge-line"/>
          </g>;
        })}
        {graph.nodes.map(n => {
          const p = layout.pos.get(n.id); if (!p) return null;
          const box = boxOf(n.id);
          const dim = (focus && !focus.ids.has(n.id)) || !activeNodes.has(n.id);
          const isSel = selected?.type === 'node' && selected.id === n.id;
          return <g key={n.id} className={`gx-node ${n.is_root ? 'root' : ''} ${dim ? 'dim' : ''} ${isSel ? 'sel' : ''} ${n.at_traversal_boundary ? 'edge-of-scope' : ''}`}
                    transform={`translate(${p.x},${p.y})`} data-hit tabIndex={0} role="button" aria-label={`Account ${n.id}`}
                    onClick={ev => { ev.stopPropagation(); setSelected({type: 'node', id: n.id}); }}
                    onKeyDown={ev => { if (ev.key === 'Enter') setSelected({type: 'node', id: n.id}); }}>
            {n.at_traversal_boundary && <rect x={-box.w / 2 - 5} y={-box.h / 2 - 5} width={box.w + 10} height={box.h + 10} rx={(box.h + 10) / 2} className="gx-boundary-pill"/>}
            <rect x={-box.w / 2} y={-box.h / 2} width={box.w} height={box.h} rx={box.h / 2} className="gx-pill"/>
            <text y={4} textAnchor="middle" className="gx-pill-label">{shortId(n.id, 26)}</text>
            <text y={box.h / 2 + 14} textAnchor="middle" className="gx-pill-sub">{moneyCompact(Number(n.in_total) + Number(n.out_total))}</text>
          </g>;
        })}
        {hovered && hoveredGeo && <g className="gx-tip" transform={`translate(${hoveredGeo.lx},${hoveredGeo.ly})`} pointerEvents="none">
          <rect x={-74} y={-40} width={148} height={34} rx={9}/>
          <text y={-26} textAnchor="middle" className="gx-tip-amt">{money(hovered.amount)}</text>
          <text y={-13} textAnchor="middle">{fmtTime(hovered.timestamp)}</text>
        </g>}
      </g>
    </svg>
  </div>;
}

function Legend({graph}) {
  const counts = graph.summary?.evidence_states || {};
  return <div className="gx-legend">
    {Object.entries(EVIDENCE).map(([state, s]) => <span key={state} className={counts[state] ? '' : 'none'}>
      <svg width="26" height="8" aria-hidden="true"><line x1="1" y1="4" x2="25" y2="4" stroke={s.color} strokeWidth="2.4" strokeDasharray={s.dash || undefined}/></svg>
      {s.label}<b>{counts[state] || 0}</b>
    </span>)}
    <span><svg width="22" height="14" aria-hidden="true"><rect x="1" y="1" width="20" height="12" rx="6" fill="none" stroke="#E3A127" strokeWidth="1.4" strokeDasharray="3 3"/></svg>Hop limit reached, may connect further</span>
  </div>;
}

function Replay({edges, cutoff, setCutoff, playing, onPlay, onPause, visibleCount}) {
  if (!edges.length) return null;
  const current = edges[Math.max(0, visibleCount - 1)];
  return <div className="gx-replay">
    <button className="gx-play" onClick={playing ? onPause : onPlay} aria-label={playing ? 'Pause replay' : 'Replay transfers in time order'}>
      {playing ? <Pause size={15}/> : <Play size={15}/>}
    </button>
    <input type="range" min={0} max={edges.length - 1} value={cutoff == null ? edges.length - 1 : cutoff}
           onChange={e => setCutoff(Number(e.target.value))} aria-label="Show transfers up to this point in time"/>
    <div className="gx-replay-label">
      <b>{visibleCount} of {edges.length} transfers</b>
      <span>up to {fmtDate(current?.timestamp)}</span>
    </div>
    {cutoff != null && <button className="text-link" onClick={() => setCutoff(null)}>Show all</button>}
  </div>;
}

function Row({k, v, mono}) { return v == null || v === '' ? null : <div className="gx-row"><span>{k}</span><b className={mono ? 'mono' : ''}>{v}</b></div>; }

function SidePanel({graph, selected, setSelected, onRetrace, onOpenAccount}) {
  if (selected?.type === 'edge') {
    const e = graph.edges.find(x => x.key === selected.id);
    if (e) return <EdgePanel e={e} onClose={() => setSelected(null)} onPick={id => setSelected({type: 'node', id})}/>;
  }
  if (selected?.type === 'node') {
    const n = graph.nodes.find(x => x.id === selected.id);
    if (n) return <NodePanel n={n} graph={graph} onClose={() => setSelected(null)} onRetrace={onRetrace} onOpenAccount={onOpenAccount}/>;
  }
  const s = graph.summary || {};
  return <div className="gx-panel">
    <h3>Trace scope</h3>
    <p className="gx-lede">What this view covers. Select an account or a line for its evidence.</p>
    <Row k="Traced account" v={graph.root} mono/>
    <Row k="Hop limit" v={`${s.max_hops} hops in each direction`}/>
    <Row k="Accounts" v={s.node_count}/>
    <Row k="Transfers" v={s.edge_count}/>
    <Row k="Earliest" v={fmtDate(s.first_timestamp)}/>
    <Row k="Latest" v={fmtDate(s.last_timestamp)}/>
    {s.truncated && <div className="gx-warn"><AlertTriangle size={15}/>The record limit was reached. Some connections are not shown; narrow the hop limit for a complete view.</div>}
    <div className="gx-note"><FileCheck2 size={15}/><span>{graph.note}</span></div>
  </div>;
}

function NodePanel({n, graph, onClose, onRetrace, onOpenAccount}) {
  const diff = Number(n.observed_flow_difference);
  const counterparts = graph.edges.filter(e => e.source === n.id || e.target === n.id);
  return <div className="gx-panel">
    <div className="gx-panel-head"><span className="gx-kind"><Users size={14}/> Account</span><button className="text-link" onClick={onClose}>Back to scope</button></div>
    <h3 className="mono gx-id">{n.id}</h3>
    <p className="gx-lede">{levelLabel(n.level)}{n.hop ? `, ${n.hop} hop${n.hop > 1 ? 's' : ''} from the traced account` : ''}</p>
    <div className="gx-stats">
      <div><span>Received</span><b>{money(n.in_total)}</b><small>{n.in_count} transfer{n.in_count === 1 ? '' : 's'} from {n.unique_senders}</small></div>
      <div><span>Sent</span><b>{money(n.out_total)}</b><small>{n.out_count} transfer{n.out_count === 1 ? '' : 's'} to {n.unique_receivers}</small></div>
    </div>
    <Row k="Observed-flow difference" v={money(diff)}/>
    <p className="gx-fine">Received minus sent within this view. A difference is not missing money: the account may hold a balance, or use rails outside this dataset.</p>
    {n.failed_attempts > 0 && <Row k="Failed attempts" v={`${n.failed_attempts} (no value moved)`}/>}
    {n.at_traversal_boundary && <div className="gx-warn"><AlertTriangle size={15}/>This account sits at the hop limit. It may have further transfers not loaded here.</div>}
    <div className="gx-actions">
      {!n.is_root && <button className="btn" onClick={() => onRetrace(n.id)}><Crosshair size={15}/> Trace from this account</button>}
      {onOpenAccount && <button className="btn light" onClick={() => onOpenAccount(n.id)}>Open account analysis</button>}
    </div>
    <h4 className="gx-sub">Transfers in this view ({counterparts.length})</h4>
    <div className="gx-mini-list">
      {counterparts.slice(0, 12).map(e => <div key={e.key}>
        <i style={{background: EVIDENCE[e.evidence_state]?.color}}/>
        <span>{e.source === n.id ? <>to {shortId(e.target, 20)}</> : <>from {shortId(e.source, 20)}</>}</span>
        <b>{money(e.amount)}</b>
      </div>)}
    </div>
  </div>;
}

function EdgePanel({e, onClose, onPick}) {
  const style = EVIDENCE[e.evidence_state] || EVIDENCE.observed;
  const ledger = e.source_id === 'tracepay_internal_ledger';
  return <div className="gx-panel">
    <div className="gx-panel-head"><span className="gx-kind" style={{color: style.color}}><i className="gx-swatch" style={{background: style.color}}/>{style.label}</span><button className="text-link" onClick={onClose}>Back to scope</button></div>
    <div className="gx-amount">{money(e.amount)}</div>
    <div className="gx-flow">
      <button onClick={() => onPick(e.source)} className="mono">{shortId(e.source, 26)}</button>
      <ArrowRight size={15}/>
      <button onClick={() => onPick(e.target)} className="mono">{shortId(e.target, 26)}</button>
    </div>
    <Row k="When" v={fmtDate(e.timestamp)}/>
    <Row k="Reference" v={e.transaction_ref} mono/>
    <h4 className="gx-sub">Why this line exists</h4>
    <p className="gx-fine">{ledger
      ? (e.flow_confirmed ? 'Trace.Pay committed both sides of this internal ledger transfer. It is not an external bank or UPI settlement.' : 'This internal transfer was attempted and failed. No ledger value moved; it is shown only as an attempt.')
      : 'An authorised source dataset contains this record. The line shows what the record says, not a judgement about it.'}</p>
    <Row k="Source" v={e.source_id} mono/>
    <Row k="Source record" v={e.source_record_ref} mono/>
    <Row k="File" v={e.source_file}/>
    <Row k="Sheet / row" v={e.source_sheet ? `${e.source_sheet}, row ${e.source_row}` : null}/>
    <Row k="Ingestion job" v={e.ingestion_job_id ? `JOB-${String(e.ingestion_job_id).padStart(4, '0')}` : null}/>
    <Row k="Event ID" v={e.event_id} mono/>
    <Row k="Provenance" v={e.provenance_status}/>
    <Row k="Failure reason" v={e.failure_reason}/>
    {e.provenance_status === 'normalized' && <p className="gx-fine">Normalised means a value was interpreted during import, for example an ambiguous day/month date read as DD/MM. Check the source row if the exact time matters.</p>}
  </div>;
}

function Timeline({edges, visibleCount, selected, setSelected}) {
  if (!edges.length) return null;
  return <div className="panel gx-timeline">
    <div className="panel-head"><h3>Transfers in time order</h3><span className="gx-count">{edges.length}</span></div>
    <div className="gx-tl-head"><span>Time</span><span>From</span><span>To</span><span>Amount</span><span>Evidence</span><span>Reference</span></div>
    <div className="gx-tl-body">
      {edges.slice(0, 400).map((e, i) => {
        const s = EVIDENCE[e.evidence_state] || EVIDENCE.observed;
        return <button key={e.key} className={`gx-tl-row ${i >= visibleCount ? 'future' : ''} ${selected?.id === e.key ? 'sel' : ''}`}
                       onClick={() => setSelected({type: 'edge', id: e.key})}>
          <span>{fmtTime(e.timestamp)}</span>
          <span className="mono">{shortId(e.source, 26)}</span>
          <span className="mono">{shortId(e.target, 26)}</span>
          <b>{money(e.amount)}</b>
          <span className="gx-tl-state"><i style={{background: s.color}}/>{s.short}</span>
          <span className="mono muted">{shortId(e.transaction_ref, 18)}</span>
        </button>;
      })}
    </div>
  </div>;
}
