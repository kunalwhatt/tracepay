import React, {useState} from 'react';
import {Beaker, FlaskConical, Play, Timer} from 'lucide-react';
import {api} from './lib.js';

const COLORS = {'TraceSense Core (caution or above)': '#9A92B8', 'TraceScore (watch or above)': '#5B2EFF', 'TraceSense Core (review)': '#C9BBFF',
  'TraceScore (review or above)': '#2A1A5E', 'Anomaly only': '#E3A127', trace_recall: '#4C9A00'};
const STEPS = ['Generating a synthetic fraud world', 'Scoring every account', 'Varying mule delays', 'Dropping records on purpose', 'Measuring'];

function Lines({rows, xKey, xLabel, keys, pct = true}) {
  const W = 640, H = 220, pl = 40, pb = 30, pt = 14;
  const xs = rows.map(r => r[xKey]);
  const x = i => pl + (W - pl - 16) * (i / Math.max(1, rows.length - 1));
  const y = v => pt + (H - pt - pb) * (1 - v);
  return <div className="chart"><svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={xLabel}>
    {[0, 0.5, 1].map(t => <g key={t} className="chart-grid"><line x1={pl} x2={W - 10} y1={y(t)} y2={y(t)}/><text x={pl - 6} y={y(t) + 3} textAnchor="end">{pct ? `${t * 100}%` : t}</text></g>)}
    {xs.map((v, i) => <text key={i} x={x(i)} y={H - 10} textAnchor="middle" className="chart-x">{pct && v < 1 && xKey === 'records_dropped' ? `${Math.round(v * 100)}%` : v}</text>)}
    {keys.map(k => <g key={k}><polyline className="tb-line" fill="none" stroke={COLORS[k]} strokeWidth="3" points={rows.map((r, i) => `${x(i)},${y(r[k] ?? 0)}`).join(' ')}/>
      {rows.map((r, i) => <circle key={i} cx={x(i)} cy={y(r[k] ?? 0)} r="4" fill={COLORS[k]}/>)}</g>)}
  </svg><div className="gb-legend">{keys.map(k => <span key={k}><i style={{background: COLORS[k]}}/>{k.replace('_', ' ')}</span>)}</div>
    <small className="muted">{xLabel}</small></div>;
}

export default function TraceBenchPage({token, setError}) {
  const [res, setRes] = useState(null);
  const [busy, setBusy] = useState(false);
  const [step, setStep] = useState(0);
  const [seed, setSeed] = useState(42);
  async function run() {
    setBusy(true); setRes(null); setStep(0);
    const timer = setInterval(() => setStep(s => Math.min(STEPS.length - 1, s + 1)), 450);
    try { setRes(await api('/api/v1/tracebench/run', {method: 'POST', body: JSON.stringify({seed: Number(seed), quick: false})}, token)); }
    catch (e) { setError(e.message); } finally { clearInterval(timer); setBusy(false); }
  }
  const det = res?.evaluation?.detectors || {};
  const main = ['TraceSense Core (caution or above)', 'TraceScore (watch or above)'];
  return <section className="tbn">
    <div className="section-title"><div><div className="eyebrow">EVALUATION LAB</div></div>
      <div className="tb-run"><label>World seed <input type="number" value={seed} onChange={e => setSeed(e.target.value)}/></label>
        <button className="btn" disabled={busy} onClick={run}><Play size={15}/> {busy ? 'Running…' : res ? 'Run again' : 'Run TraceBench'}</button></div></div>
    {!res && !busy && <div className="panel tb-intro fade-up"><FlaskConical size={28}/><div><h3>Measure Trace.Pay on a world where the truth is known</h3>
      <p>TraceBench builds ordinary users, busy shops and mule rings (victims → collector → layers → cash-out, including task-scam escalation). Every account has a true role, so each detector gets precision, recall, false positives and time-to-flag. It then makes mules wait longer and deletes records on purpose to show where detection breaks.</p></div></div>}
    {busy && <div className="panel tb-loading fade-up"><Beaker size={26} className="spin-slow"/><div>{STEPS.map((s, i) => <p key={s} className={i < step ? 'done' : i === step ? 'now' : ''}>{s}</p>)}</div></div>}
    {res && <div className="fade-up">
      <div className="tb-cards">
        <div className="tb-card"><span>Synthetic world</span><b>{res.world.accounts}</b><small>accounts · {res.world.transfers} transfers · {res.world.rings} mule rings</small></div>
        {main.map(k => det[k] && <div className="tb-card" key={k} style={{borderColor: COLORS[k]}}><span>{k}</span><b>{Math.round(det[k].precision * 100)}% / {Math.round(det[k].recall * 100)}%</b>
          <small>precision / recall · {det[k].false_positives} false alarm(s){det[k].minutes_to_flag != null ? ` · flags in ${det[k].minutes_to_flag} min` : ''}</small></div>)}
        <div className="tb-card"><span>TraceFlow recall</span><b>{Math.round(res.trace_recall * 100)}%</b><small>of victim money followed to the true cash-out</small></div>
      </div>
      <div className="acct-two">
        <div className="panel"><div className="panel-head"><h3>Detectors compared</h3></div>
          <div className="tb-table"><div className="tb-tr head"><span>Detector</span><span>Precision</span><span>Recall</span><span>F1</span><span>False alarms</span></div>
            {Object.entries(det).map(([k, v]) => <div className="tb-tr" key={k}><span><i style={{background: COLORS[k]}}/>{k}</span>
              <span><div className="tb-mini"><i style={{width: `${v.precision * 100}%`}}/></div>{Math.round(v.precision * 100)}%</span>
              <span><div className="tb-mini"><i style={{width: `${v.recall * 100}%`}}/></div>{Math.round(v.recall * 100)}%</span>
              <b>{v.f1}</b><span>{v.false_positives}</span></div>)}</div></div>
        <div className="panel"><div className="panel-head"><h3>Average TraceScore by true role</h3></div>
          <div className="sharebars">{Object.entries(res.evaluation.score_by_role).map(([role, v]) => <div className="sharebar" key={role}>
            <div className="sharebar-top"><span>{role}</span><b>{v}</b></div><div className="sharebar-track"><i style={{width: `${v}%`, background: v >= 50 ? '#E5482F' : v >= 25 ? '#E3A127' : '#5B2EFF'}}/></div></div>)}</div></div>
      </div>
      <div className="acct-two">
        <div className="panel"><div className="panel-head"><h3><Timer size={15}/> Robustness: mules wait longer</h3></div>
          <Lines rows={res.robustness} xKey="mule_delay_minutes" xLabel="Minutes each mule waits before forwarding → recall" keys={main}/></div>
        <div className="panel"><div className="panel-head"><h3>Data gaps: records missing</h3></div>
          <Lines rows={res.data_gaps} xKey="records_dropped" xLabel="Share of records deleted → recall" keys={[...main, 'trace_recall']}/></div>
      </div>
      {res.notes.map((n, i) => <p key={i} className="gx-fine">{n}</p>)}
    </div>}
  </section>;
}
