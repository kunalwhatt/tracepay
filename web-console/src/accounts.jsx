import React, {useEffect, useState} from 'react';
import {AlertTriangle, Crosshair, Search, Users} from 'lucide-react';
import {api, fmtDate, money, shortId} from './lib.js';
import {VolumeChart} from './charts.jsx';

const LEVEL_TONE = {review: 'high', caution: 'review', no_known_warning: 'low', insufficient_information: 'neutral'};

export default function AccountAnalysis({token, initialAccount = '', onTrace}) {
  const [query, setQuery] = useState('');
  const [accounts, setAccounts] = useState([]);
  const [active, setActive] = useState(initialAccount);
  const [summary, setSummary] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    const id = setTimeout(() => {
      api(`/api/v1/accounts?limit=80${query ? `&q=${encodeURIComponent(query)}` : ''}`, {}, token)
        .then(rows => { setAccounts(rows); if (!active && rows[0]) setActive(rows[0].account); })
        .catch(e => setError(e.message));
    }, 220);
    return () => clearTimeout(id);
  }, [query, token]);

  useEffect(() => { if (initialAccount) setActive(initialAccount); }, [initialAccount]);

  useEffect(() => {
    if (!active) return;
    setBusy(true); setError('');
    api(`/api/v1/accounts/${encodeURIComponent(active)}/summary`, {}, token)
      .then(setSummary).catch(e => setError(e.message)).finally(() => setBusy(false));
  }, [active, token]);

  return <section>
    <div className="section-title">
      <div><div className="eyebrow">ENTITY VIEW</div><h2>Account analysis</h2></div>
      <span className="badge neutral">{accounts.length} accounts in persisted records</span>
    </div>
    <div className="acct-layout">
      <div className="panel acct-list">
        <label className="acct-search"><Search size={15}/><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Find an account" aria-label="Find an account"/></label>
        <div className="acct-rows">
          {accounts.map(a => <button key={a.account} className={a.account === active ? 'on' : ''} onClick={() => setActive(a.account)}>
            <span className="mono">{shortId(a.account, 30)}</span>
            <small>{a.records} records, {money(a.volume)}</small>
          </button>)}
          {!accounts.length && <div className="chart-empty">No accounts yet. They appear once records are ingested or TraceBank transfers succeed.</div>}
        </div>
      </div>
      <div className="acct-detail">
        {error && <div className="gx-error"><AlertTriangle size={16}/>{error}</div>}
        {!summary && !busy && !error && <div className="panel chart-empty"><Users size={22}/> Choose an account to see its observed behaviour.</div>}
        {summary && <AccountDetail s={summary} busy={busy} onTrace={onTrace}/>}
      </div>
    </div>
  </section>;
}

function Stat({label, value, note}) {
  return <div className="acct-stat"><span>{label}</span><b>{value}</b>{note && <small>{note}</small>}</div>;
}

function AccountDetail({s, busy, onTrace}) {
  const rules = s.rules_at_last_activity;
  return <div className={`acct-card ${busy ? 'loading' : ''}`}>
    <div className="panel acct-head">
      <div>
        <h3 className="mono">{s.account}</h3>
        <p>Observed from {fmtDate(s.first_seen)} to {fmtDate(s.last_seen)}, {s.record_count} records ({s.ledger_records} from the TraceBank ledger).</p>
      </div>
      {onTrace && <button className="btn" onClick={() => onTrace(s.account)}><Crosshair size={15}/> Trace in graph</button>}
    </div>
    <div className="acct-stats">
      <Stat label="Received" value={money(s.in_total)} note={`${s.in_count} transfers from ${s.unique_senders} senders`}/>
      <Stat label="Sent" value={money(s.out_total)} note={`${s.out_count} transfers to ${s.unique_receivers} recipients`}/>
      <Stat label="Observed-flow difference" value={money(s.observed_flow_difference)} note="Received minus sent in the data"/>
      <Stat label="Median transfer" value={s.median_amount ? money(s.median_amount) : '—'}/>
      <Stat label="Busiest hour" value={`${s.max_events_in_one_hour} transfers`} note="Most records in any 60 minutes"/>
      <Stat label="Median onward time" value={s.median_onward_minutes != null ? `${s.median_onward_minutes} min` : '—'} note="From last receipt to next send"/>
    </div>
    <div className="panel">
      <div className="panel-head"><h3>Daily activity</h3><span className="gx-count">30 days to last activity</span></div>
      <VolumeChart series={s.daily} height={170}/>
    </div>
    <div className="acct-two">
      <Counterparties title="Largest senders" rows={s.top_senders} empty="No incoming transfers observed."/>
      <Counterparties title="Largest recipients" rows={s.top_receivers} empty="No outgoing transfers observed."/>
    </div>
    {rules && <div className="panel acct-rules">
      <div className="panel-head"><h3>rules-v1 at last observed activity</h3><span className={`badge ${LEVEL_TONE[rules.level] || 'neutral'}`}>{rules.level.replaceAll('_', ' ')}</span></div>
      <p className="gx-fine">Recomputed for the 24 hours ending {fmtDate(s.last_seen)}. Not stored and not shown to payers. An advisory signal, not a finding of fraud.</p>
      <ul className="acct-reasons">
        {rules.reasons.map((r, i) => <li key={i}>{r}</li>)}
      </ul>
      {rules.evidence?.map(ev => <div key={ev.code} className="acct-evidence">
        <b>{ev.code.replaceAll('_', ' ').toLowerCase()}</b>
        <span>{ev.code === 'RAPID_ONWARD'
          ? `${ev.first_incoming} received, ${ev.first_onward} sent ${ev.elapsed_minutes} minutes later`
          : `${ev.observed} counterparties (threshold ${ev.threshold}), from ${ev.records.length} records`}</span>
      </div>)}
      {s.latest_assessment && <p className="gx-fine">Last stored assessment: {s.latest_assessment.level.replaceAll('_', ' ')} on {fmtDate(s.latest_assessment.assessed_at)} ({s.latest_assessment.rule_version}).</p>}
    </div>}
  </div>;
}

function Counterparties({title, rows, empty}) {
  const max = Math.max(1, ...rows.map(r => Number(r.volume)));
  return <div className="panel">
    <div className="panel-head"><h3>{title}</h3></div>
    {rows.length ? <div className="sharebars">{rows.map(r => <div key={r.account} className="sharebar">
      <div className="sharebar-top"><span className="mono">{shortId(r.account, 28)}</span><b>{money(r.volume)}</b></div>
      <div className="sharebar-track"><i style={{width: `${(Number(r.volume) / max) * 100}%`}}/></div>
      <small>{r.count} transfer{r.count === 1 ? '' : 's'}</small>
    </div>)}</div> : <div className="chart-empty">{empty}</div>}
  </div>;
}
