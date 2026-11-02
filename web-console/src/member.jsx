import React, {useEffect, useState} from 'react';
import {Activity, AlertTriangle, BadgeCheck, Bell, Flag, Home, Info, LifeBuoy, LogOut, Search, ShieldCheck, UserRound, Wallet, X} from 'lucide-react';
import {api} from './lib.js';

const BANDS = {low: ['Excellent', '#0A9D5A', '#E6F6EE'], watch: ['Average', '#E59A00', '#FFF4DC'], review: ['Poor', '#E03E2D', '#FDEAE7'], high_review: ['Poor', '#E03E2D', '#FDEAE7']};
const band = b => BANDS[b] || ['New', '#A39DBB', '#F7F5FD'];
const rupees = v => '₹' + Number(v || 0).toLocaleString('en-IN', {maximumFractionDigits: 2});
const TABS = [['Overview', Home], ['Activity', Activity], ['Check a UPI ID', Search], ['Report a scam', Flag], ['Safety & help', LifeBuoy], ['Account', UserRound]];

/** The member portal: a separate, simpler console for trace.pay users (not investigators). */
export default function MemberPortal({token, email, onLogout}) {
  const [tab, setTab] = useState('Overview');
  const [profile, setProfile] = useState(null), [wallet, setWallet] = useState(null), [transfers, setTransfers] = useState([]), [external, setExternal] = useState([]);
  const [status, setStatus] = useState(null), [toast, setToast] = useState(''), [error, setError] = useState('');
  async function load() {
    const rs = await Promise.allSettled([api('/api/v1/pilot/profile', {}, token), api('/api/v1/pilot/wallet', {}, token), api('/api/v1/pilot/transfers?limit=100', {}, token),
      api('/api/v1/external-payments', {}, token), api('/api/v1/auth/email/status', {}, token)]);
    const v = i => rs[i].status === 'fulfilled' ? rs[i].value : null;
    setProfile(v(0)?.profile || null); setWallet(v(1)); setTransfers(v(2) || []); setExternal(v(3) || []); setStatus(v(4));
  }
  useEffect(() => { load(); const id = setInterval(load, 20000); return () => clearInterval(id); }, [token]);
  useEffect(() => { if (!toast) return; const id = setTimeout(() => setToast(''), 3000); return () => clearTimeout(id); }, [toast]);
  const me = profile?.vpa_id;
  const items = [
    ...transfers.map(t => ({id: 'tp' + t.transfer_ref, who: t.sender_vpa === me ? t.receiver_vpa : t.sender_vpa, amount: t.amount, incoming: t.receiver_vpa === me, status: t.status, via: 'trace.pay', at: t.created_at, ref: t.transfer_ref})),
    ...external.map(e => ({id: 'ex' + e.id, who: e.payee_name || e.payee_vpa, amount: e.amount, incoming: false, status: e.status, via: e.app, at: e.paid_at || e.created_at, band: e.risk_band, score: e.risk_score, ref: e.upi_txn_id || e.payee_vpa})),
  ].sort((a, b) => (b.at || '').localeCompare(a.at || ''));
  return <div className="mp">
    <header className="mp-top">
      <div className="mp-brand"><img src="/tracepay-mark.svg" alt=""/><b>trace<span>.</span>pay</b><em>Member</em></div>
      <nav className="mp-tabs">{TABS.map(([n, I]) => <button key={n} className={tab === n ? 'on' : ''} onClick={() => setTab(n)}><I size={16}/>{n}</button>)}</nav>
      <div className="mp-me"><span>{profile?.full_name || email}</span><button className="np np-white np-sm" onClick={onLogout}><LogOut size={14}/> Sign out</button></div>
    </header>
    <main className="mp-main">
      {status && status.required && !status.verified && <div className="mp-banner"><AlertTriangle size={18}/><span><b>Verify your email to pay.</b> Open the trace.pay app and enter the code we emailed you.</span></div>}
      {tab === 'Overview' && <Overview profile={profile} wallet={wallet} items={items} go={setTab}/>}
      {tab === 'Activity' && <ActivityList items={items}/>}
      {tab === 'Check a UPI ID' && <Check token={token} onReport={() => setTab('Report a scam')}/>}
      {tab === 'Report a scam' && <Report token={token} done={() => setToast('Report sent. Investigators will review it.')} setError={setError}/>}
      {tab === 'Safety & help' && <Help/>}
      {tab === 'Account' && <Account profile={profile} email={email} status={status}/>}
    </main>
    {toast && <div className="toast"><BadgeCheck size={17}/>{toast}</div>}
    {error && <div className="global-error"><AlertTriangle size={16}/>{error}<button onClick={() => setError('')}><X size={15}/></button></div>}
  </div>;
}

