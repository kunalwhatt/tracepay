import React, {useEffect, useMemo, useState} from 'react';
import {AlertTriangle, BadgeCheck, FileDown, Link2, MessageSquareWarning, Network, Radar, Search, ShieldCheck} from 'lucide-react';
import {api} from './lib.js';

const BAND = {low: ['Low', '#0A9D5A', '#E6F6EE'], watch: ['Watch', '#E59A00', '#FFF4DC'], review: ['High', '#E03E2D', '#FDEAE7'], high_review: ['Very high', '#B42A1B', '#FDEAE7'], insufficient_information: ['New', '#6B6585', '#F7F5FD']};
const bandOf = b => BAND[b] || BAND.insufficient_information;
const CAT_COLORS = ['#5B2EFF', '#C6FF3D', '#E03E2D', '#E59A00', '#1E7BFF', '#0A9D5A', '#8F6BFF', '#14092E'];
const rupees = v => '₹' + Number(v || 0).toLocaleString('en-IN', {maximumFractionDigits: 0});
const TABS = [['Trend radar', Radar], ['Campaigns', Network], ['Message & link check', MessageSquareWarning], ['Evidence pack', FileDown]];

/** Animated pixel field (the logo's corner squares) for hero banners. */
export function PixelHero({title, sub, children}) {
  const pixels = useMemo(() => Array.from({length: 46}, (_, i) => ({x: Math.random() * 100, y: Math.random() * 100, s: 6 + Math.random() * 14,
    d: 4 + Math.random() * 7, delay: -Math.random() * 8, lime: i % 6 === 0, z: Math.random()})), []);
  return <section className="px-hero">
    <div className="px-field" aria-hidden="true">{pixels.map((p, i) => <i key={i} style={{left: p.x + '%', top: p.y + '%', width: p.s, height: p.s,
      animationDuration: p.d + 's', animationDelay: p.delay + 's', opacity: .25 + p.z * .6, background: p.lime ? '#C6FF3D' : p.z > .6 ? '#fff' : '#8F6BFF',
      transform: `translateZ(${Math.round(p.z * 60)}px)`}}/>)}</div>
    <div className="px-copy"><div className="px-badge"><img src="/tracepay-mark.svg" alt=""/><b>Trace<span>Score</span></b> intelligence</div>
      <h2 className="cirka">{title}</h2><p>{sub}</p>{children}</div>
  </section>;
}

/** trace.pay merchant badge. */
export function MerchantBadge({badge}) {
  if (!badge) return null;
  const verified = badge.tier === 'verified';
  return <span className={`tp-badge ${verified ? 'v' : 'r'}`} title={badge.detail}><BadgeCheck size={14}/>{badge.label}</span>;
}

export default function FraudIntel({token, setToast, setError}) {
  const [tab, setTab] = useState('Trend radar');
  return <div className="fi">
    <PixelHero title="Fraud intelligence" sub="Every report, message check and warning across trace.pay, turned into trends, campaigns and evidence."/>
    <div className="fi-tabs">{TABS.map(([n, I]) => <button key={n} className={tab === n ? 'on' : ''} onClick={() => setTab(n)}><I size={16}/>{n}</button>)}</div>
    {tab === 'Trend radar' && <Trends token={token} setError={setError}/>}
    {tab === 'Campaigns' && <Campaigns token={token} setError={setError} open={() => setTab('Evidence pack')}/>}
    {tab === 'Message & link check' && <Analyzer token={token} setError={setError}/>}
    {tab === 'Evidence pack' && <Evidence token={token} setError={setError} setToast={setToast}/>}
  </div>;
}

