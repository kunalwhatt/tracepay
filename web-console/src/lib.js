export const API = import.meta.env.VITE_API_BASE_URL || 'http://192.168.0.119:8000';

export async function api(path, options = {}, token) {
  const headers = {...(options.headers || {})};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (options.body && !(options.body instanceof FormData)) headers['Content-Type'] = 'application/json';
  const response = await fetch(API + path, {...options, headers});
  if (!response.ok) {
    const detail = await response.json().catch(() => ({}));
    const message = Array.isArray(detail.detail) ? detail.detail.map(d => d.msg).join('; ') : detail.detail;
    throw new Error(message || `Request failed (${response.status})`);
  }
  return response.status === 204 ? null : response.json();
}

const inr = new Intl.NumberFormat('en-IN', {style: 'currency', currency: 'INR', maximumFractionDigits: 2});
export const money = v => inr.format(Number(v || 0));
/** Indian short scale: K (thousand), L (lakh), Cr (crore). The browser's en-IN compact uses "T" for thousand, which reads as trillion. */
export function moneyCompact(v) {
  const n = Number(v || 0), a = Math.abs(n);
  const fmt = (x, unit) => `₹${(Math.round(x * 10) / 10).toLocaleString('en-IN')}${unit}`;
  if (a >= 1e7) return fmt(n / 1e7, ' Cr');
  if (a >= 1e5) return fmt(n / 1e5, ' L');
  if (a >= 1e3) return fmt(n / 1e3, 'K');
  return `₹${Math.round(n).toLocaleString('en-IN')}`;
}
// The pilot is India-based, so times always display in IST regardless of the viewer's device zone.
const TZ = 'Asia/Kolkata';
const dateFmt = new Intl.DateTimeFormat('en-IN', {dateStyle: 'medium', timeStyle: 'short', timeZone: TZ});
const timeFmt = new Intl.DateTimeFormat('en-IN', {hour: '2-digit', minute: '2-digit', day: '2-digit', month: 'short', timeZone: TZ});
const dayFmt = new Intl.DateTimeFormat('en-IN', {day: '2-digit', month: 'short', timeZone: 'UTC'});
export const fmtDate = v => v ? dateFmt.format(new Date(v)) : '—';
export const fmtTime = v => v ? timeFmt.format(new Date(v)) : '—';
export const fmtDay = v => v ? dayFmt.format(new Date(v + 'T00:00:00Z')) : '—';
export function shortId(id, max = 22) {
  const s = String(id || '');
  if (s.length <= max) return s;
  const keep = Math.floor((max - 1) / 2);
  return s.slice(0, keep) + '…' + s.slice(-keep);
}

/** Trace.Pay IDs are always name@tracepay. A bare name gets the suffix; other handles are rejected. */
export function normalizeTracePayId(value) {
  let raw = String(value || '').trim().toLowerCase();
  if (raw.startsWith('upi://') || raw.startsWith('tracepay://')) {
    try { raw = (new URL(raw.replace(/^(upi|tracepay):\/\//, 'https://x/')).searchParams.get('pa') || '').toLowerCase(); } catch { raw = ''; }
  }
  if (raw && !raw.includes('@')) raw += '@tracepay';
  return /^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?@tracepay$/.test(raw) ? raw : null;
}

/** One vocabulary for evidence states across graph, timeline, drawer and legend. */
export const EVIDENCE = {
  observed: {label: 'Source record', short: 'Observed', color: '#5B2EFF', dash: null},
  observed_normalized: {label: 'Source record, normalised', short: 'Normalised', color: '#A88BFF', dash: null},
  ledger_confirmed: {label: 'TraceBank ledger, committed', short: 'Ledger', color: '#4C9A00', dash: null},
  failed_attempt: {label: 'Failed attempt, no value moved', short: 'Failed', color: '#E5482F', dash: '5 5'},
};

export const RISK_LEVELS = [
  ['review', 'Review', '#e5482f'],
  ['caution', 'Caution', '#e3a127'],
  ['no_known_warning', 'No known warning', '#1f9d6c'],
  ['insufficient_information', 'Insufficient information', '#b9b3a9'],
];
