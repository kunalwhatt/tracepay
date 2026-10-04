import React, {useEffect, useRef, useState} from 'react';
import {ArrowRight, BookOpen, CircleHelp, Send, Sparkles, X} from 'lucide-react';
import {api, EVIDENCE} from './lib.js';

/** Open the assistant on a topic from anywhere: openAssistant('hops') or openAssistant(null, {question, account}). */
export function openAssistant(topic, extra = {}) {
  window.dispatchEvent(new CustomEvent('tp-assistant', {detail: {topic, ...extra}}));
}

// ---- tiny, safe markdown renderer (bold, italic, code, headings, lists, paragraphs) ----
function inline(text, key) {
  const parts = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`|_[^_]+_)/g;
  let last = 0, m, i = 0;
  while ((m = re.exec(text))) {
    if (m.index > last) parts.push(text.slice(last, m.index));
    const t = m[0];
    if (t.startsWith('**')) parts.push(<b key={`${key}-${i++}`}>{t.slice(2, -2)}</b>);
    else if (t.startsWith('`')) parts.push(<code key={`${key}-${i++}`}>{t.slice(1, -1)}</code>);
    else parts.push(<em key={`${key}-${i++}`}>{t.slice(1, -1)}</em>);
    last = m.index + t.length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return parts;
}
export function Md({text = ''}) {
  const blocks = [];
  let list = null;
  text.split('\n').forEach((raw, idx) => {
    const line = raw.trimEnd();
    const item = line.match(/^\s*(?:[-*]|\d+\.)\s+(.*)$/);
    if (item) { (list ||= []).push(<li key={idx}>{inline(item[1], idx)}</li>); return; }
    if (list) { blocks.push(<ul key={`l${idx}`}>{list}</ul>); list = null; }
    if (!line.trim()) return;
    const h = line.match(/^#{1,4}\s+(.*)$/);
    blocks.push(h ? <h4 key={idx}>{inline(h[1], idx)}</h4> : <p key={idx}>{inline(line, idx)}</p>);
  });
  if (list) blocks.push(<ul key="lend">{list}</ul>);
  return <div className="md">{blocks}</div>;
}

function Table({table}) {
  if (!table) return null;
  return <div className="as-table">
    {table.title && <h5>{table.title}</h5>}
    <div className="as-table-scroll"><table><thead><tr>{table.columns.map((c, i) => <th key={i}>{c}</th>)}</tr></thead>
      <tbody>{table.rows.map((r, i) => <tr key={i}>{r.map((c, j) => <td key={j}>{String(c)}</td>)}</tr>)}</tbody></table></div>
  </div>;
}

// ---- diagrams ----
function HopsDiagram() {
  const nodes = [['V1', 'victim'], ['TP-A', 'traced'], ['TP-B', ''], ['TP-E', ''], ['ATM', '']];
  const labels = ['1 hop before', 'Traced account', '1 hop after', '2 hops after', '3 hops after'];
  return <svg viewBox="0 0 520 120" className="as-diagram" role="img" aria-label="Hop diagram">
    <defs><marker id="as-arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto"><path d="M0,1 L10,5 L0,9 z" fill="#5B2EFF"/></marker></defs>
    {nodes.map(([n, kind], i) => <g key={n} transform={`translate(${52 + i * 104},48)`}>
      {i < nodes.length - 1 && <line x1="36" y1="0" x2="66" y2="0" stroke="#5B2EFF" strokeWidth="2.5" markerEnd="url(#as-arr)"/>}
      <rect x="-36" y="-17" width="72" height="34" rx="17" fill={kind === 'traced' ? '#C6FF3D' : '#DDD3FF'} stroke={kind === 'traced' ? '#9fd61f' : '#C9BBFF'}/>
      <text textAnchor="middle" y="4" fontSize="12" fontWeight="700" fill="#14092E">{n}</text>
      <text textAnchor="middle" y="44" fontSize="10" fill="#5E5480">{labels[i]}</text>
    </g>)}
  </svg>;
}
function RiskDiagram() {
  const rules = ['Inbound breadth ≥ 5 senders', 'Outbound breadth ≥ 5 recipients', 'Onward within 30 min'];
  const outs = [['0 signals', 'No known warning', '#1f9d6c'], ['1 signal', 'Caution', '#e3a127'], ['2+ signals', 'Review', '#e5482f']];
  return <svg viewBox="0 0 520 170" className="as-diagram" role="img" aria-label="Risk decision diagram">
    <text x="10" y="16" fontSize="11" fontWeight="700" fill="#5E5480">LAST 24 HOURS OF RECORDS</text>
    {rules.map((r, i) => <g key={r} transform={`translate(10,${30 + i * 44})`}>
      <rect width="210" height="34" rx="12" fill="#fff" stroke="#DDD3FF"/><text x="12" y="21" fontSize="12" fill="#14092E">{r}</text>
      <path d={`M210,17 C250,17 250,${70 - i * 44 + 17} 280,${70 - i * 44 + 17}`} fill="none" stroke="#C9BBFF" strokeWidth="2"/>
    </g>)}
    <rect x="280" y="72" width="80" height="34" rx="12" fill="#5B2EFF"/><text x="320" y="93" textAnchor="middle" fontSize="12" fontWeight="700" fill="#fff">Count</text>
    {outs.map(([k, v, c], i) => <g key={k} transform={`translate(380,${30 + i * 44})`}>
      <path d={`M-20,${89 - 30 - i * 44} C-10,${89 - 30 - i * 44} -10,17 0,17`} fill="none" stroke="#C9BBFF" strokeWidth="2"/>
      <rect width="130" height="34" rx="12" fill="#fff" stroke={c} strokeWidth="1.5"/>
      <text x="10" y="14" fontSize="9.5" fill="#5E5480">{k}</text><text x="10" y="27" fontSize="12" fontWeight="700" fill={c}>{v}</text>
    </g>)}
  </svg>;
}
function EvidenceDiagram() {
  return <div className="as-legend">{Object.values(EVIDENCE).map(s => <div key={s.label}>
    <svg width="54" height="10"><line x1="2" y1="5" x2="52" y2="5" stroke={s.color} strokeWidth="3" strokeDasharray={s.dash || undefined}/></svg>{s.label}</div>)}</div>;
}
function PipelineDiagram() {
  const steps = ['Read', 'Detect', 'AI agent', 'Review', 'Validate', 'Deduplicate', 'Save'];
  return <div className="as-steps">{steps.map((s, i) => <React.Fragment key={s}><span className={s === 'AI agent' ? 'ai' : ''}>{s}</span>{i < steps.length - 1 && <ArrowRight size={13}/>}</React.Fragment>)}</div>;
}
const DIAGRAMS = {hops: HopsDiagram, risk: RiskDiagram, evidence: EvidenceDiagram, ingestion: PipelineDiagram};

export default function Assistant({token, tab, focusAccount}) {
  const [open, setOpen] = useState(false);
  const [view, setView] = useState('learn');
  const [topics, setTopics] = useState(null);
  const [gemini, setGemini] = useState(null);
  const [topic, setTopic] = useState(null);
  const [account, setAccount] = useState('');
  const [question, setQuestion] = useState('');
  const [thread, setThread] = useState([]);
  const [busy, setBusy] = useState(false);
  const endRef = useRef(null);

  useEffect(() => {
    const onOpen = e => {
      const d = e.detail || {};
      setOpen(true);
      if (d.account) setAccount(d.account);
      if (d.topic) { setView('learn'); setTopic(d.topic); }
      if (d.question) { setView('ask'); ask(d.question, d.account); }
    };
    window.addEventListener('tp-assistant', onOpen);
    return () => window.removeEventListener('tp-assistant', onOpen);
  }, [token]);
  useEffect(() => { if (open && !topics) api('/api/v1/assistant/topics', {}, token).then(r => { setTopics(r.topics); setGemini(r.gemini); }).catch(() => setTopics({})); }, [open]);
  useEffect(() => { if (focusAccount) setAccount(focusAccount); }, [focusAccount]);
  useEffect(() => { endRef.current?.scrollIntoView({behavior: 'smooth'}); }, [thread, busy]);

  async function ask(q = question, acct = account) {
    const text = (q || '').trim();
    if (!text) return;
    setThread(t => [...t, {role: 'you', text}]); setQuestion(''); setBusy(true);
    try {
      const r = await api('/api/v1/assistant/ask', {method: 'POST', body: JSON.stringify({question: text, account_ref: acct || null, screen: tab})}, token);
      setThread(t => [...t, {role: 'ai', ...r}]);
    } catch (e) { setThread(t => [...t, {role: 'ai', answer: `_Could not get an answer: ${e.message}_`}]); }
    finally { setBusy(false); }
  }

  const t = topic && topics?.[topic];
  const Diagram = topic && DIAGRAMS[topic];
  return <>
    <button className="as-fab" onClick={() => setOpen(o => !o)} aria-label="Open the Trace.Pay assistant"><Sparkles size={18}/> <span>Ask Trace.Pay</span></button>
    {open && <aside className="as-panel" aria-label="Trace.Pay assistant">
      <div className="as-head">
        <div><b>Trace.Pay assistant</b><small>{gemini?.enabled ? `AI answers by Gemini · ${gemini.model}` : 'Built-in explanations · add a Gemini key for AI answers'}</small></div>
        <button onClick={() => setOpen(false)} aria-label="Close"><X size={18}/></button>
      </div>
      <div className="as-tabs">
        <button className={view === 'learn' ? 'on' : ''} onClick={() => setView('learn')}><BookOpen size={14}/> Learn</button>
        <button className={view === 'ask' ? 'on' : ''} onClick={() => setView('ask')}><Sparkles size={14}/> Ask</button>
      </div>
      {view === 'learn' && <div className="as-body">
        {!t && <div className="as-topics">{topics ? Object.entries(topics).map(([k, v]) => <button key={k} onClick={() => setTopic(k)}><CircleHelp size={15}/>{v.title}<ArrowRight size={14}/></button>) : <p className="gx-fine">Loading…</p>}</div>}
        {t && <div className="as-topic">
          <button className="text-link" onClick={() => setTopic(null)}>← All topics</button>
          <h3>{t.title}</h3>
          {Diagram && <Diagram/>}
          <Md text={t.body}/>
          <Table table={t.table}/>
          <button className="btn light" onClick={() => { setView('ask'); ask(`Explain "${t.title}" using ${account ? `the account ${account}` : 'a simple example'}.`); }}><Sparkles size={14}/> Explain with {account ? 'this account' : 'an example'}</button>
        </div>}
      </div>}
      {view === 'ask' && <div className="as-body as-chat">
        <label className="as-context">About account <input value={account} onChange={e => setAccount(e.target.value)} placeholder="optional, e.g. tp.a.collect@tracepay"/></label>
        {!thread.length && <div className="as-suggest">{['Why is this account flagged?', 'What does a hop mean in this graph?', 'Which counterparties matter most here?', 'How were the columns of my file understood?']
          .map(s => <button key={s} onClick={() => ask(s)}>{s}</button>)}</div>}
        {thread.map((m, i) => m.role === 'you'
          ? <div key={i} className="as-msg you">{m.text}</div>
          : <div key={i} className="as-msg ai">
              <Md text={m.answer}/><Table table={m.table}/>
              {m.source && <small className="as-src">{m.source === 'gemini' ? `Answered by ${m.model} from live Trace.Pay data` : 'Built-in explanation'}</small>}
              {m.follow_ups?.length > 0 && <div className="as-suggest">{m.follow_ups.map(f => <button key={f} onClick={() => ask(f)}>{f}</button>)}</div>}
            </div>)}
        {busy && <div className="as-msg ai typing"><i/><i/><i/></div>}
        <div ref={endRef}/>
        <form className="as-input" onSubmit={e => { e.preventDefault(); ask(); }}>
          <input value={question} onChange={e => setQuestion(e.target.value)} placeholder="Ask about hops, risk, an account, your file…"/>
          <button className="btn" disabled={busy || !question.trim()} aria-label="Send"><Send size={15}/></button>
        </form>
      </div>}
    </aside>}
  </>;
}
