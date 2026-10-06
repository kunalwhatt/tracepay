import React, {useEffect, useState} from 'react';
import {Activity, ArrowDownRight, Gauge, Lightbulb, ShieldCheck, Sparkles} from 'lucide-react';
import {api} from './lib.js';
import {openAssistant} from './assistant.jsx';

export const BAND_COLOR = {high_review: '#B3261E', review: '#E5482F', watch: '#E3A127', low: '#4C9A00', insufficient_information: '#9A92B8'};

/** Animate a number from 0 to its value. */
export function useCountUp(target, ms = 900) {
  const [v, setV] = useState(0);
  useEffect(() => {
    if (target == null) { setV(0); return; }
    let raf, start;
    const step = t => { start ??= t; const p = Math.min(1, (t - start) / ms); setV(Math.round(target * (1 - Math.pow(1 - p, 3)))); if (p < 1) raf = requestAnimationFrame(step); };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [target, ms]);
  return v;
}

export function ScoreGauge({score, band, label, size = 168}) {
  const shown = useCountUp(score ?? 0);
  const r = 62, c = Math.PI * r, frac = (score ?? 0) / 100;
  const color = BAND_COLOR[band] || '#5B2EFF';
  return <div className="ts-gauge" style={{width: size}}>
    <svg viewBox="0 0 160 96" role="img" aria-label={`TraceScore ${score ?? 'not available'} out of 100, ${label}`}>
      <path d="M18 84 A62 62 0 0 1 142 84" fill="none" stroke="#EEE8FF" strokeWidth="14" strokeLinecap="round"/>
      <path d="M18 84 A62 62 0 0 1 142 84" fill="none" stroke={color} strokeWidth="14" strokeLinecap="round"
            strokeDasharray={`${c * frac} ${c}`} className="ts-arc"/>
    </svg>
    <div className="ts-num"><b style={{color}}>{score == null ? '—' : shown}</b><span>/ 100</span></div>
    <div className="ts-band" style={{background: color}}>{label}</div>
  </div>;
}

export function TraceScorePanel({token, account}) {
  const [s, setS] = useState(null);
  const [err, setErr] = useState('');
  useEffect(() => { if (!account) return; setS(null); setErr(''); api(`/api/v1/tracescore/${encodeURIComponent(account)}`, {}, token).then(setS).catch(e => setErr(e.message)); }, [account, token]);
  if (err) return <div className="panel gx-error">{err}</div>;
  if (!s) return <div className="panel ts-panel"><div className="skel skel-gauge"/><div className="skel-lines"><i/><i/><i/><i/></div></div>;
  const max = Math.max(1, ...s.contributions.map(c => Math.abs(c.points)));
  return <div className="panel ts-panel fade-up">
    <div className="ts-left">
      <div className="ts-title"><Gauge size={16}/> TraceScore</div>
      <ScoreGauge score={s.score} band={s.band} label={s.band_label}/>
      <div className="ts-conf"><span>Confidence</span><div className="ts-conf-bar"><i style={{width: `${Math.round(s.confidence * 100)}%`}}/></div><b>{Math.round(s.confidence * 100)}%</b></div>
      {s.label && <div className={`ts-label ${s.label.label}`}><ShieldCheck size={14}/> {s.label.label.replace('_', ' ')}</div>}
      {s.complaints > 0 && <div className="ts-label confirmed_fraud">{s.complaints} complaint(s)</div>}
      <small className="muted">{s.version} · {s.engine}</small>
    </div>
    <div className="ts-right">
      <div className="panel-head"><h3>Why this score</h3><button className="text-link" onClick={() => openAssistant(null, {account, question: `Explain the TraceScore of ${account} signal by signal.`})}><Sparkles size={14}/> Explain</button></div>
      {!s.contributions.length && <p className="gx-fine">No TraceSense signal fired for this account.</p>}
      <div className="ts-bars">{s.contributions.map((c, i) => <div className={`ts-bar ${c.points < 0 ? 'neg' : ''}`} key={c.code} style={{animationDelay: `${i * 60}ms`}}>
        <div className="ts-bar-top"><span><i className={`fam ${c.family}`}>{c.family === 'core' ? 'Core' : 'Deep'}</i>{c.label}</span><b>{c.points > 0 ? '+' : ''}{c.points}</b></div>
        <div className="ts-track"><i style={{width: `${Math.abs(c.points) / max * 100}%`}}/></div>
        <small>{c.detail}</small>
      </div>)}</div>
      {s.counterfactuals?.length > 0 && <div className="ts-cf"><h4><Lightbulb size={14}/> What would change it</h4>{s.counterfactuals.map((t, i) => <p key={i}><ArrowDownRight size={13}/>{t}</p>)}</div>}
      {s.signals?.dwell && <div className="ts-chips">
        <span><Activity size={13}/> Pass-through 30 min <b>{Math.round((s.signals.dwell.pass_through_30m || 0) * 100)}%</b></span>
        <span>Median stay <b>{s.signals.dwell.median_dwell_minutes ?? '—'} min</b></span>
        <span>First-time payers <b>{Math.round((s.signals.victim_convergence?.first_time_share || 0) * 100)}%</b></span>
        <span>Max burst <b>{s.signals.motifs?.max_burst_30m || 0}/30 min</b></span>
        {s.signals.network?.ring?.size >= 3 && <span>Ring of <b>{s.signals.network.ring.size}</b></span>}
        {s.signals.network?.anomaly && <span>Anomaly <b>{s.signals.network.anomaly.score}</b></span>}
      </div>}
    </div>
  </div>;
}
