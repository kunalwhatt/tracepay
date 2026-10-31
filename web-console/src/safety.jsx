import React, {useEffect, useState} from 'react';
import {BadgeCheck, CheckCircle2, Flag, Search, ShieldAlert, ShieldCheck, Store, XCircle} from 'lucide-react';
import {api, fmtDate, money} from './lib.js';
import {ScoreGauge, BAND_COLOR} from './tracescore.jsx';

const FAMILY = {core: 'Core rule', deep: 'Behaviour', community: 'Community', trust: 'Trust'};

/** Safety Center: Truecaller-style lookup, community report moderation and merchant verification. */
export default function SafetyCenter({token, setToast, setError}) {
  const [tab, setTab] = useState('lookup');
  return <section className="safety">
    <div className="section-title"><div><div className="eyebrow">TRUECALLER FOR UPI</div></div>
      <div className="gx-hops" role="tablist">{[['lookup', 'Look up an account'], ['reports', 'Community reports'], ['merchants', 'Merchants']].map(([k, l]) =>
        <button key={k} className={tab === k ? 'on' : ''} onClick={() => setTab(k)}>{l}</button>)}</div></div>
    {tab === 'lookup' && <Lookup token={token} setError={setError}/>}
    {tab === 'reports' && <Reports token={token} setToast={setToast} setError={setError}/>}
    {tab === 'merchants' && <Merchants token={token} setToast={setToast} setError={setError}/>}
  </section>;
}

export function Verdict({r}) {
  const color = BAND_COLOR[r.band] || '#5B2EFF';
  const max = Math.max(1, ...r.factors.map(f => Math.abs(f.points)));
  return <div className="panel sf-verdict fade-up">
    <div className="sf-head">
      <ScoreGauge score={r.score} band={r.band} label={r.verdict.title}/>
      <div className="sf-who">
        <h3>{r.display_name || r.ref}{r.merchant?.verified && <BadgeCheck size={20} className="sf-tick"/>}</h3>
        <span className="mono">{r.ref}</span>
        <p style={{color}}><b>{r.verdict.title}.</b> {r.verdict.advice}</p>
        <div className="sf-chips">
          <span>{r.member ? 'Trace.Pay member' : r.is_tracepay ? 'Trace.Pay ID' : 'External UPI ID'}</span>
          {r.merchant && <span><Store size={12}/> {r.merchant.verified ? 'Verified merchant' : 'Merchant'}</span>}
          <span><Flag size={12}/> {r.community.reports} report(s)</span>
          <span>{r.history.records} record(s){r.history.first_seen ? ` since ${fmtDate(r.history.first_seen)}` : ''}</span>
          <span>Confidence {Math.round((r.confidence || 0) * 100)}%</span>
        </div>
      </div>
    </div>
    <h4>Why this score</h4>
    {!r.factors.length && <p className="gx-fine">No warning or trust signals found.</p>}
    <div className="ts-bars">{r.factors.map((f, i) => <div className={`ts-bar ${f.points < 0 ? 'neg' : ''}`} key={f.code} style={{animationDelay: `${i * 60}ms`}}>
      <div className="ts-bar-top"><span><i className={`fam ${f.family}`}>{FAMILY[f.family] || f.family}</i>{f.label}</span><b>{f.points > 0 ? '+' : ''}{f.points}</b></div>
      <div className="ts-track"><i style={{width: `${Math.abs(f.points) / max * 100}%`}}/></div><small>{f.detail}</small></div>)}</div>
    {r.counterfactuals?.length > 0 && <div className="ts-cf"><h4>What would change it</h4>{r.counterfactuals.map((c, i) => <p key={i}>{c}</p>)}</div>}
    <p className="gx-fine">{r.disclaimer}</p>
  </div>;
}

