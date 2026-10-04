import React, {useEffect, useRef, useState} from 'react';
import {AlertTriangle, CheckCircle2, CircleHelp, Database, FileSearch2, RotateCcw, Sparkles, Trash2, Upload} from 'lucide-react';
import {api, fmtDate, money, shortId} from './lib.js';
import {openAssistant} from './assistant.jsx';

const PREVIEW_STAGES = [
  {key: 'upload', label: 'Upload', hint: 'Sending the file to the Trace.Pay API'},
  {key: 'read', label: 'Read sheets', hint: 'Opening every sheet and finding the real header row'},
  {key: 'rules', label: 'Detect columns', hint: 'Matching column names with known banking and UPI layouts'},
  {key: 'gemini', label: 'AI agent', hint: 'Gemini proposes column roles when the rules are unsure. It never invents values.'},
  {key: 'review', label: 'Plan ready', hint: 'Check the plan below before anything is saved'},
];
const IMPORT_STAGES = [
  {key: 'validate', label: 'Validate rows', hint: 'Parsing dates, ₹ amounts and Dr/Cr markers, row by row'},
  {key: 'dedupe', label: 'Duplicates & conflicts', hint: 'Skipping rows already imported; keeping contradictions as conflicts'},
  {key: 'save', label: 'Save to PostgreSQL', hint: 'Writing records with file, sheet and row provenance'},
  {key: 'archive', label: 'Archive raw file', hint: 'Keeping the original file in Blob storage'},
  {key: 'done', label: 'Done', hint: 'Records are now available to the graph, accounts and risk checks'},
];
const MODE_FIELDS = {
  transfers: ['sender_id', 'receiver_id', 'amount', 'timestamp', 'date', 'time', 'transaction_id', 'sender_name', 'receiver_name', 'currency'],
  statement: ['date', 'time', 'timestamp', 'description', 'debit_amount', 'credit_amount', 'amount', 'direction', 'counterparty', 'transaction_id', 'account_id', 'currency'],
};
const SOURCE_LABEL = {rule: 'Rule', gemini: 'AI', you: 'You'};
const wait = ms => new Promise(r => setTimeout(r, ms));

function Pipeline({stages, state}) {
  return <ol className="pipe">
    {stages.map((s, i) => {
      const st = state[s.key] || {status: 'waiting'};
      return <li key={s.key} className={`pipe-step ${st.status}`}>
        <div className="pipe-dot">{st.status === 'done' ? <CheckCircle2 size={16}/> : st.status === 'error' ? <AlertTriangle size={15}/> : <span>{i + 1}</span>}</div>
        <div className="pipe-body">
          <div className="pipe-top"><b>{s.label}</b>{st.ms != null && st.status === 'done' && <small>{st.ms < 1 ? '<1' : Math.round(st.ms)} ms</small>}</div>
          <span>{st.detail || s.hint}</span>
          {st.status === 'running' && <i className="pipe-bar"/>}
        </div>
      </li>;
    })}
  </ol>;
}