function Trends({token, setError}) {
  const [days, setDays] = useState(30), [d, setD] = useState(null);
  useEffect(() => { api(`/api/v1/intel/trends?days=${days}`, {}, token).then(setD).catch(e => setError(e.message)); }, [days, token]);
  if (!d) return <div className="panel fi-load">Loading trends…</div>;
  const cats = d.categories.map(c => c.category);
  const max = Math.max(1, ...d.series.map(s => cats.reduce((a, c) => a + (s[c] || 0), 0)));
  return <>
    <div className="fi-kpis">
      {[['Reports', d.total_reports], ['Money reported lost', rupees(d.total_lost)], ['Messages checked', d.messages_checked], ['People warned', d.people_warned]]
        .map(([k, v]) => <div key={k} className="fi-kpi"><small>{k}</small><b>{v}</b></div>)}
    </div>
    <div className="fi-grid">
      <div className="panel">
        <div className="fi-head"><h3>Reports per day</h3><div className="fi-range">{[7, 30, 90].map(n => <button key={n} className={days === n ? 'on' : ''} onClick={() => setDays(n)}>{n}d</button>)}</div></div>
        <div className="fi-bars">{d.series.length ? d.series.map(s => <div key={s.date} className="fi-bar" title={s.date}>
          {cats.map((c, i) => s[c] ? <i key={c} style={{height: (s[c] / max * 100) + '%', background: CAT_COLORS[i % 8]}}/> : null)}</div>) : <p className="gx-fine">No reports in this period.</p>}</div>
        <div className="fi-legend">{d.categories.map((c, i) => <span key={c.category}><i style={{background: CAT_COLORS[i % 8]}}/>{c.label}</span>)}</div>
      </div>
      <div className="panel">
        <h3>By scam type</h3>
        {d.categories.map((c, i) => <div className="fi-cat" key={c.category}><i style={{background: CAT_COLORS[i % 8]}}/><span>{c.label}</span><b>{c.reports}</b><em>{rupees(c.lost)}</em></div>)}
        <h3 style={{marginTop: 18}}>Most-reported accounts</h3>
        {d.top_accounts.map(a => <div className="fi-cat" key={a.ref}><i style={{background: '#E03E2D'}}/><span className="mono">{a.ref}</span><b>{a.reports}</b></div>)}
      </div>
    </div>
  </>;
}

function Campaigns({token, setError}) {
  const [rows, setRows] = useState(null);
  useEffect(() => { api('/api/v1/intel/campaigns', {}, token).then(setRows).catch(e => setError(e.message)); }, [token]);
  if (!rows) return <div className="panel fi-load">Finding campaigns…</div>;
  if (!rows.length) return <div className="panel"><p className="gx-fine">No campaigns yet. Campaigns appear when several reports share an account or very similar wording.</p></div>;
  return <div className="fi-camps">{rows.map((c, i) => <div className="fi-camp" key={i}>
    <div className="fi-camp-top"><span className="fi-chip">{c.label}</span><b>{c.size} reports</b></div>
    <h3>{rupees(c.total_lost)} reported lost</h3>
    <p className="gx-fine">{new Date(c.first).toLocaleDateString('en-IN')} – {new Date(c.last).toLocaleDateString('en-IN')} · {c.accounts.length} account{c.accounts.length > 1 ? 's' : ''}</p>
    <div className="fi-accts">{c.accounts.slice(0, 8).map(a => <code key={a}>{a}</code>)}</div>
  </div>)}</div>;
}

function Analyzer({token, setError}) {
  const [text, setText] = useState(''), [r, setR] = useState(null), [busy, setBusy] = useState(false);
  async function run() { setBusy(true); try { setR(await api('/api/v1/intel/message', {method: 'POST', body: JSON.stringify({text})}, token)); } catch (e) { setError(e.message); } finally { setBusy(false); } }
  const [label, col, bg] = bandOf(r?.overall_band);
  return <div className="fi-grid">
    <div className="panel">
      <h3>Paste a message, link or UPI ID</h3>
      <textarea className="fi-text" value={text} onChange={e => setText(e.target.value)} placeholder="e.g. URGENT: Your KYC is pending. Your account will be blocked today. Pay ₹10 to verify@ybl or click bit.ly/…"/>
      <button className="np" disabled={busy || text.trim().length < 3} onClick={run}><Search size={15}/> {busy ? 'Checking…' : 'Check for scams'}</button>
    </div>
    <div className="panel">
      {!r ? <p className="gx-fine">Results appear here: scam language, risky links, and the TraceScore of every UPI ID and phone number in the message.</p> : <>
        <div className="fi-verdict" style={{background: bg, color: col}}><AlertTriangle size={20}/><div><b>{r.verdict}</b><span>Risk {r.overall}% · {label}</span></div></div>
        {r.signals.map(s => <div className="fi-sig" key={s.code}><b>{s.label}</b><em>+{s.points}</em><small>{(s.matched || []).map(m => `"${m}"`).join(', ')}</small></div>)}
        {r.upi_checks.map(c => <div className="fi-sig" key={c.ref}><b><ShieldCheck size={14}/> {c.ref}{c.name ? ` · ${c.name}` : ''}</b><em style={{color: bandOf(c.band)[1]}}>{c.score ?? '—'}%</em><small>{c.title} · {c.reports} report{c.reports === 1 ? '' : 's'}</small></div>)}
        {r.phone_checks.map(p => <div className="fi-sig" key={p.number}><b>📞 {p.number}</b><em style={{color: bandOf(p.band)[1]}}>{p.score}%</em><small>{p.reports} report{p.reports === 1 ? '' : 's'}</small></div>)}
        {r.link_checks.map(l => <div className="fi-sig" key={l.url}><b><Link2 size={14}/> {l.host}</b><em style={{color: bandOf(l.band)[1]}}>{l.score}%</em><small>{l.signals.map(s => s.label).join(' · ') || 'No warning signs'}</small></div>)}
      </>}
    </div>
  </div>;
}

