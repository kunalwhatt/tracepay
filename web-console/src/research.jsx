import React, {useEffect, useState} from 'react';
import {Brain, Download, FlaskConical, ShieldAlert, Swords, TrendingUp, Users} from 'lucide-react';
import {api, API} from './lib.js';
import {PixelHero} from './intel.jsx';

const pct = v => (v * 100).toFixed(1) + '%';
const TABS = [['Adversary simulation', Swords], ['Learned vs expert', Brain], ['Drift monitor', TrendingUp], ['Explanation study', Users], ['Dataset', Download]];

export default function ResearchLab({token, setError}) {
  const [tab, setTab] = useState('Adversary simulation');
  return <div className="fi">
    <PixelHero title="Research lab" sub="How well TraceScore holds up against adaptive mules, how it compares with a learned model, whether it drifts, and whether explanations change what people do."/>
    <div className="fi-tabs">{TABS.map(([n, I]) => <button key={n} className={tab === n ? 'on' : ''} onClick={() => setTab(n)}><I size={16}/>{n}</button>)}</div>
    {tab === 'Adversary simulation' && <Adversary token={token} setError={setError}/>}
    {tab === 'Learned vs expert' && <Learned token={token} setError={setError}/>}
    {tab === 'Drift monitor' && <Drift token={token} setError={setError}/>}
    {tab === 'Explanation study' && <Study token={token} setError={setError}/>}
    {tab === 'Dataset' && <Dataset token={token}/>}
  </div>;
}

function useLoad(path, token, setError) {
  const [d, setD] = useState(null);
  useEffect(() => { api(path, {}, token).then(setD).catch(e => setError(e.message)); }, [path, token]);
  return d;
}
const Loading = ({what}) => <div className="panel fi-load">{what}… (the first run takes up to a minute while TraceBench simulates the worlds)</div>;

function Adversary({token, setError}) {
  const d = useLoad('/api/v1/research/adversary', token, setError);
  if (!d) return <Loading what="Simulating adaptive mules"/>;
  const base = d.results[0];
  return <div className="panel">
    <h3>Does TraceScore survive mules that adapt?</h3>
    <p className="gx-fine">TraceBench rebuilds the same world with mule rings using evasion tactics. "Flagged" means TraceScore 25 or above.</p>
    <table className="fi-table rl-table"><thead><tr><th>Mule strategy</th><th>Precision</th><th>Recall</th><th>F1</th><th>vs baseline</th><th>Mule avg score</th><th>Normal avg score</th></tr></thead>
      <tbody>{d.results.map(r => { const drop = r.f1 - base.f1; return <tr key={r.strategy}>
        <td><b>{r.strategy}</b></td><td>{pct(r.precision)}</td><td>{pct(r.recall)}</td><td><b>{pct(r.f1)}</b></td>
        <td style={{color: drop < -0.1 ? '#E03E2D' : drop < 0 ? '#E59A00' : '#0A9D5A', fontWeight: 800}}>{drop === 0 ? '—' : (drop > 0 ? '+' : '') + (drop * 100).toFixed(1)}</td>
        <td>{r.mule_avg_score}</td><td>{r.normal_avg_score}</td></tr>; })}</tbody></table>
    <div className="rl-note"><ShieldAlert size={18}/><span>Rows in red are where detection breaks. These are the weaknesses to report in the paper and to target with new signals.</span></div>
  </div>;
}

function Learned({token, setError}) {
  const d = useLoad('/api/v1/research/learned', token, setError);
  if (!d) return <Loading what="Training the learned model"/>;
  const max = Math.max(...d.signal_weights.map(w => Math.abs(w.learned_weight)), 0.01);
  return <div className="fi-grid">
    <div className="panel">
      <h3>Expert weights vs a learned model</h3>
      <p className="gx-fine">Trained on TraceBench worlds {d.train_seeds.join(', ')}, tested on world {d.test_seed}. Same signals, different weights.</p>
      {[['Expert TraceScore', d.expert_TraceScore], ['Learned model', d.learned_model]].map(([n, m]) => <div key={n} className="rl-model">
        <b>{n}</b><span>Precision {pct(m.precision)}</span><span>Recall {pct(m.recall)}</span><span className="rl-f1">F1 {pct(m.f1)}</span><span>{m.false_positives} false alarms</span></div>)}
    </div>
    <div className="panel">
      <h3>What each signal is worth</h3>
      {d.signal_weights.map(w => <div key={w.code} className="rl-w"><span>{w.label}</span>
        <div><i style={{width: Math.abs(w.learned_weight) / max * 100 + '%', background: w.learned_weight >= 0 ? '#5B2EFF' : '#0A9D5A'}}/></div>
        <em>{w.learned_weight}</em><small>expert +{w.expert_points}</small></div>)}
    </div>
  </div>;
}

