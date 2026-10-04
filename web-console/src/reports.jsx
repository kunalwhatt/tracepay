import React, {useEffect, useState} from 'react';
import {AlertTriangle, BriefcaseBusiness, Crosshair, Download, FileCheck2, Plus, Printer, Sparkles, Trash2, Users, X} from 'lucide-react';
import {api, EVIDENCE, fmtDate, money, shortId} from './lib.js';

const LEVEL_TONE = {review: 'high', caution: 'review', no_known_warning: 'low', insufficient_information: 'neutral'};
const goto = (tab, extra = {}) => window.dispatchEvent(new CustomEvent('tp-tab', {detail: {tab, ...extra}}));
const parseBody = r => { try { return r.body?.startsWith('{') ? JSON.parse(r.body) : null; } catch { return null; } };
function download(name, text, type) {
  const url = URL.createObjectURL(new Blob([text], {type}));
  const a = Object.assign(document.createElement('a'), {href: url, download: name});
  document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
const csvCell = v => `"${String(v ?? '').replaceAll('"', '""')}"`;

function useAccounts(token) {
  const [accounts, setAccounts] = useState([]);
  useEffect(() => { api('/api/v1/accounts?limit=300', {}, token).then(setAccounts).catch(() => {}); }, [token]);
  return accounts;
}

// ------------------------------------------------------------------ Reports
export function ReportsPage({token, setToast, setError, initialAccount = '', initialReport = null}) {
  const [reports, setReports] = useState([]);
  const [account, setAccount] = useState(initialAccount);
  const [title, setTitle] = useState('');
  const [hops, setHops] = useState(2);
  const [ai, setAi] = useState(false);
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState(null);
  const accounts = useAccounts(token);
  const load = () => api('/api/v1/reports', {}, token).then(setReports).catch(e => setError(e.message));
  useEffect(() => { load(); }, [token]);
  useEffect(() => { if (initialAccount) setAccount(initialAccount); }, [initialAccount]);
  useEffect(() => { if (initialReport) api(`/api/v1/reports/${initialReport}`, {}, token).then(setOpen).catch(e => setError(e.message)); }, [initialReport]);

  async function generate() {
    setBusy(true);
    try {
      const r = await api('/api/v1/reports/generate', {method: 'POST', body: JSON.stringify({account_ref: account.trim(), title: title.trim() || null, hops, include_ai_summary: ai})}, token);
      setToast(`Report ${r.report_ref} generated`); setOpen(r); setTitle(''); load();
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  async function remove(r) {
    if (!window.confirm(`Delete ${r.report_ref}?`)) return;
    try { await api(`/api/v1/reports/${r.id}`, {method: 'DELETE'}, token); setOpen(null); load(); } catch (e) { setError(e.message); }
  }

  if (open) return <ReportViewer report={open} onClose={() => setOpen(null)} onDelete={() => remove(open)}/>;
  return <section>
    <div className="section-title"><div><div className="eyebrow">EVIDENCE PACKS</div></div></div>
    <div className="rp-layout">
      <div className="panel rp-form">
        <h3>Generate an evidence report</h3>
        <p className="gx-fine">Built only from persisted records: account behaviour, rules-v1 evidence, the transfer network, every transaction with its source file and row, TraceBank transfers and source conflicts.</p>
        <label className="ing-field">Account
          <input list="rp-accounts" value={account} onChange={e => setAccount(e.target.value)} placeholder="e.g. tp.a.collect@tracepay"/>
          <datalist id="rp-accounts">{accounts.map(a => <option key={a.account} value={a.account}>{a.records} records</option>)}</datalist>
        </label>
        <label className="ing-field">Title (optional)<input value={title} onChange={e => setTitle(e.target.value)} placeholder={account ? `Evidence report: ${account}` : 'Evidence report'}/></label>
        <label className="ing-field">Network depth
          <select value={hops} onChange={e => setHops(Number(e.target.value))}>{[1, 2, 3, 4].map(h => <option key={h} value={h}>{h} hop{h > 1 ? 's' : ''}</option>)}</select>
        </label>
        <label className="ing-toggle"><input type="checkbox" checked={ai} onChange={e => setAi(e.target.checked)}/><span><Sparkles size={14}/> Add an AI-written summary (clearly labelled)</span></label>
        <button className="btn" disabled={!account.trim() || busy} onClick={generate}><FileCheck2 size={16}/> {busy ? 'Building report…' : 'Generate report'}</button>
      </div>
      <div className="rp-list">
        {reports.map(r => { const b = parseBody(r); return <button key={r.id} className="panel rp-card" onClick={() => api(`/api/v1/reports/${r.id}`, {}, token).then(setOpen).catch(e => setError(e.message))}>
          <div className="rp-card-top"><b>{r.title}</b>{b?.rules?.level && <span className={`badge ${LEVEL_TONE[b.rules.level]}`}>{b.rules.level.replaceAll('_', ' ')}</span>}</div>
          <span className="mono">{r.report_ref}{r.case_ref ? ` · ${r.case_ref}` : ''}</span>
          <small>{fmtDate(r.created_at)}{b ? ` · ${b.transactions.length} transactions · ${b.network.accounts} accounts in network` : ' · legacy draft'}</small>
        </button>; })}
        {!reports.length && <div className="panel chart-empty">No reports yet. Generate one from any account with records.</div>}
      </div>
    </div>
  </section>;
}

export function ReportViewer({report, onClose, onDelete}) {
  const b = parseBody(report);
  if (!b) return <section className="panel"><button className="text-link" onClick={onClose}>← Back</button><h3>{report.title}</h3><p>{report.body || 'This legacy draft has no content.'}</p></section>;
  const s = b.summary;
  const csv = () => download(`${report.report_ref}-transactions.csv`,
    ['time,from,to,amount,reference,evidence,source,file,sheet,row', ...b.transactions.map(t => [t.time, t.from, t.to, t.amount, t.reference, t.evidence, t.source, t.file, t.sheet, t.row].map(csvCell).join(','))].join('\n'), 'text/csv');
  return <section className="rp-view">
    <div className="rp-toolbar no-print">
      <button className="text-link" onClick={onClose}>← All reports</button>
      <div><button className="btn light" onClick={() => window.print()}><Printer size={15}/> Print / Save PDF</button>
        <button className="btn light" onClick={csv}><Download size={15}/> Transactions CSV</button>
        <button className="btn light" onClick={() => download(`${report.report_ref}.json`, JSON.stringify(b, null, 2), 'application/json')}><Download size={15}/> JSON</button>
        <button className="btn light danger-text" onClick={onDelete}><Trash2 size={15}/> Delete</button></div>
    </div>
    <article className="report-print">
      <header className="rp-head">
        <div><div className="eyebrow">TRACE.PAY EVIDENCE REPORT</div><h2>{report.title}</h2>
          <span>{report.report_ref} · generated {fmtDate(b.generated_at)} · {b.rule_version}{report.case_ref ? ` · ${report.case_ref}` : ''}</span></div>
        <img src={import.meta.env.BASE_URL + 'tracepay-mark.svg'} alt="" width="48" height="48"/>
      </header>
      <h3>1. Account under review</h3>
      <p className="rp-account mono">{b.account}</p>
      <div className="rp-stats">
        <div><span>Received</span><b>{money(s.in_total)}</b><small>{s.in_count} transfers from {s.unique_senders}</small></div>
        <div><span>Sent</span><b>{money(s.out_total)}</b><small>{s.out_count} transfers to {s.unique_receivers}</small></div>
        <div><span>Observed-flow difference</span><b>{money(s.observed_flow_difference)}</b><small>received minus sent in this data</small></div>
        <div><span>Active</span><b>{fmtDate(s.first_seen)}</b><small>to {fmtDate(s.last_seen)}</small></div>
        <div><span>Busiest hour</span><b>{s.max_events_in_one_hour} transfers</b><small>median onward {s.median_onward_minutes ?? '—'} min</small></div>
      </div>
      {b.ai_summary && <div className={`rp-ai ${b.ai_summary.error ? 'err' : ''}`}><Sparkles size={15}/><div>
        {b.ai_summary.text ? <><b>{b.ai_summary.label}</b><p>{b.ai_summary.text}</p><small>{b.ai_summary.model}</small></> : <span>AI summary unavailable: {b.ai_summary.error}</span>}
      </div></div>}
      <h3>2. Advisory risk result (rules-v1)</h3>
      <p><span className={`badge ${LEVEL_TONE[b.rules.level] || 'neutral'}`}>{(b.rules.level || 'no records').replaceAll('_', ' ').toUpperCase()}</span> computed for the 24 hours ending {fmtDate(b.rules.window_end)}.</p>
      <ul>{(b.rules.reasons || []).map((r, i) => <li key={i}>{r}</li>)}</ul>
      {(b.rules.evidence || []).map(e => <div className="acct-evidence" key={e.code}><b>{e.code.replaceAll('_', ' ').toLowerCase()}</b>
        <span>{e.code === 'RAPID_ONWARD' ? `${e.first_incoming} received, ${e.first_onward} sent ${e.elapsed_minutes} min later` : `${e.observed} counterparties (threshold ${e.threshold})`} · records: {e.records.join(', ')}</span></div>)}
      <h3>3. Transfer network ({b.network.hops} hop{b.network.hops > 1 ? 's' : ''})</h3>
      <p>{b.network.accounts} accounts and {b.network.transfers} transfers are linked to this account{b.network.truncated ? ' (limit reached: further links exist)' : ''}.
        Evidence: {Object.entries(b.network.evidence_states || {}).map(([k, v]) => `${v} ${EVIDENCE[k]?.short.toLowerCase() || k}`).join(', ') || 'none'}.</p>
      <div className="acct-two">
        <PartyTable title="Largest senders" rows={b.network.top_senders}/><PartyTable title="Largest recipients" rows={b.network.top_receivers}/>
      </div>
      <h3>4. Source records ({b.transactions.length})</h3>
      <div className="rp-table"><table><thead><tr><th>Time (IST)</th><th>From</th><th>To</th><th>Amount</th><th>Reference</th><th>Evidence</th><th>Source · file · row</th></tr></thead>
        <tbody>{b.transactions.map((t, i) => <tr key={i}><td>{fmtDate(t.time)}</td><td className="mono">{t.from}</td><td className="mono">{t.to}</td><td>{money(t.amount)}</td>
          <td className="mono">{t.reference}</td><td>{EVIDENCE[t.evidence]?.short || t.evidence}</td><td>{[t.source, t.file, t.sheet && `${t.sheet}:${t.row}`].filter(Boolean).join(' · ')}</td></tr>)}</tbody></table></div>
      {b.ledger_transfers.length > 0 && <><h3>5. TraceBank pilot transfers ({b.ledger_transfers.length})</h3>
        <div className="rp-table"><table><thead><tr><th>Time</th><th>From</th><th>To</th><th>Amount</th><th>Reference</th><th>Status</th></tr></thead>
          <tbody>{b.ledger_transfers.map((t, i) => <tr key={i}><td>{fmtDate(t.time)}</td><td className="mono">{t.from}</td><td className="mono">{t.to}</td><td>{money(t.amount)}</td><td className="mono">{t.reference}</td><td>{t.status}</td></tr>)}</tbody></table></div></>}
      <h3>{b.ledger_transfers.length ? 6 : 5}. Source conflicts ({b.conflicts.length})</h3>
      {b.conflicts.length ? b.conflicts.map((c, i) => <div className="gx-warn" key={i}><AlertTriangle size={15}/>{c.reference}: sources disagree on {c.fields}. Incoming version from {c.incoming.source_file || c.incoming.source_id}, row {c.incoming.source_row}.</div>)
        : <p>No source disagreed about these records.</p>}
      <h3>Sources</h3><p>{Object.entries(b.sources).map(([k, v]) => `${k}: ${v} records`).join(' · ') || '—'}</p>
      <h3>Limitations</h3><ul>{b.limitations.map((l, i) => <li key={i}>{l}</li>)}</ul>
    </article>
  </section>;
}
function PartyTable({title, rows = []}) {
  return <div className="rp-mini"><h4>{title}</h4>{rows.length ? rows.map(r => <div key={r.account}><span className="mono">{shortId(r.account, 30)}</span><b>{money(r.volume)}</b><small>{r.count}×</small></div>) : <p className="gx-fine">None</p>}</div>;
}

// ------------------------------------------------------------------ Cases
export function CasesPage({token, setToast, setError}) {
  const [cases, setCases] = useState([]);
  const [reports, setReports] = useState([]);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({title: '', account_ref: '', description: ''});
  const [busyCase, setBusyCase] = useState(null);
  const accounts = useAccounts(token);
  const load = () => Promise.all([api('/api/v1/cases', {}, token), api('/api/v1/reports', {}, token)]).then(([c, r]) => { setCases(c); setReports(r); }).catch(e => setError(e.message));
  useEffect(() => { load(); }, [token]);

  async function create() {
    try { await api('/api/v1/cases', {method: 'POST', body: JSON.stringify({...form, account_ref: form.account_ref || null})}, token);
      setCreating(false); setForm({title: '', account_ref: '', description: ''}); setToast('Case created'); load(); } catch (e) { setError(e.message); }
  }
  async function patch(c, body) { try { await api(`/api/v1/cases/${c.id}`, {method: 'PATCH', body: JSON.stringify(body)}, token); load(); } catch (e) { setError(e.message); } }
  async function report(c) {
    setBusyCase(c.id);
    try { const r = await api('/api/v1/reports/generate', {method: 'POST', body: JSON.stringify({account_ref: c.account_ref, case_ref: c.case_ref, title: `${c.title}: evidence`})}, token);
      setToast(`Report ${r.report_ref} attached to ${c.case_ref}`); load(); } catch (e) { setError(e.message); } finally { setBusyCase(null); }
  }
  const counts = ['OPEN', 'IN_REVIEW', 'CLOSED'].map(s => [s, cases.filter(c => c.status === s).length]);
  return <section>
    <div className="section-title"><div><div className="eyebrow">INVESTIGATIONS</div></div>
      <div className="case-counts">{counts.map(([s, n]) => <span key={s} className="badge neutral">{s.replace('_', ' ')} {n}</span>)}
        <button className="btn" onClick={() => setCreating(true)}><Plus size={15}/> New case</button></div></div>
    {creating && <div className="panel case-form">
      <div className="panel-head"><h3>New case</h3><button className="icon-button" onClick={() => setCreating(false)} aria-label="Close"><X size={16}/></button></div>
      <label className="ing-field">Title<input value={form.title} onChange={e => setForm({...form, title: e.target.value})} placeholder="e.g. Madhapur collection account"/></label>
      <label className="ing-field">Account under investigation
        <input list="case-accounts" value={form.account_ref} onChange={e => setForm({...form, account_ref: e.target.value})} placeholder="e.g. tp.a.collect@tracepay"/>
        <datalist id="case-accounts">{accounts.map(a => <option key={a.account} value={a.account}/>)}</datalist></label>
      <label className="ing-field">Notes<textarea rows={3} value={form.description} onChange={e => setForm({...form, description: e.target.value})} placeholder="Why this case was opened, what to check"/></label>
      <button className="btn" disabled={form.title.trim().length < 2} onClick={create}>Create case</button>
    </div>}
    <div className="case-grid">
      {cases.map(c => { const linked = reports.filter(r => r.case_ref === c.case_ref); return <div className="panel case-card2" key={c.id}>
        <div className="case-top"><span className="mono">{c.case_ref}</span>
          <select value={c.status} onChange={e => patch(c, {status: e.target.value})} aria-label="Case status">{['OPEN', 'IN_REVIEW', 'CLOSED'].map(s => <option key={s} value={s}>{s.replace('_', ' ')}</option>)}</select></div>
        <h3>{c.title}</h3>
        {c.account_ref ? <p className="mono case-acct">{c.account_ref}</p> : <p className="gx-fine">No account linked.</p>}
        {c.description && <p className="case-desc">{c.description}</p>}
        <small>Opened {fmtDate(c.created_at)} · updated {fmtDate(c.updated_at)}</small>
        {c.account_ref && <div className="case-actions">
          <button className="btn light" onClick={() => goto('Account Analysis', {account: c.account_ref})}><Users size={14}/> Account</button>
          <button className="btn light" onClick={() => goto('Graph Analysis', {root: c.account_ref})}><Crosshair size={14}/> Trace</button>
          <button className="btn light" disabled={busyCase === c.id} onClick={() => report(c)}><FileCheck2 size={14}/> {busyCase === c.id ? 'Building…' : 'Add report'}</button>
        </div>}
        {linked.length > 0 && <div className="case-reports">{linked.map(r => <button key={r.id} className="text-link" onClick={() => goto('Reports', {report: r.id})}>{r.report_ref} · {fmtDate(r.created_at)}</button>)}</div>}
      </div>; })}
      {!cases.length && !creating && <div className="panel chart-empty"><BriefcaseBusiness size={20}/> No cases yet. Create one and link the account you are investigating.</div>}
    </div>
  </section>;
}
