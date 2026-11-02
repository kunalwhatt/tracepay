import React, {useEffect, useState} from 'react';
import {BadgeCheck, MailWarning, Phone, Search, ShieldAlert, Trash2, UserRound, X} from 'lucide-react';
import {api} from './lib.js';

const SCOPES = [
  ['transactions', 'Transactions', 'Payments, ledger entries, external payments and evidence records for this account'],
  ['logs', 'Activity logs', 'Everything this person did in the app'],
  ['reports', 'Scam reports', 'Reports this person submitted'],
  ['profile', 'Profile & wallet', 'Name, selfie, Trace.Pay ID and wallet (also removes transactions)'],
  ['account', 'Whole account', 'Everything above, then the account itself. They can sign up again.'],
];

/** Admin tools: link a mobile number, erase a member's data, erase logs. Every action is audited. */
export default function AccountsData({token, setToast, setError}) {
  const [rows, setRows] = useState([]);
  const [q, setQ] = useState('');
  const [mobileFor, setMobileFor] = useState(null);
  const [eraseFor, setEraseFor] = useState(null);
  const [logs, setLogs] = useState(false);
  const [onlyUnverified, setOnlyUnverified] = useState(false);
  const isAdmin = sessionStorage.getItem('tp_role') === 'admin';
  const load = () => api('/api/v1/admin/accounts', {}, token).then(setRows).catch(e => setError(e.message));
  useEffect(() => { if (isAdmin) load(); }, [token]);
  if (!isAdmin) return <div className="panel"><h3>Admins only</h3><p className="gx-fine">Sign in as an administrator to manage accounts and data.</p></div>;
  const shown = rows.filter(r => (!onlyUnverified || r.email_verified === false) && (!q || [r.name, r.email, r.mobile, r.vpa_id].join(' ').toLowerCase().includes(q.toLowerCase())));
  const unverified = rows.filter(r => r.email_verified === false && r.role !== 'admin').length;
  async function setVerified(r, verified) {
    try { await api(`/api/v1/admin/accounts/${r.id}/email-verified`, {method: 'PATCH', body: JSON.stringify({verified})}, token); setToast(verified ? 'Marked verified: payments unlocked' : 'Marked unverified: payments blocked'); load(); }
    catch (e) { setError(e.message); }
  }
  const unlinked = rows.filter(r => !r.mobile && r.role !== 'admin').length;
  return <section className="ad">
    <div className="ad-head">
      <div><div className="eyebrow">ADMIN</div><h2 className="cirka">Accounts & data</h2>
        <p className="gx-fine">{rows.length} accounts · {unlinked} without a mobile number · <b style={{color: unverified ? '#B42A1B' : 'inherit'}}>{unverified} unverified email{unverified === 1 ? '' : 's'} (can't pay)</b></p></div>
      <button className="np np-white" onClick={() => setLogs(true)}><Trash2 size={16}/> Erase logs</button>
    </div>
    <div className="ad-tools"><label className="ad-search"><Search size={17}/><input value={q} onChange={e => setQ(e.target.value)} placeholder="Search name, email, mobile or Trace.Pay ID"/></label>
      <button className={`np ${onlyUnverified ? 'np-danger' : 'np-white'}`} onClick={() => setOnlyUnverified(v => !v)}><MailWarning size={16}/> Unverified only</button></div>
    <div className="panel ad-table">
      <div className="ad-row ad-th"><span>Account</span><span>Mobile</span><span>Activity</span><span></span></div>
      {shown.map(r => <div className="ad-row" key={r.id}>
        <span className="ad-who"><i><UserRound size={16}/></i><span><b>{r.name || r.email || r.mobile || `Account ${r.id}`}</b>
          <small>{[r.vpa_id, r.email, r.role !== 'pilot_user' ? r.role : null].filter(Boolean).join(' · ') || 'No profile yet'}</small>
          {r.email_verified === true && <em className="ad-ok"><BadgeCheck size={12}/> Email verified</em>}
          {r.email_verified === false && <em className="ad-no"><MailWarning size={12}/> Email not verified · payments blocked</em>}</span></span>
        <span>{r.mobile ? <b className="mono">+91 {r.mobile}</b> : <span className="ad-pill">Not linked</span>}</span>
        <span className="gx-fine">{r.transfers} payments · {r.external_payments} external · {r.logs} logs</span>
        <span className="ad-actions">
          <button className="np np-white np-sm" onClick={() => setMobileFor(r)}><Phone size={14}/> {r.mobile ? 'Change' : 'Link'} mobile</button>
          {r.email_verified !== null && r.email_verified !== undefined && <button className="np np-white np-sm" onClick={() => setVerified(r, !r.email_verified)}>
            {r.email_verified ? 'Unverify' : <><BadgeCheck size={14}/> Mark verified</>}</button>}
          {r.role !== 'admin' && <button className="np np-danger np-sm" onClick={() => setEraseFor(r)}><Trash2 size={14}/> Erase</button>}
        </span>
      </div>)}
      {!shown.length && <p className="gx-fine" style={{padding: 18}}>No accounts match.</p>}
    </div>
    {mobileFor && <LinkMobile row={mobileFor} token={token} onClose={() => setMobileFor(null)} onDone={() => { setMobileFor(null); setToast('Mobile number linked'); load(); }} setError={setError}/>}
    {eraseFor && <Erase row={eraseFor} token={token} onClose={() => setEraseFor(null)} onDone={msg => { setEraseFor(null); setToast(msg); load(); }} setError={setError}/>}
    {logs && <EraseLogs token={token} onClose={() => setLogs(false)} onDone={n => { setLogs(false); setToast(`${n} log entries erased`); load(); }} setError={setError}/>}
  </section>;
}

function Modal({title, children, onClose}) {
  return <div className="ad-scrim" onClick={onClose}><div className="ad-modal" onClick={e => e.stopPropagation()} role="dialog" aria-label={title}>
    <div className="ad-mhead"><h3 className="cirka">{title}</h3><button className="ad-x" onClick={onClose} aria-label="Close"><X size={18}/></button></div>{children}</div></div>;
}

function LinkMobile({row, token, onClose, onDone, setError}) {
  const [mobile, setMobile] = useState(row.mobile || ''), [busy, setBusy] = useState(false);
  async function save() {
    setBusy(true);
    try { await api(`/api/v1/admin/accounts/${row.id}/mobile`, {method: 'PATCH', body: JSON.stringify({mobile})}, token); onDone(); }
    catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  return <Modal title="Link a mobile number" onClose={onClose}>
    <p className="gx-fine">{row.name || row.email} will be able to sign in with this number and their password. No OTP is sent.</p>
    <label className="ad-field"><span>+91</span><input autoFocus inputMode="numeric" value={mobile} onChange={e => setMobile(e.target.value.replace(/[^\d ]/g, ''))} placeholder="10-digit mobile number"/></label>
    <div className="ad-mfoot"><button className="np np-white" onClick={onClose}>Cancel</button><button className="np" disabled={busy || mobile.replace(/\D/g, '').length !== 10} onClick={save}>{busy ? 'Saving…' : 'Link number'}</button></div>
  </Modal>;
}

function Erase({row, token, onClose, onDone, setError}) {
  const [scopes, setScopes] = useState(['transactions']), [confirm, setConfirm] = useState(''), [busy, setBusy] = useState(false);
  const toggle = k => setScopes(s => s.includes(k) ? s.filter(x => x !== k) : [...s, k]);
  async function erase() {
    setBusy(true);
    try {
      const r = await api(`/api/v1/admin/accounts/${row.id}/erase`, {method: 'POST', body: JSON.stringify({scopes, confirm})}, token);
      const total = Object.values(r.counts || {}).reduce((a, b) => a + b, 0);
      onDone(`Erased ${r.erased.join(', ')} (${total} records)`);
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  return <Modal title={`Erase data · ${row.name || row.email || row.mobile}`} onClose={onClose}>
    <div className="ad-warn"><ShieldAlert size={18}/><span>This permanently deletes data. It can't be undone. The action itself is recorded in the audit log.</span></div>
    <div className="ad-scopes">{SCOPES.map(([k, l, d]) => <label key={k} className={scopes.includes(k) ? 'on' : ''}>
      <input type="checkbox" checked={scopes.includes(k)} onChange={() => toggle(k)}/><span><b>{l}</b><small>{d}</small></span></label>)}</div>
    <label className="ad-field"><span>Type ERASE</span><input value={confirm} onChange={e => setConfirm(e.target.value)} placeholder="ERASE"/></label>
    <div className="ad-mfoot"><button className="np np-white" onClick={onClose}>Cancel</button>
      <button className="np np-danger" disabled={busy || confirm !== 'ERASE' || !scopes.length} onClick={erase}>{busy ? 'Erasing…' : 'Erase permanently'}</button></div>
  </Modal>;
}

function EraseLogs({token, onClose, onDone, setError}) {
  const [days, setDays] = useState(0), [confirm, setConfirm] = useState(''), [busy, setBusy] = useState(false);
  async function erase() {
    setBusy(true);
    try { const r = await api('/api/v1/admin/logs/erase', {method: 'POST', body: JSON.stringify({confirm, older_than_days: Number(days)})}, token); onDone(r.deleted); }
    catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  return <Modal title="Erase activity logs" onClose={onClose}>
    <p className="gx-fine">Deletes audit log entries for all accounts. A record of this erase is kept.</p>
    <div className="ad-scopes">{[[0, 'All logs'], [30, 'Older than 30 days'], [90, 'Older than 90 days']].map(([v, l]) =>
      <label key={v} className={days === v ? 'on' : ''}><input type="radio" checked={days === v} onChange={() => setDays(v)}/><span><b>{l}</b></span></label>)}</div>
    <label className="ad-field"><span>Type ERASE</span><input value={confirm} onChange={e => setConfirm(e.target.value)} placeholder="ERASE"/></label>
    <div className="ad-mfoot"><button className="np np-white" onClick={onClose}>Cancel</button><button className="np np-danger" disabled={busy || confirm !== 'ERASE'} onClick={erase}>{busy ? 'Erasing…' : 'Erase logs'}</button></div>
  </Modal>;
}