function Drift({token, setError}) {
  const d = useLoad('/api/v1/research/drift', token, setError);
  if (!d) return <Loading what="Comparing this week with the last month"/>;
  const col = d.status === 'stable' ? '#0A9D5A' : d.status === 'moderate drift' ? '#E59A00' : '#E03E2D';
  return <>
    <div className="fi-kpis">{[['Drift (PSI)', d.psi], ['Status', d.status], ['Checks this week', d.recent_checks], ['Avg score: this week / before', `${d.recent_avg ?? '—'} / ${d.baseline_avg ?? '—'}`]]
      .map(([k, v], i) => <div key={k} className="fi-kpi"><small>{k}</small><b style={i === 1 ? {color: col, fontSize: 20} : {}}>{v}</b></div>)}</div>
    <div className="panel"><h3>How often each signal fires</h3>
      <p className="gx-fine">PSI under 0.1 is stable, 0.1–0.25 moderate, above 0.25 significant: a sign scam patterns are changing.</p>
      {d.signals.length ? d.signals.map(s => <div key={s.code} className="rl-w"><span>{s.code}</span>
        <div><i style={{width: Math.min(100, s.baseline_rate * 100) + '%', background: '#D6CFE8'}}/><i style={{width: Math.min(100, s.recent_rate * 100) + '%', background: '#5B2EFF', marginTop: 3}}/></div>
        <em>{pct(s.recent_rate)}</em><small>before {pct(s.baseline_rate)}</small></div>) : <p className="gx-fine">No checks recorded yet. Every TraceScore lookup is logged from v1.1.</p>}
    </div>
  </>;
}

function Study({token, setError}) {
  const d = useLoad('/api/v1/research/study', token, setError);
  if (!d) return <Loading what="Loading decisions"/>;
  return <div className="panel">
    <h3>Do explanations stop risky payments?</h3>
    <p className="gx-fine">Every time someone sees a TraceScore report in the app, their choice (pay, cancel, report) and whether they opened the explanation are logged. {d.total} decisions so far.</p>
    <table className="fi-table rl-table"><thead><tr><th>Risk band</th><th>Opened explanation</th><th>Decisions</th><th>Paid</th><th>Cancelled</th><th>Reported</th><th>Pay-through</th><th>Avg time on report</th></tr></thead>
      <tbody>{d.groups.map((g, i) => <tr key={i}><td><b>{g.band}</b></td><td>{g.explanation_opened ? 'Yes' : 'No'}</td><td>{g.decisions}</td><td>{g.paid}</td><td>{g.cancelled}</td><td>{g.reported}</td>
        <td style={{fontWeight: 800, color: g.pay_through_rate > 0.5 && g.band.includes('review') ? '#E03E2D' : '#14092E'}}>{pct(g.pay_through_rate)}</td><td>{g.avg_seconds}s</td></tr>)}</tbody></table>
    <div className="rl-note"><FlaskConical size={18}/><span>Research question: in high-risk bands, is pay-through lower when people open the explanation? Lower is better.</span></div>
  </div>;
}

function Dataset({token}) {
  const [seed, setSeed] = useState(42);
  async function download() {
    const r = await fetch(`${API}/api/v1/research/dataset.csv?seed=${seed}`, {headers: {Authorization: `Bearer ${token}`}});
    const blob = await r.blob(); const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `tracebench_seed${seed}.csv`; a.click();
  }
  return <div className="panel">
    <h3>TraceBench dataset</h3>
    <p className="gx-fine">A labelled synthetic UPI world: every payment with a timestamp, and every account's true role (normal user, shop, victim, collector, layer, cash-out). Use it to train and compare temporal graph neural networks against TraceScore.</p>
    <div className="fi-ev-search" style={{marginTop: 12}}><label className="acx-field" style={{margin: 0}}><span>World seed</span><input type="number" value={seed} onChange={e => setSeed(Number(e.target.value) || 42)}/></label>
      <button className="np" onClick={download}><Download size={15}/> Download CSV</button></div>
  </div>;
}
