import React, {useEffect, useState} from 'react';
import {Search, WalletCards} from 'lucide-react';
import {API, api, fmtDate, money} from './lib.js';

/** Live selfie fetched with the investigator's token (an <img> tag cannot send it), cached for the session. */
const photoCache = new Map();
function MemberPhoto({vpa, name, token}) {
  const [src, setSrc] = useState(photoCache.get(vpa) || null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (photoCache.has(vpa)) return;
    let cancelled = false;
    fetch(`${API}/api/v1/pilot/users/${encodeURIComponent(vpa)}/photo`, {headers: {Authorization: `Bearer ${token}`}})
      .then(r => r.ok ? r.blob() : Promise.reject())
      .then(b => { const url = URL.createObjectURL(b); photoCache.set(vpa, url); if (!cancelled) setSrc(url); })
      .catch(() => { if (!cancelled) setFailed(true); });
    return () => { cancelled = true; };
  }, [vpa, token]);
  const initials = (name || vpa).split(/[ .@]/).filter(Boolean).slice(0, 2).map(x => x[0].toUpperCase()).join('');
  return src && !failed ? <img className="member-photo fade-up" src={src} alt={`${name} selfie`}/> : <span className="member-photo initials">{initials}</span>;
}

/** Members with live Trace.Pay balances; admins can add funds. */
export default function UsersPage({token, setToast, setError}) {
  const [users, setUsers] = useState([]);
  const [wallets, setWallets] = useState({});
  const [q, setQ] = useState('');
  const [funding, setFunding] = useState(null);
  const [amount, setAmount] = useState('5000');
  const [note, setNote] = useState('Wallet top-up');
  const [busy, setBusy] = useState(false);
  const isAdmin = sessionStorage.getItem('tp_role') === 'admin';
  const load = () => Promise.all([api('/api/v1/pilot/users', {}, token), api('/api/v1/pilot/admin/wallets', {}, token)])
    .then(([u, w]) => { setUsers(u); setWallets(Object.fromEntries(w.map(x => [x.owner_vpa || x.vpa_id, x]))); })
    .catch(e => setError(e.message));
  useEffect(() => { load(); }, [token]);

  async function fund(vpa) {
    setBusy(true);
    try {
      await api('/api/v1/pilot/admin/fund', {method: 'POST', body: JSON.stringify({vpa_id: vpa, amount: Number(amount), note,
        idempotency_key: `fund-${crypto.randomUUID ? crypto.randomUUID() : Date.now()}`})}, token);
      setToast(`Added ${money(amount)} to ${vpa}`); setFunding(null); load();
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  const shown = users.filter(u => !q || `${u.full_name} ${u.vpa_id} ${u.email}`.toLowerCase().includes(q.toLowerCase()));
  return <section>
    <div className="section-title"><div><div className="eyebrow">MEMBERS</div></div>
      <label className="acct-search users-search"><Search size={15}/><input value={q} onChange={e => setQ(e.target.value)} placeholder="Search name, Trace.Pay ID or email"/></label></div>
    <div className="panel">
      <div className="cp-table users-table">
        <div className="cp-row head"><span>Participant</span><span>Trace.Pay ID</span><span>Balance</span><span>Joined</span><span></span></div>
        {shown.map(u => { const w = wallets[u.vpa_id]; return <React.Fragment key={u.vpa_id}>
          <div className="cp-row">
            <span className="member-cell"><MemberPhoto vpa={u.vpa_id} name={u.full_name} token={token}/><span><b>{u.full_name}</b><small className="muted">{u.email}</small></span></span>
            <span className="mono">{u.vpa_id}</span>
            <b>{w ? money(w.balance) : '—'}</b>
            <span className="muted">{fmtDate(u.created_at)}</span>
            {isAdmin ? <button className="text-link" onClick={() => setFunding(funding === u.vpa_id ? null : u.vpa_id)}><WalletCards size={14}/> Fund</button> : <span/>}
          </div>
          {funding === u.vpa_id && <div className="fund-row">
            <label>Amount (₹)<input type="number" min="1" max="1000000" value={amount} onChange={e => setAmount(e.target.value)}/></label>
            <label>Note<input value={note} onChange={e => setNote(e.target.value)}/></label>
            <button className="btn" disabled={busy || !(Number(amount) > 0)} onClick={() => fund(u.vpa_id)}>{busy ? 'Adding…' : `Add ${money(amount)}`}</button>
            <span className="gx-fine">Credited to the Trace.Pay wallet ledger.</span>
          </div>}
        </React.Fragment>; })}
        {!shown.length && <p className="gx-fine">No participants yet. People appear here after they create an account and complete their profile in the app.</p>}
      </div>
    </div>
  </section>;
}