function Overview({profile, wallet, items, go}) {
  const month = items.filter(i => (i.at || '').slice(0, 7) === new Date().toISOString().slice(0, 7));
  const spent = month.filter(i => !i.incoming && i.status === 'SUCCESS').reduce((a, i) => a + Number(i.amount || 0), 0);
  const flagged = month.filter(i => i.band === 'review' || i.band === 'high_review').length;
  return <>
    <h1 className="cirka mp-h1">Hi {(profile?.full_name || 'there').split(' ')[0]},</h1>
    <div className="mp-grid">
      <section className="mp-balance"><small>trace.pay balance</small><b>{rupees(wallet?.balance)}</b><span>{profile?.vpa_id}</span>
        <div><button className="np np-lime" onClick={() => go('Check a UPI ID')}><Search size={16}/> Check a UPI ID</button></div></section>
      <section className="mp-card"><ShieldCheck size={26} color="#0A9D5A"/><h3>{flagged ? `${flagged} risky payment${flagged > 1 ? 's' : ''} flagged` : "You're well protected"}</h3>
        <div className="mp-stats"><span><b>{month.length}</b>payments this month</span><span><b>{rupees(spent)}</b>spent</span><span><b>{flagged}</b>flagged</span></div></section>
    </div>
    <div className="mp-section-head"><h2 className="cirka">Recent</h2><button className="np np-white np-sm" onClick={() => go('Activity')}>See all</button></div>
    <ActivityList items={items.slice(0, 5)} compact/>
  </>;
}

function ActivityList({items, compact}) {
  if (!items.length) return <p className="gx-fine mp-empty">No payments yet. Scan any UPI QR in the trace.pay app to pay safely.</p>;
  return <div className="mp-list">{!compact && <h1 className="cirka mp-h1">Activity</h1>}{items.map(i => {
    const [label, col, bg] = band(i.band);
    return <div className="mp-row" key={i.id}><i>{(i.who || '?').slice(0, 2).toUpperCase()}</i>
      <div><b>{i.who}</b><small>{i.via} · {i.at ? new Date(i.at).toLocaleString('en-IN', {dateStyle: 'medium', timeStyle: 'short'}) : ''}{i.ref ? ` · ${i.ref}` : ''}</small></div>
      <div className="mp-amt"><b style={{color: i.status !== 'SUCCESS' ? '#A39DBB' : i.incoming ? '#0A9D5A' : '#14092E'}}>{i.incoming ? '+' : '−'}{rupees(i.amount)}</b>
        {i.band ? <em style={{color: col, background: bg}}>{label}{i.score != null ? ` · ${i.score}%` : ''}</em> : <small>{i.status === 'SUCCESS' ? (i.incoming ? 'Received' : 'Paid') : i.status.toLowerCase()}</small>}</div></div>;
  })}</div>;
}

function Check({token, onReport}) {
  const [q, setQ] = useState(''), [r, setR] = useState(null), [busy, setBusy] = useState(false), [msg, setMsg] = useState(''), [rules, setRules] = useState(null);
  async function check() { setBusy(true); setMsg(''); setR(null); try { setR(await api('/api/v1/lookup?ref=' + encodeURIComponent(q.trim()), {}, token)); } catch (e) { setMsg(e.message); } finally { setBusy(false); } }
  async function showRules() { try { setRules(await api('/api/v1/scoring/model', {}, token)); } catch (e) { setMsg(e.message); } }
  const [label, col, bg] = band(r?.band);
  return <>
    <h1 className="cirka mp-h1">Check any UPI ID</h1>
    <div className="mp-check"><input value={q} onChange={e => setQ(e.target.value)} onKeyDown={e => e.key === 'Enter' && q && check()} placeholder="name@okaxis, 98xxxxxx@ybl or a full upi:// link"/>
      <button className="np" disabled={!q.trim() || busy} onClick={check}>{busy ? 'Checking…' : 'Check'}</button></div>
    {msg && <p className="mp-err">{msg}</p>}
    {r && <div className="mp-report">
      <div className="mp-score" style={{'--c': col, '--p': (r.score ?? 0) + '%'}}><div><small>RISK SCORE</small><b>{r.score ?? '—'}<sup>%</sup></b><em style={{color: col, background: bg}}>{label}</em></div></div>
      <div className="mp-verdict">
        <h3>{r.display_name || r.ref}</h3><p className="gx-fine">{r.ref}</p>
        <div className="mp-callout" style={{background: bg, color: col}}><b>{r.verdict?.title}</b><span>{r.verdict?.advice}</span></div>
        <div className="mp-section-head"><h3>Why this score</h3><button className="np np-white np-sm" onClick={showRules}><Info size={14}/> How it's scored</button></div>
        {(r.factors || []).map(f => <div className="mp-factor" key={f.code + f.label}>
          <i style={{background: f.points < 0 ? '#0A9D5A' : '#E03E2D'}}/><div><b>{f.label}</b>{f.detail && <small>{f.detail}</small>}</div>
          {f.points !== 0 && <em style={{color: f.points < 0 ? '#0A9D5A' : '#E03E2D'}}>{f.points > 0 ? '+' : '−'}{Math.abs(f.points)}</em>}</div>)}
        <button className="np np-white" onClick={onReport}><Flag size={15}/> Report this account</button>
      </div></div>}
    {rules && <div className="ad-scrim" onClick={() => setRules(null)}><div className="ad-modal mp-rules" onClick={e => e.stopPropagation()}>
      <div className="ad-mhead"><h3 className="cirka">How the score works</h3><button className="ad-x" onClick={() => setRules(null)}><X size={18}/></button></div>
      <p className="gx-fine">{rules.summary}</p>
      {rules.bands.map(b => <div className="mp-rule" key={b.range}><b style={{color: band(b.band)[1]}}>{b.range}</b><div><b>{b.label}</b><small>{b.meaning}</small></div></div>)}
      <h4>Payment behaviour</h4>{rules.signals.map(s => <div className="mp-rule" key={s.code}><em>{s.points > 0 ? '+' : ''}{s.points}</em><div><b>{s.label}</b><small>{s.rule}</small></div></div>)}
      <h4>Reports and trust</h4>{rules.community.map(s => <div className="mp-rule" key={s.code}><em>{String(s.points)}</em><div><b>{s.label}</b><small>{s.rule}</small></div></div>)}
      <p className="gx-fine">{rules.window}</p>
    </div></div>}
  </>;
}