function Evidence({token, setError, setToast}) {
  const [ref, setRef] = useState(''), [e, setE] = useState(null), [busy, setBusy] = useState(false);
  async function load() { setBusy(true); try { setE(await api('/api/v1/intel/evidence?ref=' + encodeURIComponent(ref.trim()), {}, token)); } catch (x) { setError(x.message); } finally { setBusy(false); } }
  const [label, col] = bandOf(e?.band);
  return <>
    <div className="panel fi-ev-search"><input value={ref} onChange={x => setRef(x.target.value)} onKeyDown={x => x.key === 'Enter' && ref && load()} placeholder="UPI ID, e.g. collector@ybl"/>
      <button className="np" disabled={busy || ref.trim().length < 3} onClick={load}>{busy ? 'Building…' : 'Build evidence pack'}</button>
      {e && <button className="np np-white" onClick={() => { window.print(); setToast('Use "Save as PDF" in the print window'); }}><FileDown size={15}/> Save as PDF</button>}</div>
    {e && <article className="fi-ev print-area">
      <header><div><small>trace.pay · evidence package</small><h2 className="cirka">{e.account}</h2><p>{e.name || 'Name not on record'}</p></div>
        <div className="fi-ev-score" style={{color: col}}><b>{e.score ?? '—'}%</b><span>{label} risk · {e.stage?.label}</span></div></header>
      <div className="fi-kpis">{[['Payments', e.summary.payments], ['Money in', rupees(e.summary.inflow)], ['Money out', rupees(e.summary.outflow)], ['Payers → payees', `${e.summary.payers} → ${e.summary.payees}`]]
        .map(([k, v]) => <div key={k} className="fi-kpi"><small>{k}</small><b>{v}</b></div>)}</div>
      <h3>Why it was flagged</h3>{e.factors.map(f => <div className="fi-sig" key={f.code + f.label}><b>{f.label}</b><em>{f.points > 0 ? '+' : ''}{f.points}</em><small>{f.detail}</small></div>)}
      <h3>Money flow ({e.flows.length})</h3>
      <table className="fi-table"><thead><tr><th>Time</th><th>From</th><th>To</th><th>Amount</th><th>Ref</th></tr></thead>
        <tbody>{e.flows.map((f, i) => <tr key={i}><td>{new Date(f.at).toLocaleString('en-IN')}</td><td className="mono">{f.from}</td><td className="mono">{f.to}</td><td>{rupees(f.amount)}</td><td className="mono">{f.ref}</td></tr>)}</tbody></table>
      <h3>Community reports ({e.reports.length})</h3>{e.reports.map(r => <div className="fi-sig" key={r.id}><b>{r.category_label}</b><em>{r.status}</em><small>{r.description} {r.amount ? `· ₹${r.amount}` : ''}</small></div>)}
      <footer>Generated {new Date(e.generated_at).toLocaleString('en-IN')} by {e.generated_by}. Advisory analysis from trace.pay records; verify with bank records before action.</footer>
    </article>}
  </>;
}