export default function IngestionPage({token, data, reload, setToast, setError}) {
  const [file, setFile] = useState(null);
  const [drag, setDrag] = useState(false);
  const [useAi, setUseAi] = useState(true);
  const [sourceId, setSourceId] = useState('');
  const [preview, setPreview] = useState(null);
  const [plans, setPlans] = useState({});
  const [phase, setPhase] = useState('idle'); // idle | analysing | review | importing | done
  const [pState, setPState] = useState({});
  const [iState, setIState] = useState({});
  const [result, setResult] = useState(null);
  const [showAll, setShowAll] = useState({});
  const inputRef = useRef(null);
  const role = sessionStorage.getItem('tp_role');

  const pick = f => { if (!f) return; setFile(f); setPreview(null); setResult(null); setPhase('idle'); setPState({}); setIState({}); };

  const planPayload = () => ({sheets: Object.fromEntries(Object.entries(plans).map(([name, p]) => [name, {mode: p.mode, mapping: p.mapping, statement_account: p.statement_account}]))});

  async function analyse(withPlan = false) {
    if (!file) return;
    setPhase('analysing'); setResult(null); setIState({});
    setPState({upload: {status: 'running'}});
    const fd = new FormData();
    fd.append('file', file); fd.append('use_gemini', String(useAi));
    if (withPlan) fd.append('plan', JSON.stringify(planPayload()));
    const started = performance.now();
    try {
      const r = await api('/api/v1/ingestion/preview', {method: 'POST', body: fd}, token);
      const read = r.stages.find(s => s.key === 'read');
      const total = performance.now() - started;
      const gem = r.sheets.map(s => s.plan.gemini || {});
      const rulesMs = r.sheets.reduce((a, s) => a + (s.plan.timings?.rules_ms || 0), 0);
      const gemMs = r.sheets.reduce((a, s) => a + (s.plan.timings?.gemini_ms || 0), 0);
      const steps = [
        ['upload', {status: 'done', ms: Math.max(0, total - (read?.ms || 0) - rulesMs - gemMs), detail: `${file.name} · ${(r.size_bytes / 1024).toFixed(1)} KB sent`}],
        ['read', {status: 'done', ms: read?.ms, detail: `${read?.detail}. Header found on row ${r.sheets.map(s => s.header_row).join(', ')}`}],
        ['rules', {status: 'done', ms: rulesMs, detail: r.sheets.map(s => `${s.name}: ${Object.values(s.plan.source || {}).filter(x => x === 'rule').length} columns recognised`).join(' · ')}],
        ['gemini', gem.some(g => g.used) ? {status: 'done', ms: gemMs, detail: `${gem.find(g => g.used)?.model} filled ${r.sheets.reduce((a, s) => a + Object.values(s.plan.source || {}).filter(x => x === 'gemini').length, 0)} column roles`}
          : gem.some(g => g.error) ? {status: 'error', detail: `Gemini unavailable: ${gem.find(g => g.error).error.slice(0, 140)}`}
          : {status: 'skipped', detail: !useAi ? 'Turned off for this file' : !r.gemini?.enabled ? 'No Gemini key configured on the server' : 'Not needed: the rules understood every column'}],
        ['review', {status: 'done', detail: r.sheets.every(s => s.plan.ready) ? 'Every sheet is ready to import' : 'Some details need your input below'}],
      ];
      for (const [k, v] of steps) { setPState(s => ({...s, [k]: {status: 'running'}})); await wait(260); setPState(s => ({...s, [k]: v})); }
      setPreview(r);
      setPlans(Object.fromEntries(r.sheets.map(s => [s.name, {...s.plan}])));
      setPhase('review');
    } catch (e) {
      setPState(s => ({...s, upload: {status: 'error', detail: e.message}}));
      setPhase('idle'); setError(e.message);
    }
  }

  async function commit() {
    setPhase('importing');
    setIState({validate: {status: 'running', detail: 'Processing rows on the server…'}});
    const fd = new FormData();
    fd.append('file', file); fd.append('use_gemini', String(useAi)); fd.append('source_id', sourceId);
    fd.append('plan', JSON.stringify(planPayload()));
    try {
      const r = await api('/api/v1/ingestion/file', {method: 'POST', body: fd}, token);
      const byKey = Object.fromEntries((r.stages || []).map(s => [s.key, s]));
      for (const k of ['validate', 'dedupe', 'save', 'archive']) {
        setIState(s => ({...s, [k]: {status: 'running'}})); await wait(300);
        setIState(s => ({...s, [k]: {status: k === 'archive' && !r.raw_archived ? 'skipped' : 'done', ms: byKey[k]?.ms, detail: byKey[k]?.detail}}));
      }
      setIState(s => ({...s, done: {status: r.accepted ? 'done' : 'error', detail: `Job JOB-${String(r.job_id).padStart(4, '0')} · ${r.status.replaceAll('_', ' ')}`}}));
      setResult(r); setPhase('done');
      setToast(`Imported ${r.accepted} records${r.duplicates ? `, ${r.duplicates} duplicates skipped` : ''}${r.conflicts ? `, ${r.conflicts} conflicts kept` : ''}`);
      reload();
    } catch (e) {
      setIState(s => ({...s, validate: {status: 'error', detail: e.message}}));
      setPhase('review'); setError(e.message);
    }
  }

  const setPlan = (name, patch) => setPlans(p => ({...p, [name]: {...p[name], ...patch, source: {...p[name].source, ...(patch.mapping ? Object.fromEntries(Object.keys(patch.mapping).map(k => [k, 'you'])) : {})}}}));
  const setField = (name, field, column) => {
    const p = plans[name]; const mapping = {...p.mapping};
    Object.keys(mapping).forEach(k => { if (mapping[k] === column && column) delete mapping[k]; });
    if (column) mapping[field] = column; else delete mapping[field];
    setPlans(ps => ({...ps, [name]: {...p, mapping, source: {...p.source, [field]: 'you'}, edited: true}}));
  };
  const anyEdited = Object.values(plans).some(p => p.edited);
  const anyReady = preview && preview.sheets.some(s => plans[s.name]?.ready && !plans[s.name]?.edited);

  return <section className="ing">
    <div className="section-title"><div><div className="eyebrow">SOURCE-LINKED IMPORT</div></div>
      <div className="ing-help">
        <button className="text-link" onClick={() => openAssistant('ingestion')}><CircleHelp size={15}/> What happens to my file?</button>
        <button className="text-link" onClick={() => openAssistant('statements')}><CircleHelp size={15}/> Bank statements</button>
      </div>
    </div>

    <div className="ing-grid">
      <div className="panel ing-upload">
        <div className={`dropzone ${drag ? 'over' : ''} ${file ? 'has-file' : ''}`}
             onDragOver={e => { e.preventDefault(); setDrag(true); }} onDragLeave={() => setDrag(false)}
             onDrop={e => { e.preventDefault(); setDrag(false); pick(e.dataTransfer.files?.[0]); }}
             onClick={() => inputRef.current?.click()} role="button" tabIndex={0}>
          <Upload size={26}/>
          <b>{file ? file.name : 'Drop a file here, or click to choose'}</b>
          <span>{file ? `${(file.size / 1024).toFixed(1)} KB` : 'Transfer exports, case files, or bank and UPI statements · CSV, TXT, TSV, XLS, XLSX'}</span>
          <input ref={inputRef} type="file" hidden accept=".csv,.txt,.tsv,.xls,.xlsx,.xlsm" onChange={e => pick(e.target.files?.[0])}/>
        </div>
        <label className="ing-field">Source label <input value={sourceId} onChange={e => setSourceId(e.target.value)} placeholder="e.g. hdfc-statement-oct (defaults to the file name)"/></label>
        <label className="ing-toggle"><input type="checkbox" checked={useAi} onChange={e => setUseAi(e.target.checked)}/>
          <span><Sparkles size={14}/> Let the AI agent help with unclear columns</span></label>
        <button className="btn" disabled={!file || phase === 'analysing' || phase === 'importing'} onClick={() => analyse(false)}>
          <FileSearch2 size={16}/> {phase === 'analysing' ? 'Analysing…' : preview ? 'Analyse again' : 'Analyse file'}
        </button>
      </div>
      <div className="panel ing-pipe">
        <div className="panel-head"><h3>Behind the scenes</h3><span className="gx-count">live from the server</span></div>
        <Pipeline stages={PREVIEW_STAGES} state={pState}/>
        {(phase === 'importing' || phase === 'done') && <Pipeline stages={IMPORT_STAGES} state={iState}/>}
        {phase === 'idle' && !Object.keys(pState).length && <p className="gx-fine">Choose a file and press Analyse. Nothing is saved until you press Import.</p>}
      </div>
    </div>

    {preview && preview.sheets.map(sheet => {
      const p = plans[sheet.name] || sheet.plan;
      const fields = showAll[sheet.name] ? Object.keys(preview.fields) : (MODE_FIELDS[p.mode] || Object.keys(preview.fields));
      const columns = sheet.columns.map(c => c.column);
      return <div className="panel ing-sheet" key={sheet.name}>
        <div className="ing-sheet-head">
          <div><h3>{sheet.name === 'csv' ? file?.name : `Sheet: ${sheet.name}`}</h3>
            <span>{sheet.rows} data rows · header on row {sheet.header_row}{sheet.preamble ? ' · preamble detected' : ''}</span></div>
          <span className={`badge ${p.ready && !p.edited ? 'low' : 'review'}`}>{p.edited ? 'EDITED: RE-CHECK' : p.ready ? 'READY' : 'NEEDS INPUT'}</span>
        </div>

        <div className="ing-mode">
          <span>This file is</span>
          {['transfers', 'statement'].map(m => <button key={m} className={p.mode === m ? 'on' : ''} onClick={() => setPlans(ps => ({...ps, [sheet.name]: {...p, mode: m, edited: true}}))}>
            {m === 'transfers' ? 'A list of transfers (sender → receiver)' : "One account's bank / UPI statement"}</button>)}
        </div>
        {p.mode === 'statement' && <label className="ing-field owner">Whose statement is this?
          <input value={p.statement_account || ''} onChange={e => setPlans(ps => ({...ps, [sheet.name]: {...p, statement_account: e.target.value, edited: true}}))}
                 placeholder="Account number or UPI ID of the statement owner, e.g. ravi.kumar@okaxis"/>
          {p.statement_account_source && !p.edited && <small>Found by {p.statement_account_source === 'file' ? 'reading the file header' : p.statement_account_source === 'gemini' ? 'the AI agent (it appears in the file)' : 'you'}</small>}
        </label>}

        {(p.missing || []).length > 0 && <div className="gx-warn"><AlertTriangle size={15}/>Still needed: {p.missing.join(' · ')}</div>}
        {(p.notes || []).concat(p.warnings || []).map((n, i) => <div key={i} className="ing-note"><Sparkles size={13}/>{n}</div>)}

        <div className="ing-map">
          <div className="ing-map-head"><span>Trace.Pay field</span><span>Column in your file</span><span>Chosen by</span></div>
          {fields.map(f => <div className="ing-map-row" key={f}>
            <span><b>{f.replaceAll('_', ' ')}</b><small>{preview.fields[f]}</small></span>
            <select value={p.mapping?.[f] || ''} onChange={e => setField(sheet.name, f, e.target.value)}>
              <option value="">— not used —</option>
              {columns.map(c => <option key={c} value={c}>{c}</option>)}
            </select>
            <span>{p.mapping?.[f] ? <i className={`src ${p.source?.[f]}`}>{SOURCE_LABEL[p.source?.[f]] || 'Rule'}</i> : ''}</span>
          </div>)}
          <button className="text-link" onClick={() => setShowAll(s => ({...s, [sheet.name]: !s[sheet.name]}))}>{showAll[sheet.name] ? 'Show only relevant fields' : 'Show all fields'}</button>
        </div>

        <div className="ing-preview">
          <h4>How the first rows will be imported</h4>
          <div className="ing-table">
            <div className="ing-tr head"><span>Row</span><span>From</span><span>To</span><span>Amount</span><span>When (IST)</span><span>Notes</span></div>
            {sheet.sample.map(r => <div className={`ing-tr ${r.ok ? '' : 'bad'}`} key={r.row}>
              <span>{r.row}</span>
              {r.skipped ? <span className="span5 muted">Blank or summary row: skipped</span> : r.ok ? <>
                <span className="mono">{shortId(r.sender, 26)}</span><span className="mono">{shortId(r.receiver, 26)}</span>
                <b>{money(r.amount)}</b><span>{fmtDate(r.timestamp)}</span><span className="muted">{(r.repairs || []).join('; ') || 'as recorded'}</span>
              </> : <span className="span5 err">{r.error}</span>}
            </div>)}
            {!sheet.sample.length && <div className="ing-tr"><span className="span6 muted">Choose what kind of file this is to see a preview.</span></div>}
          </div>
        </div>
      </div>;
    })}

    {preview && phase !== 'importing' && <div className="ing-actions">
      {anyEdited && <button className="btn light" onClick={() => analyse(true)}><RotateCcw size={15}/> Re-check with my changes</button>}
      <button className="btn" disabled={!anyReady || anyEdited} onClick={commit}><Database size={16}/> Import {preview.sheets.filter(s => plans[s.name]?.ready).length} sheet(s)</button>
      {anyEdited && <span className="gx-fine">Re-check first so you can see the preview with your changes.</span>}
    </div>}

    {result && <div className="panel ing-result">
      <div className="panel-head"><h3>Import result</h3><span className={`badge ${result.status === 'completed' ? 'low' : 'review'}`}>{result.status.replaceAll('_', ' ').toUpperCase()}</span></div>
      <div className="dq-grid five">
        <div><b>{result.accepted}</b><span>saved</span></div><div><b>{result.rejected}</b><span>rejected</span></div>
        <div><b>{result.duplicates}</b><span>duplicates</span></div><div><b>{result.conflicts}</b><span>conflicts kept</span></div>
        <div><b>{result.skipped}</b><span>blank rows skipped</span></div>
      </div>
      {result.errors?.length > 0 && <details className="ing-errors"><summary>{result.errors.length} row message(s)</summary>{result.errors.map((e, i) => <div key={i}>{e}</div>)}</details>}
      <p className="gx-fine">sha256 {result.checksum_sha256?.slice(0, 16)}… · {result.raw_archived ? 'raw file archived' : 'raw file not archived (Blob storage not configured)'}</p>
    </div>}

    <div className="ing-bottom">
      <div className="panel">
        <div className="panel-head"><h3>Import history</h3><span className="gx-count">{(data.jobs || []).length}</span></div>
        <div className="rows">{(data.jobs || []).slice(0, 12).map(j => <div className="job-row" key={j.id}>
          <div><b>JOB-{String(j.id).padStart(4, '0')}</b><span>{j.filename || j.source_id} · {fmtDate(j.created_at)}</span></div>
          <span>{j.accepted}/{j.received} saved{j.duplicates ? `, ${j.duplicates} dup.` : ''}{j.conflicts ? `, ${j.conflicts} conflicts` : ''}</span>
          <span className={`badge ${j.status === 'completed' ? 'low' : 'review'}`}>{j.status.replaceAll('_', ' ')}</span>
        </div>)}{!(data.jobs || []).length && <p className="gx-fine">No imports yet.</p>}</div>
      </div>
      {role === 'admin' && <ResetPanel token={token} reload={reload} setToast={setToast} setError={setError}/>}
    </div>
  </section>;
}