const CATS = [['scam_payment', 'Scam payment'], ['task_scam', 'Task scam'], ['investment_scam', 'Investment scam'], ['fake_merchant', 'Fake shop'], ['loan_app', 'Loan app'], ['impersonation', 'Impersonation']];
function Report({token, done, setError}) {
  const [ref, setRef] = useState(''), [cat, setCat] = useState('task_scam'), [details, setDetails] = useState(''), [amount, setAmount] = useState(''), [busy, setBusy] = useState(false);
  async function send() {
    setBusy(true);
    try { await api('/api/v1/community/reports', {method: 'POST', body: JSON.stringify({target_ref: ref.trim(), category: cat, description: details, ...(Number(amount) ? {amount: Number(amount).toFixed(2)} : {})})}, token); done(); setRef(''); setDetails(''); setAmount(''); }
    catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  return <>
    <h1 className="cirka mp-h1">Report a scam</h1>
    <p className="gx-fine">Confirmed reports warn everyone who tries to pay that account.</p>
    <div className="mp-form">
      <label className="ad-field"><span>UPI ID</span><input value={ref} onChange={e => setRef(e.target.value)} placeholder="scammer@ybl"/></label>
      <div className="mp-cats">{CATS.map(([k, l]) => <button key={k} className={cat === k ? 'on' : ''} onClick={() => setCat(k)}>{l}</button>)}</div>
      <label className="ad-field"><span>Details</span><input value={details} onChange={e => setDetails(e.target.value)} placeholder="What happened (optional)"/></label>
      <label className="ad-field"><span>Amount lost ₹</span><input inputMode="decimal" value={amount} onChange={e => setAmount(e.target.value.replace(/[^\d.]/g, ''))} placeholder="Optional"/></label>
      <button className="np np-danger" disabled={busy || !ref.includes('@')} onClick={send}><Flag size={15}/> {busy ? 'Sending…' : 'Send report'}</button>
    </div>
  </>;
}

function Help() {
  return <>
    <h1 className="cirka mp-h1">Safety & help</h1>
    <div className="mp-help">
      <a href="tel:1930" className="mp-card"><LifeBuoy size={22} color="#E03E2D"/><h3>Call 1930</h3><p className="gx-fine">National cyber-crime helpline. Act within the first hour.</p></a>
      <a href="https://cybercrime.gov.in" target="_blank" rel="noreferrer" className="mp-card"><Flag size={22} color="#E03E2D"/><h3>File a complaint</h3><p className="gx-fine">At cybercrime.gov.in. Keep screenshots of the chat and payment.</p></a>
      <div className="mp-card"><Wallet size={22} color="#5B2EFF"/><h3>Call your bank</h3><p className="gx-fine">Ask them to block the transaction and raise a dispute.</p></div>
    </div>
    <h2 className="cirka">Know the scams</h2>
    <div className="mp-help">
      <div className="mp-card"><h3>Task scams</h3><p className="gx-fine">"Like videos, earn money", then pay to unlock earnings. Real jobs never ask you to pay.</p></div>
      <div className="mp-card"><h3>Fake KYC calls</h3><p className="gx-fine">No bank asks for your UPI PIN or OTP on a call or link.</p></div>
      <div className="mp-card"><h3>Investment groups</h3><p className="gx-fine">Guaranteed returns on WhatsApp or Telegram are scams.</p></div>
    </div>
  </>;
}

function Account({profile, email, status}) {
  return <>
    <h1 className="cirka mp-h1">Account</h1>
    <div className="mp-card mp-acct">
      {[['Name', profile?.full_name], ['trace.pay ID', profile?.vpa_id], ['Email', status?.email || email], ['Email verified', status ? (status.verified ? 'Yes' : status.required ? 'No · payments blocked' : 'Not needed') : '—']]
        .map(([k, v]) => <div key={k}><span>{k}</span><b>{v || '—'}</b></div>)}
      <p className="gx-fine">To change your password, use "Forgot password?" on the app's sign-in screen. Device lock, cooling-off and limits are set in the app.</p>
    </div>
  </>;
}
