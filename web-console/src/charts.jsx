import React, {useState} from 'react';
import {fmtDay, money, moneyCompact, RISK_LEVELS} from './lib.js';

/** Daily observed volume. Data-anchored: the last bar is the day of the latest record, not today. */
export function VolumeChart({series = [], height = 210, compact = false, mode = 'volume'}) {
  const val = d => mode === 'count' ? Number(d.count) : Number(d.volume);
  const label = v => mode === 'count' ? `${Math.round(v)}` : moneyCompact(v);
  const [hover, setHover] = useState(null);
  if (!series.length || series.every(d => !d.count)) {
    return <div className="chart-empty">No transfers in this period yet. Ingest a dataset or make a TraceBank transfer to see daily activity.</div>;
  }
  const W = 640, H = height, padL = compact ? 8 : 52, padR = 8, padT = 24, padB = 26;
  const max = Math.max(...series.map(val), 1);
  const ticks = [0, 0.5, 1].map(t => t * max);
  const bw = (W - padL - padR) / series.length;
  const y = v => padT + (H - padT - padB) * (1 - v / max);
  const labelEvery = Math.ceil(series.length / (compact ? 5 : 8));
  const h = hover != null ? series[hover] : null;
  return <div className="chart">
    <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`Daily volume for ${series.length} days`} onMouseLeave={() => setHover(null)}>
      {!compact && ticks.map((t, i) => <g key={i} className="chart-grid">
        <line x1={padL} x2={W - padR} y1={y(t)} y2={y(t)}/>
        <text x={padL - 8} y={y(t) + 3} textAnchor="end">{label(t)}</text>
      </g>)}
      {series.map((d, i) => {
        const v = val(d), x = padL + i * bw;
        return <g key={d.date} onMouseEnter={() => setHover(i)}>
          <rect x={x} y={padT} width={bw} height={H - padT - padB} fill="transparent"/>
          <rect x={x + bw * 0.18} y={y(v)} width={bw * 0.64} height={Math.max(0, H - padB - y(v))} rx={Math.min(5, bw * 0.2)}
                className={`chart-bar ${hover === i ? 'on' : ''}`}/>
          {i % labelEvery === labelEvery - 1 || i === series.length - 1
            ? <text x={x + bw / 2} y={H - 8} textAnchor="middle" className="chart-x">{fmtDay(d.date)}</text> : null}
        </g>;
      })}
      {h && (() => {
        const i = hover, x = Math.min(W - 96, Math.max(padL + 70, padL + i * bw + bw / 2));
        return <g className="chart-tip" transform={`translate(${x},${Math.max(30, y(val(h)) - 12)})`} pointerEvents="none">
          <rect x={-70} y={-34} width={140} height={32} rx={8}/>
          <text y={-21} textAnchor="middle" className="chart-tip-amt">{money(h.volume)}</text>
          <text y={-9} textAnchor="middle">{fmtDay(h.date)}, {h.count} transfer{h.count === 1 ? '' : 's'}</text>
        </g>;
      })()}
    </svg>
  </div>;
}

/** Latest rules-v1 level per recipient, as a single proportional bar. */
export function RiskMix({levels = {}}) {
  const total = RISK_LEVELS.reduce((s, [k]) => s + (levels[k] || 0), 0);
  if (!total) return <div className="chart-empty dark">No recipients assessed yet. Assessments appear after a payer or investigator checks a recipient.</div>;
  return <div className="riskmix">
    <div className="riskmix-bar" role="img" aria-label="Distribution of latest risk levels">
      {RISK_LEVELS.map(([k, , color]) => levels[k] ? <i key={k} style={{flexGrow: levels[k], background: color}} title={`${k}: ${levels[k]}`}/> : null)}
    </div>
    <ul>
      {RISK_LEVELS.map(([k, label, color]) => <li key={k}><i style={{background: color}}/>{label}<b>{levels[k] || 0}</b></li>)}
    </ul>
  </div>;
}

/** Horizontal share bars for evidence quality figures. */
export function ShareBars({rows}) {
  const total = rows.reduce((s, r) => s + r.value, 0) || 1;
  return <div className="sharebars">
    {rows.map(r => <div key={r.label} className="sharebar">
      <div className="sharebar-top"><span>{r.label}</span><b>{r.value.toLocaleString('en-IN')}</b></div>
      <div className="sharebar-track"><i style={{width: `${(r.value / total) * 100}%`, background: r.color}}/></div>
      {r.note && <small>{r.note}</small>}
    </div>)}
  </div>;
}
