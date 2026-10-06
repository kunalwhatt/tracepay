"""AI integration for Trace.Pay (Claude API and Gemini).

Providers: Claude (ANTHROPIC_API_KEY, CLAUDE_MODEL) and Gemini (GEMINI_API_KEY, GEMINI_MODEL).
AI_PROVIDER=auto (default) tries Claude first when its key is set, then Gemini; "claude" or "gemini"
uses only that provider. The module keeps its historical name so existing imports keep working.

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

try:
    import anthropic
    ANTHROPIC_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover
    anthropic = None
    ANTHROPIC_IMPORT_ERROR = exc

CLAUDE_FALLBACK_MODELS = ["claude-haiku-4-5-20251001", "claude-sonnet-5-5"]
FALLBACK_MODELS = ["gemini-flash-latest", "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.0-flash"]
TRANSIENT = ("503", "UNAVAILABLE", "429", "RESOURCE_EXHAUSTED", "overloaded", "high demand")


def _gemini_enabled() -> bool:
    return bool(os.getenv("GEMINI_API_KEY", "").strip()) and os.getenv("GEMINI_ENABLED", "true").lower() in {"1", "true", "yes", "on"}


def _claude_enabled() -> bool:
    return bool(os.getenv("ANTHROPIC_API_KEY", "").strip())


def providers() -> list[str]:
    choice = os.getenv("AI_PROVIDER", "auto").strip().lower()
    available = [p for p, ok in (("claude", _claude_enabled()), ("gemini", _gemini_enabled())) if ok]
    if choice in ("claude", "gemini"):
        return [choice] if choice in available else []
    return available


def enabled() -> bool:
    return bool(providers())


def _models(provider: str = "gemini") -> list[str]:
    preferred = os.getenv("CLAUDE_MODEL" if provider == "claude" else "GEMINI_MODEL", "").strip()
    fallbacks = CLAUDE_FALLBACK_MODELS if provider == "claude" else FALLBACK_MODELS
    seen, out = set(), []
    for m in ([preferred] if preferred else []) + fallbacks:
        if m and m not in seen:
            seen.add(m); out.append(m)
    return out


def status() -> dict[str, Any]:
    order = providers()
    first = order[0] if order else None
    return {"enabled": bool(order), "provider": first, "providers": order,
            "model": _models(first)[0] if first else None,
            "sdk_available": {"claude": anthropic is not None, "gemini": genai is not None}}


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


def _gemini_json(prompt: str) -> dict[str, Any]:
    if genai is None:
        return {"ok": False, "error": f"google-genai is not installed: {GEMINI_IMPORT_ERROR}"}
    import time
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    errors = []
    for model in _models("gemini"):
        for attempt in range(2):
            try:
                response = client.models.generate_content(model=model, contents=prompt,
                                                          config={"response_mime_type": "application/json", "temperature": 0.1})
                data = _parse_json(response.text)
                if not isinstance(data, dict):
                    raise ValueError("response was not a JSON object")
                return {"ok": True, "data": data, "model": model}
            except Exception as exc:  # noqa: BLE001
                message = str(exc)
                transient = any(t in message for t in TRANSIENT)
                if transient and attempt == 0:
                    time.sleep(1.5); continue
                errors.append(f"{model}: {'busy' if transient else type(exc).__name__}: {message[:120]}")
                break
    return {"ok": False, "error": " | ".join(errors)}


def _claude_json(prompt: str) -> dict[str, Any]:
    if anthropic is None:
        return {"ok": False, "error": f"anthropic SDK is not installed: {ANTHROPIC_IMPORT_ERROR}"}
    import time
    client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    errors = []
    for model in _models("claude"):
        for attempt in range(2):
            try:
                response = client.messages.create(
                    model=model, max_tokens=2048, temperature=0.1,
                    system="You are a component of the Trace.Pay system. Reply with one JSON object only, no prose and no code fences.",
                    messages=[{"role": "user", "content": prompt}])
                text = "".join(getattr(block, "text", "") for block in response.content)
                data = _parse_json(text)
                if not isinstance(data, dict):
                    raise ValueError("response was not a JSON object")
                return {"ok": True, "data": data, "model": model}
            except Exception as exc:  # noqa: BLE001
                message = str(exc)
                transient = any(t in message for t in TRANSIENT + ("529", "overloaded_error", "Overloaded"))
                if transient and attempt == 0:
                    time.sleep(1.5); continue
                errors.append(f"{model}: {'busy' if transient else type(exc).__name__}: {message[:120]}")
                break
    return {"ok": False, "error": " | ".join(errors)}


def generate_json(prompt: str) -> dict[str, Any]:
    """Ask the configured AI provider(s) for a JSON object. Returns {"ok", "data", "model", "provider", "error"}."""
    order = providers()
    if not order:
        return {"ok": False, "error": "No AI provider is configured (set ANTHROPIC_API_KEY and/or GEMINI_API_KEY)."}
    errors = []
    for provider in order:
        result = _claude_json(prompt) if provider == "claude" else _gemini_json(prompt)
        if result["ok"]:
            return {**result, "provider": provider}
        errors.append(f"{provider}: {result['error']}")
    return {"ok": False, "error": " || ".join(errors)}


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
    return {"ok": True, "model": result["model"], "provider": result.get("provider"), "dataset_type": data.get("dataset_type"), "mapping": mapping,
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
