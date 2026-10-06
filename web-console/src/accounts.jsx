import React, {useEffect, useState} from 'react';
import {AlertTriangle, ArrowLeftRight, CheckCircle2, CircleHelp, Crosshair, FileCheck2, Search, Sparkles, Users, XCircle} from 'lucide-react';
import {api, fmtDate, money, shortId} from './lib.js';
import {GroupedBars, VolumeChart} from './charts.jsx';
import {openAssistant} from './assistant.jsx';
import {TraceScorePanel} from './tracescore.jsx';
import {moneyCompact, fmtDay} from './lib.js';

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
      <div><div className="eyebrow">ENTITY VIEW</div></div>
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
        {summary && <AccountDetail s={summary} busy={busy} onTrace={onTrace} token={token}/>}
      </div>
    </div>
  </section>;
}

function Stat({label, value, note}) {
  return <div className="acct-stat"><span>{label}</span><b>{value}</b>{note && <small>{note}</small>}</div>;
}

function AccountDetail({s, busy, onTrace, token}) {
  const rules = s.rules_at_last_activity;
  const report = () => window.dispatchEvent(new CustomEvent('tp-tab', {detail: {tab: 'Reports', account: s.account}}));
  return <div className={`acct-card ${busy ? 'loading' : ''}`}>
    <div className="panel acct-head">
      <div>
        <h3 className="mono">{s.account}</h3>
        <p>Observed from {fmtDate(s.first_seen)} to {fmtDate(s.last_seen)} · {s.record_count} records ({s.ledger_records} from the TraceBank ledger)</p>
      </div>
      <div className="acct-actions">
        {onTrace && <button className="btn" onClick={() => onTrace(s.account)}><Crosshair size={15}/> Trace in graph</button>}
        <button className="btn light" onClick={report}><FileCheck2 size={15}/> Evidence report</button>
        <button className="btn light" onClick={() => openAssistant(null, {account: s.account, question: `Explain what the records show about ${s.account} and why TraceSense Core says ${rules?.level || 'what it says'}.`})}><Sparkles size={15}/> Explain</button>
      </div>
    </div>
    <TraceScorePanel token={token} account={s.account}/>
    {s.plain_summary && <div className="acct-plain"><Sparkles size={15}/><p>{s.plain_summary}</p></div>}
    <div className="acct-stats">
      <Stat label="Received" value={money(s.in_total)} note={`${s.in_count} transfers from ${s.unique_senders} senders`}/>
      <Stat label="Sent" value={money(s.out_total)} note={`${s.out_count} transfers to ${s.unique_receivers} recipients`}/>
      <Stat label="Observed-flow difference" value={money(s.observed_flow_difference)} note="Received minus sent in this data (not missing money)"/>
      <Stat label="Median transfer" value={s.median_amount ? money(s.median_amount) : '—'}/>
      <Stat label="Busiest hour" value={`${s.max_events_in_one_hour} transfers`} note="Most records in any 60 minutes"/>
      <Stat label="Median onward time" value={s.median_onward_minutes != null ? `${s.median_onward_minutes} min` : '—'} note="From last receipt to next send"/>
    </div>

    {rules && <div className="panel acct-rules">
      <div className="panel-head"><h3>Why this risk level?</h3>
        <div className="acct-head-right"><span className={`badge ${LEVEL_TONE[rules.level] || 'neutral'}`}>{rules.level.replaceAll('_', ' ')}</span>
          <button className="text-link" onClick={() => openAssistant('risk', {account: s.account})}><CircleHelp size={14}/> How flagging works</button></div></div>
      <p className="gx-fine">TraceSense Core recomputed for the 24 hours ending {fmtDate(s.last_seen)}. An advisory signal, not a finding of fraud. Two or more triggered rules → review; one → caution.</p>
      <div className="rule-table">
        <div className="rule-row head"><span>Rule</span><span>Triggers when</span><span>Observed</span><span>Result</span></div>
        {(s.rule_table || []).map(r => <div className={`rule-row ${r.triggered ? 'hit' : ''}`} key={r.rule}>
          <b>{r.rule}</b><span>{r.threshold}</span><span>{r.observed}</span>
          <span className="rule-res">{r.triggered ? <><XCircle size={15}/> Triggered</> : <><CheckCircle2 size={15}/> Not triggered</>}</span>
        </div>)}
      </div>
      {rules.evidence?.map(ev => <div key={ev.code} className="acct-evidence">
        <b>{ev.code.replaceAll('_', ' ').toLowerCase()}</b>
        <span>{ev.code === 'RAPID_ONWARD' ? `${ev.first_incoming} received, ${ev.first_onward} sent ${ev.elapsed_minutes} minutes later` : `${ev.observed} counterparties from ${ev.records.length} records`} · records: {ev.records.slice(0, 8).join(', ')}{ev.records.length > 8 ? ' …' : ''}</span>
      </div>)}
      {s.latest_assessment && <p className="gx-fine">Last stored check: {s.latest_assessment.level.replaceAll('_', ' ')} on {fmtDate(s.latest_assessment.assessed_at)}.</p>}
    </div>}

    <div className="panel">
      <div className="panel-head"><h3>Money in and out per day</h3><span className="gx-count">30 days to last activity</span></div>
      <GroupedBars rows={(s.daily_split || []).map(d => ({label: fmtDay(d.date), in: Number(d.in), out: Number(d.out)}))} valueLabel={v => moneyCompact(v)} labelEvery={5}/>
    </div>
    <div className="acct-two">
      <div className="panel"><div className="panel-head"><h3>Time of day</h3><span className="gx-count">transfers per hour, IST</span></div>
        <GroupedBars rows={(s.hourly || []).map(h => ({label: String(h.hour).padStart(2, '0'), in: h.in, out: h.out}))} labelEvery={3} height={150}/></div>
      <div className="panel"><div className="panel-head"><h3>Transfer sizes</h3><span className="gx-count">count by amount</span></div>
        <GroupedBars rows={(s.amount_buckets || []).map(b => ({label: b.label, in: b.in, out: b.out}))} height={150}/></div>
    </div>

    <div className="panel">
      <div className="panel-head"><h3>Counterparties</h3><span className="gx-count">{(s.counterparties || []).length} shown · largest first</span></div>
      <div className="cp-table">
        <div className="cp-row head"><span>Account</span><span>Received from</span><span>Sent to</span><span>First → last</span><span></span></div>
        {(s.counterparties || []).map(c => <div className="cp-row" key={c.account}>
          <span className="mono">{shortId(c.account, 30)}{c.both_ways && <i className="both" title="Money moved in both directions"><ArrowLeftRight size={12}/> both ways</i>}</span>
          <span>{c.received_from_count ? `${money(c.received_from)} · ${c.received_from_count}×` : '—'}</span>
          <span>{c.sent_to_count ? `${money(c.sent_to)} · ${c.sent_to_count}×` : '—'}</span>
          <span className="muted">{fmtDate(c.first)} → {fmtDate(c.last)}</span>
          <button className="text-link" onClick={() => onTrace && onTrace(c.account)}>Trace</button>
        </div>)}
      </div>
    </div>

    <div className="acct-two">
      <div className="panel"><div className="panel-head"><h3>Where the records come from</h3></div>
        <div className="sharebars">{Object.entries(s.sources || {}).map(([k, v]) => <div className="sharebar" key={k}>
          <div className="sharebar-top"><span>{k}</span><b>{v}</b></div>
          <div className="sharebar-track"><i style={{width: `${(v / Math.max(1, s.record_count)) * 100}%`}}/></div></div>)}</div></div>
      <div className="panel"><div className="panel-head"><h3>Daily activity</h3></div><VolumeChart series={s.daily} height={150} mode="count"/></div>
    </div>
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