function ResetPanel({token, reload, setToast, setError}) {
  const [scope, setScope] = useState('ingested');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  async function run() {
    setBusy(true);
    try {
      const r = await api('/api/v1/admin/reset', {method: 'POST', body: JSON.stringify({scope, confirm})}, token);
      setToast(`Reset complete: ${Object.entries(r.deleted).map(([k, v]) => `${v} ${k.replaceAll('_', ' ')}`).join(', ')}`);
      setConfirm(''); reload();
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  return <div className="panel reset-panel">
    <div className="panel-head"><h3><Trash2 size={16}/> Reset data</h3><span className="badge high">ADMIN</span></div>
    <label className="ing-radio"><input type="radio" checked={scope === 'ingested'} onChange={() => setScope('ingested')}/>
      <span><b>Imported evidence</b><small>All imported transactions, import jobs, conflicts and risk results</small></span></label>
    <label className="ing-radio"><input type="radio" checked={scope === 'investigation'} onChange={() => setScope('investigation')}/>
      <span><b>Imported evidence + cases and reports</b><small>Everything above, plus every case and report</small></span></label>
    <p className="gx-fine">Always kept: users, profiles, wallets, the TraceBank ledger and the audit log. This cannot be undone.</p>
    <label className="ing-field">Type RESET to confirm<input value={confirm} onChange={e => setConfirm(e.target.value)} placeholder="RESET"/></label>
    <button className="btn danger" disabled={confirm !== 'RESET' || busy} onClick={run}>{busy ? 'Resetting…' : 'Reset now'}</button>
  </div>;
}
