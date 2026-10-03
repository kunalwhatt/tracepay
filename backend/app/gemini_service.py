from __future__ import annotations

import json
import os
from typing import Any

try:
    from google import genai
    GEMINI_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover
    genai = None
    GEMINI_IMPORT_ERROR = exc


def enabled() -> bool:
    return bool(os.getenv("GEMINI_API_KEY", "").strip()) and os.getenv("GEMINI_ENABLED", "true").lower() in {"1", "true", "yes", "on"}


def suggest_mapping(columns: list[str], sample_rows: list[dict[str, Any]]) -> dict[str, Any]:
    if not enabled() or genai is None:
        return {"enabled": False, "mapping": {}, "repairs": [], "message": "Gemini mapping is disabled or google-genai is unavailable."}
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    model = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
    prompt = f"""
You are a data-ingestion assistant for Trace.Pay. Do NOT invent transaction values.
Infer only a column mapping and safe normalization suggestions from the provided headers and sample rows.
Canonical fields: transaction_id, event_id, sender_id, receiver_id, amount, currency, timestamp, source_record_ref.
Return JSON only. Do not fabricate missing sender, receiver, amount or timestamp values.
Headers: {json.dumps(columns)}
Sample rows: {json.dumps(sample_rows, default=str)}
"""
    schema = {
        "type": "object",
        "properties": {
            "mapping": {"type": "object", "additionalProperties": {"type": "string"}},
            "repairs": {"type": "array", "items": {"type": "string"}},
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["mapping", "repairs", "warnings"],
    }
    response = client.models.generate_content(
        model=model,
        contents=prompt,
        config={"response_mime_type": "application/json", "response_schema": schema},
    )
    try:
        return {"enabled": True, **json.loads(response.text)}
    except Exception:
        return {"enabled": True, "mapping": {}, "repairs": [], "warnings": ["Gemini returned an invalid structured response."]}