function Lookup({token, setError}) {
  const [q, setQ] = useState(''), [r, setR] = useState(null), [busy, setBusy] = useState(false);
  async function go(e) {
    e?.preventDefault(); if (!q.trim()) return; setBusy(true); setR(null);
    try { setR(await api(`/api/v1/lookup?ref=${encodeURIComponent(q.trim())}`, {}, token)); } catch (err) { setError(err.message); } finally { setBusy(false); }
  }
  return <>
    <form className="panel sf-search" onSubmit={go}>
      <Search size={18}/><input value={q} onChange={e => setQ(e.target.value)} placeholder="Any UPI ID or pasted UPI QR text: name@okaxis, shop@ybl, upi://pay?pa=…"/>
      <button className="btn" disabled={busy}>{busy ? 'Checking…' : 'Check'}</button>
    </form>
    {busy && <div className="panel ts-panel"><div className="skel skel-gauge"/><div className="skel-lines"><i/><i/><i/><i/></div></div>}
    {r && <Verdict r={r}/>}
  </>;
}

function Reports({token, setToast, setError}) {
  const [status, setStatus] = useState('pending'), [rows, setRows] = useState([]);
  const load = () => api(`/api/v1/community/reports?status=${status}`, {}, token).then(setRows).catch(e => setError(e.message));
  useEffect(() => { load(); }, [status, token]);
  async function moderate(r, s) {
    try { await api(`/api/v1/community/reports/${r.id}`, {method: 'PATCH', body: JSON.stringify({status: s})}, token); setToast(`Report ${s}`); load(); }
    catch (e) { setError(e.message); }
  }
  return <div className="panel">
    <div className="panel-head"><h3>Community reports</h3>
      <div className="gx-hops">{['pending', 'verified', 'rejected'].map(s => <button key={s} className={status === s ? 'on' : ''} onClick={() => setStatus(s)}>{s}</button>)}</div></div>
    {rows.map(r => <div className="sf-report fade-up" key={r.id}>
      <ShieldAlert size={18}/>
      <div><b className="mono">{r.target_ref}</b>{r.target_name && <span> · {r.target_name}</span>}
        <small>{r.category_label}{r.amount ? ` · ${money(r.amount)}` : ''} · {fmtDate(r.created_at)}</small>{r.description && <p>{r.description}</p>}</div>
      {status === 'pending' && <div className="sf-actions">
        <button className="btn light" onClick={() => moderate(r, 'verified')}><CheckCircle2 size={15}/> Confirm</button>
        <button className="btn light danger-text" onClick={() => moderate(r, 'rejected')}><XCircle size={15}/> Reject</button></div>}
    </div>)}
    {!rows.length && <p className="gx-fine">No {status} reports. Members report scam accounts from the app; confirmed reports raise that account's score for everyone.</p>}
  </div>;
}

function Merchants({token, setToast, setError}) {
  const [rows, setRows] = useState([]);
  const load = () => api('/api/v1/pilot/merchants', {}, token).then(setRows).catch(e => setError(e.message));
  useEffect(() => { load(); }, [token]);
  async function toggle(m) {
    try { await api(`/api/v1/pilot/merchants/${m.id}/verify`, {method: 'PATCH', body: JSON.stringify({verified: !m.verified})}, token); setToast(`${m.display_name} ${m.verified ? 'unverified' : 'verified'}`); load(); }
    catch (e) { setError(e.message); }
  }
  return <div className="panel">
    <div className="panel-head"><h3>Merchants</h3><span className="gx-count">verified merchants get a ✓ badge and a lower risk score</span></div>
    {rows.map(m => <div className="sf-report" key={m.id}><Store size={18}/>
      <div><b>{m.display_name}</b> {m.verified && <BadgeCheck size={15} className="sf-tick"/>}<small className="mono">{m.vpa_id} · {m.category}{m.location ? ` · ${m.location}` : ''}</small></div>
      <button className={`btn ${m.verified ? 'light' : ''}`} onClick={() => toggle(m)}><ShieldCheck size={15}/> {m.verified ? 'Remove verification' : 'Verify'}</button></div>)}
    {!rows.length && <p className="gx-fine">No merchants registered yet.</p>}
  </div>;
}
