from __future__ import annotations

import os
from datetime import datetime, timezone
from uuid import uuid4

try:
    from azure.identity import DefaultAzureCredential
    from azure.storage.blob import BlobServiceClient, ContentSettings
except Exception:  # pragma: no cover
    DefaultAzureCredential = None
    BlobServiceClient = None


def enabled() -> bool:
    return bool(os.getenv("AZURE_STORAGE_ACCOUNT_URL", "").strip()) and BlobServiceClient is not None and DefaultAzureCredential is not None


def upload_raw(filename: str, raw: bytes, content_type: str | None = None) -> str | None:
    if not enabled():
        return None
    client = BlobServiceClient(os.environ["AZURE_STORAGE_ACCOUNT_URL"], credential=DefaultAzureCredential())
    container = os.getenv("AZURE_INGESTION_CONTAINER", "tracepay-ingestion")
    name = f"{datetime.now(timezone.utc):%Y/%m/%d}/{uuid4().hex}_{filename.replace('/', '_')}"
    blob = client.get_blob_client(container=container, blob=name)
    blob.upload_blob(raw, overwrite=False, content_settings=ContentSettings(content_type=content_type) if content_type else None)
    return blob.url
