import React, {useEffect, useState} from 'react';
import {AlertTriangle, ArrowRight, CheckCircle2, Crosshair, Flag, Megaphone, Radar, ShieldX, Timer} from 'lucide-react';
import {api, fmtDate, money, shortId} from './lib.js';

const goto = (tab, extra = {}) => window.dispatchEvent(new CustomEvent('tp-tab', {detail: {tab, ...extra}}));
const SCAMS = ['task scam', 'investment scam', 'fake job / fee', 'loan app', 'KYC / bank impersonation', 'shopping', 'unknown'];

export default function TraceRankPage({token, setToast, setError}) {
  const [rank, setRank] = useState(null);
  const [complaints, setComplaints] = useState([]);
  const [labels, setLabels] = useState([]);
  const [form, setForm] = useState({victim_name: '', victim_account: '', paid_to: '', amount: '', paid_at: '', scam_type: 'task scam', description: ''});
  const [busy, setBusy] = useState(false);
  const [lastTrace, setLastTrace] = useState(null);
  const load = () => Promise.all([api('/api/v1/tracerank?limit=40', {}, token), api('/api/v1/complaints', {}, token), api('/api/v1/labels', {}, token)])
    .then(([r, c, l]) => { setRank(r); setComplaints(c); setLabels(l); }).catch(e => setError(e.message));
  useEffect(() => { load(); }, [token]);

  async function submit() {
    setBusy(true);
    try {
      const r = await api('/api/v1/complaints', {method: 'POST', body: JSON.stringify({...form, amount: Number(form.amount), paid_at: new Date(form.paid_at).toISOString(), victim_account: form.victim_account || null})}, token);
      setToast(`Complaint ${r.complaint_ref} recorded${r.matched_transaction_key ? ' and matched to a recorded payment' : ''}`);
      setLastTrace(r.trace ? {...r.trace, ref: r.complaint_ref} : null);
      setForm({...form, victim_name: '', victim_account: '', paid_to: '', amount: '', description: ''}); load();
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  async function label(account, value) {
    try { await api('/api/v1/labels', {method: 'POST', body: JSON.stringify({account_ref: account, label: value, reason: value === 'confirmed_fraud' ? 'Confirmed from TraceRank review' : 'Cleared from TraceRank review'})}, token);
      setToast(`${account} marked ${value.replace('_', ' ')}`); load(); } catch (e) { setError(e.message); }
  }
  const valid = form.victim_name.trim().length > 1 && form.paid_to.trim() && Number(form.amount) > 0 && form.paid_at;
  return <section className="trk">
    <div className="section-title"><div><div className="eyebrow">SUSPICION PROPAGATION</div></div></div>
    <div className="trk-grid">
      <div className="panel trk-form fade-up">
        <h3><Megaphone size={17}/> Record a victim complaint</h3>
        <p className="gx-fine">A complaint marks the account that was paid as a starting point. If the payment is in the records, TraceFlow follows the money straight away.</p>
        <label className="ing-field">Victim name<input value={form.victim_name} onChange={e => setForm({...form, victim_name: e.target.value})} placeholder="Full name"/></label>
        <div className="trk-two">
          <label className="ing-field">Victim's account (optional)<input value={form.victim_account} onChange={e => setForm({...form, victim_account: e.target.value})} placeholder="e.g. victim@oksbi"/></label>
          <label className="ing-field">Paid to<input value={form.paid_to} onChange={e => setForm({...form, paid_to: e.target.value})} placeholder="Account or UPI ID paid"/></label>
        </div>
        <div className="trk-two">
          <label className="ing-field">Amount (₹)<input type="number" min="1" value={form.amount} onChange={e => setForm({...form, amount: e.target.value})}/></label>
          <label className="ing-field">When<input type="datetime-local" value={form.paid_at} onChange={e => setForm({...form, paid_at: e.target.value})}/></label>
        </div>
        <label className="ing-field">Scam type<select value={form.scam_type} onChange={e => setForm({...form, scam_type: e.target.value})}>{SCAMS.map(s => <option key={s}>{s}</option>)}</select></label>
        <label className="ing-field">What happened<textarea rows={2} value={form.description} onChange={e => setForm({...form, description: e.target.value})}/></label>
        <button className="btn" disabled={!valid || busy} onClick={submit}><Flag size={15}/> {busy ? 'Recording and tracing…' : 'Record complaint'}</button>
        {lastTrace && <div className="trk-trace fade-up">
          <div className="gh-ring"><Timer size={18}/><b>{lastTrace.golden_hour.within_golden_hour ? 'Inside the golden hour' : `${Math.round(lastTrace.golden_hour.elapsed_minutes)} min since payment`}</b></div>
          <p><b>{money(lastTrace.golden_hour.recoverable_amount)}</b> of the reported money has not reached a cash-out point.</p>
          {lastTrace.hold_list.slice(0, 3).map(h => <div className="hold-row" key={h.account}><i>{h.priority}</i><span className="mono">{shortId(h.account, 28)}</span><b>{money(h.traced_funds_now)}</b></div>)}
        </div>}
      </div>
      <div className="panel trk-rank fade-up">
        <div className="panel-head"><h3><Radar size={17}/> TraceRank</h3><span className="gx-count">{rank?.seeds?.length || 0} seed(s) · {rank?.cleared?.length || 0} cleared</span></div>
        {!rank && <div className="skel-lines"><i/><i/><i/><i/><i/></div>}
        {rank && !rank.ranking.length && <div className="chart-empty"><Radar size={20}/> {rank.note || 'No connected accounts yet.'}</div>}
        {rank?.ranking.map((r, i) => <div className="trk-row" key={r.account} style={{animationDelay: `${i * 35}ms`}}>
          <span className="trk-pos">{i + 1}</span>
          <div className="trk-main">
            <div className="trk-top"><b className="mono">{shortId(r.account, 32)}</b><div className="trk-meter"><i style={{width: `${r.rank * 100}%`}}/></div><small>{Math.round(r.rank * 100)}</small></div>
            <div className="trk-path">{r.path.map((p, j) => <React.Fragment key={j}>{j > 0 && <ArrowRight size={11}/>}<span className={j === 0 ? 'seed' : ''}>{shortId(p, 18)}</span></React.Fragment>)}</div>
          </div>
          <div className="trk-actions">
            <button title="Trace" onClick={() => goto('Graph Analysis', {root: r.account})}><Crosshair size={14}/></button>
            <button title="Confirm fraud" className="bad" onClick={() => label(r.account, 'confirmed_fraud')}><ShieldX size={14}/></button>
            <button title="Not suspicious" className="ok" onClick={() => label(r.account, 'not_suspicious')}><CheckCircle2 size={14}/></button>
          </div>
        </div>)}
        <p className="gx-fine">Suspicion flows from confirmed fraud and complaints through money transfers and weakens with every hop. Clearing an account stops it spreading through that account.</p>
      </div>
    </div>
    <div className="trk-grid two">
      <div className="panel"><div className="panel-head"><h3>Complaints</h3><span className="gx-count">{complaints.length}</span></div>
        {complaints.map(c => <div className="trk-item" key={c.id}><AlertTriangle size={15}/><div><b>{c.victim_name}</b> paid <span className="mono">{c.paid_to}</span> {money(c.amount)}<small>{c.scam_type} · {fmtDate(c.paid_at)} · {c.matched_transaction_key ? 'matched to a record' : 'no matching record yet'}</small></div></div>)}
        {!complaints.length && <p className="gx-fine">No complaints recorded.</p>}</div>
      <div className="panel"><div className="panel-head"><h3>Investigator decisions</h3><span className="gx-count">{labels.length}</span></div>
        {labels.map(l => <div className="trk-item" key={l.account_ref}>{l.label === 'confirmed_fraud' ? <ShieldX size={15} color="#B3261E"/> : <CheckCircle2 size={15} color="#4C9A00"/>}<div><span className="mono">{l.account_ref}</span> · {l.label.replace('_', ' ')}<small>{l.reason} · {fmtDate(l.updated_at)}</small></div>
          <button className="text-link" onClick={() => api(`/api/v1/labels/${encodeURIComponent(l.account_ref)}`, {method: 'DELETE'}, token).then(load)}>Undo</button></div>)}
        {!labels.length && <p className="gx-fine">Confirm or clear accounts from the ranking to teach TraceRank.</p>}</div>
    </div>
  </section>;
}
