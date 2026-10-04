"""Gemini integration for Trace.Pay.

Gemini is used in two places, both strictly bounded:

* the ingestion schema agent asks it which *column* holds which field, and what kind of dataset a
  file is. It never supplies transaction values; every suggestion is validated against the file.
* the console assistant asks it to explain screens and evidence using only facts the API passes in.

The model is configurable with GEMINI_MODEL. If that model is unavailable, a short list of
fallbacks is tried, and the error is reported to the caller instead of being swallowed.
"""
from __future__ import annotations

import json
import os
import re
from typing import Any

try:
    from google import genai
    GEMINI_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover
    genai = None
    GEMINI_IMPORT_ERROR = exc

FALLBACK_MODELS = ["gemini-flash-latest", "gemini-2.5-flash"]


def enabled() -> bool:
    return bool(os.getenv("GEMINI_API_KEY", "").strip()) and os.getenv("GEMINI_ENABLED", "true").lower() in {"1", "true", "yes", "on"}


def status() -> dict[str, Any]:
    return {"enabled": enabled(), "sdk_available": genai is not None, "model": os.getenv("GEMINI_MODEL", "") or FALLBACK_MODELS[0]}


def _models() -> list[str]:
    preferred = os.getenv("GEMINI_MODEL", "").strip()
    seen, out = set(), []
    for m in ([preferred] if preferred else []) + FALLBACK_MODELS:
        if m and m not in seen:
            seen.add(m); out.append(m)
    return out


def _parse_json(text: str) -> Any:
    text = (text or "").strip()
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text, flags=re.S)
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, flags=re.S)
        if match:
            return json.loads(match.group(0))
        raise


def generate_json(prompt: str) -> dict[str, Any]:
    """Ask Gemini for a JSON object. Returns {"ok", "data", "model", "error"}."""
    if not enabled():
        return {"ok": False, "error": "Gemini is not configured (set GEMINI_API_KEY and GEMINI_ENABLED=true)."}
    if genai is None:
        return {"ok": False, "error": f"google-genai is not installed: {GEMINI_IMPORT_ERROR}"}
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    errors = []
    for model in _models():
        try:
            response = client.models.generate_content(model=model, contents=prompt,
                                                      config={"response_mime_type": "application/json", "temperature": 0.1})
            data = _parse_json(response.text)
            if not isinstance(data, dict):
                raise ValueError("response was not a JSON object")
            return {"ok": True, "data": data, "model": model}
        except Exception as exc:  # noqa: BLE001 - reported to the caller
            errors.append(f"{model}: {type(exc).__name__}: {str(exc)[:160]}")
    return {"ok": False, "error": " | ".join(errors)}


def suggest_plan(columns: list[str], sample_rows: list[dict[str, Any]], preamble: str, filename: str,
                 field_help: dict[str, str]) -> dict[str, Any]:
    prompt = f"""You are the schema agent of Trace.Pay, a fund-flow tracing system. Decide how a real-world
transaction file maps to Trace.Pay fields. You map COLUMN NAMES ONLY. Never invent values.

Dataset types:
- "transfers": one row per transfer with a sender and a receiver column.
- "statement": one account's bank/UPI statement (date, narration, withdrawal/deposit or amount + Dr/Cr).
- "unsupported": not transaction data.

Fields you may map (field: meaning):
{json.dumps(field_help, indent=1)}

Rules:
- Every value in "mapping" must be one of these exact column names: {json.dumps(columns)}
- Map each column to at most one field. Leave a field out if no column fits.
- A running balance column is NOT an amount. Do not map it.
- If the statement owner's account number or UPI ID is written in the preamble or filename, copy it
  exactly into "statement_account"; otherwise use "".

File name: {filename}
Preamble text above the header row: {preamble[:1500]!r}
First rows: {json.dumps(sample_rows, default=str)[:6000]}

Reply with JSON only, exactly this shape:
{{"dataset_type": "transfers|statement|unsupported", "mapping": [{{"field": "...", "column": "..."}}],
 "statement_account": "", "notes": ["short reasons"], "warnings": ["anything the analyst should check"]}}"""
    result = generate_json(prompt)
    if not result["ok"]:
        return {"ok": False, "error": result["error"]}
    data = result["data"]
    raw_mapping = data.get("mapping") or []
    mapping: dict[str, str] = {}
    if isinstance(raw_mapping, dict):
        mapping = {str(k): str(v) for k, v in raw_mapping.items()}
    else:
        for item in raw_mapping:
            if isinstance(item, dict) and item.get("field") and item.get("column"):
                mapping[str(item["field"])] = str(item["column"])
    return {"ok": True, "model": result["model"], "dataset_type": data.get("dataset_type"), "mapping": mapping,
            "statement_account": str(data.get("statement_account") or ""), "notes": [str(n) for n in data.get("notes") or []],
            "warnings": [str(w) for w in data.get("warnings") or []]}


def answer(question: str, knowledge: str, facts: dict[str, Any]) -> dict[str, Any]:
    prompt = f"""You are the investigator assistant inside the Trace.Pay console. Explain clearly and briefly
for an analyst who may be new to fund-flow tracing. Use ONLY the knowledge and facts below. If the facts do
not answer the question, say what is missing. Never claim fraud: rules are advisories, not findings.
Use Indian rupee formatting (₹) and IST times where relevant.

Knowledge about how Trace.Pay works:
{knowledge}

Facts from the live system (JSON):
{json.dumps(facts, default=str)[:12000]}

Question: {question}

Reply with JSON only:
{{"answer": "markdown, at most about 180 words",
 "table": {{"title": "", "columns": ["..."], "rows": [["..."]]}} or null,
 "follow_ups": ["up to 3 short follow-up questions"]}}"""
    result = generate_json(prompt)
    if not result["ok"]:
        return {"ok": False, "error": result["error"]}
    data = result["data"]
    table = data.get("table")
    if not (isinstance(table, dict) and isinstance(table.get("columns"), list) and isinstance(table.get("rows"), list)):
        table = None
    return {"ok": True, "model": result["model"], "answer": str(data.get("answer") or ""), "table": table,
            "follow_ups": [str(f) for f in (data.get("follow_ups") or [])][:3]}


def summarize_report(facts: dict[str, Any]) -> dict[str, Any]:
    prompt = f"""Write a neutral 4-6 sentence investigator summary of this Trace.Pay evidence report.
Use only these facts. State what was observed, what the advisory rules flagged and why, and what is unknown.
Do not say anyone committed fraud. Facts: {json.dumps(facts, default=str)[:10000]}
Reply with JSON only: {{"summary": "..."}}"""
    result = generate_json(prompt)
    if not result["ok"]:
        return {"ok": False, "error": result["error"]}
    return {"ok": True, "model": result["model"], "summary": str(result["data"].get("summary") or "")}


def suggest_mapping(columns: list[str], sample_rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Backward-compatible wrapper used by older callers."""
    result = suggest_plan(columns, sample_rows, "", "", {})
    return {"enabled": enabled(), "mapping": result.get("mapping", {}), "repairs": [], "warnings": result.get("warnings", [result.get("error", "")])}
