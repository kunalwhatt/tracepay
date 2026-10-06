import time
import csv, io, json, os, secrets
from datetime import datetime, timezone, date, timedelta
from decimal import Decimal, InvalidOperation
from uuid import uuid4
from pydantic import BaseModel, Field, field_validator
import re, random
import redis
import base64, hashlib
from cryptography.fernet import Fernet, InvalidToken
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, WebSocket, WebSocketDisconnect, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, desc, func, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from fastapi.responses import Response
from pathlib import Path
import cv2, numpy as np, jwt
from .db import Base, engine, get_db, SessionLocal
from .models import User, Transaction, IngestionJob, AuditEvent, RiskAssessment, PaymentIntent, PilotProfile, PilotMerchant, PilotTransfer, PilotWallet, PilotLedgerEntry, InvestigationCase, InvestigationReport, SourceConflict, Complaint, AccountLabel
from .schemas import RegisterIn, LoginIn, TokenOut, UserOut, RiskIn, RiskOut, TransactionOut, IngestionOut, PaymentIntentIn, PaymentIntentOut, CaseIn, CaseOut, ReportIn, ReportOut
from .security import hash_password, verify_password, create_token, renew_token, current_user, require_roles, security as bearer_scheme
from .engine import assess_recipient, graph_for_account, summarize_account, network_timeseries, collect_neighbourhood, recent_movements, _movements_for
from . import traceflow, tracesense, tracerank, tracebench
from .ingestion_service import read_upload, deterministic_mapping, normalize_row, sample_for_ai
from .gemini_service import suggest_mapping, enabled as gemini_enabled, status as gemini_status
from . import schema_agent, assistant as tp_assistant
from .blob_service import upload_raw as upload_raw_blob
from .ids import normalize_tracepay_id

APP_VERSION = "5.1.0"
OPS_ROLES = ("admin", "analyst", "reviewer")
app = FastAPI(title="Trace.Pay API", version=APP_VERSION, description="Trace.Pay identity, evidence-aware risk and transaction intelligence API.")
redis_client = redis.Redis.from_url(os.getenv("REDIS_URL", "redis://redis:6379/0"), decode_responses=True, socket_connect_timeout=1, socket_timeout=1)
# Derive an at-rest PII key from an optional dedicated secret or JWT_SECRET.
# Keep the source secret stable across restarts or previously encrypted fields cannot be decrypted.
_pii_material = (os.getenv("PII_ENCRYPTION_KEY") or os.environ["JWT_SECRET"]).encode()
_pii_fernet = Fernet(base64.urlsafe_b64encode(hashlib.sha256(_pii_material).digest()))
def protect_pii(value: str) -> str:
    return "enc:v1:" + _pii_fernet.encrypt(value.encode()).decode() if value else ""
def reveal_pii(value: str) -> str:
    if not value or not value.startswith("enc:v1:"): return value or ""
    try: return _pii_fernet.decrypt(value[7:].encode()).decode()
    except InvalidToken: return "[unavailable]"

class PilotProfileIn(BaseModel):
    full_name: str = Field(min_length=2, max_length=160)
    date_of_birth: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    # Server assigns a unique pilot ID; any client-provided value is ignored.
    vpa_id: str | None = Field(default=None, min_length=3, max_length=255)
    bank_name: str = Field(default="", max_length=120)
    account_last4: str = Field(default="", pattern=r"^$|^\d{4}$")
    participant_type: str = Field(default="pilot_user", pattern=r"^pilot_user$")
    consent_profile: bool
    consent_pilot_ledger: bool

    @field_validator("date_of_birth")
    @classmethod
    def validate_dob(cls, value):
        try: parsed = date.fromisoformat(value)
        except ValueError: raise ValueError("Date of birth must be a valid YYYY-MM-DD date")
        if parsed > date.today(): raise ValueError("Date of birth cannot be in the future")
        return value

    @field_validator("vpa_id")
    @classmethod
    def normalize_vpa(cls, value):
        return None if value is None else normalize_tracepay_id(value)

class MerchantIn(BaseModel):
    display_name: str = Field(min_length=2, max_length=160)
    vpa_id: str = Field(min_length=2, max_length=255)

    @field_validator("vpa_id")
    @classmethod
    def tracepay_only(cls, value): return normalize_tracepay_id(value)
    category: str = Field(default="General", max_length=80)
    location: str = Field(default="", max_length=160)

class GeneratePilotTransfersIn(BaseModel):
    count: int = Field(default=10, ge=1, le=100)
    min_amount: Decimal = Field(default=Decimal("50"), gt=0, le=100000)
    max_amount: Decimal = Field(default=Decimal("1500"), gt=0, le=100000)

class AdminPilotTransferIn(BaseModel):
    sender_vpa: str = Field(min_length=2, max_length=255)
    receiver_vpa: str = Field(min_length=2, max_length=255)

    @field_validator("sender_vpa", "receiver_vpa")
    @classmethod
    def tracepay_only(cls, value): return normalize_tracepay_id(value)
    amount: Decimal = Field(gt=0, le=100000)
    note: str = Field(default="", max_length=255)
    idempotency_key: str = Field(min_length=8, max_length=100)

class PilotTransferIn(BaseModel):
    receiver_vpa: str = Field(min_length=2, max_length=255)
    amount: Decimal = Field(gt=0, le=100000)
    note: str = Field(default="", max_length=255)
    idempotency_key: str = Field(min_length=8, max_length=100)

    @field_validator("receiver_vpa")
    @classmethod
    def normalize_receiver(cls, value):
        return normalize_tracepay_id(value)

def pilot_profile_json(profile, user_email=None, include_private=False):
    result = {"id": profile.id, "user_id": profile.user_id, "email": user_email, "full_name": reveal_pii(profile.full_name),
        "vpa_id": profile.vpa_id, "bank_name": reveal_pii(profile.bank_name),
        "account_last4": reveal_pii(profile.account_last4), "participant_type": profile.participant_type,
        "selfie_status": profile.selfie_status, "gender": getattr(profile, "gender", "Prefer not to say"), "face_count": getattr(profile, "face_count", 0), "created_at": profile.created_at.isoformat()}
    if include_private: result["date_of_birth"] = reveal_pii(profile.date_of_birth)
    return result

def generate_pilot_vpa(db: Session, user: User, full_name: str) -> str:
    """Generate a readable, unique Trace.Pay handle from the participant's chosen display name."""
    import unicodedata
    ascii_name = unicodedata.normalize("NFKD", full_name).encode("ascii", "ignore").decode()
    base = re.sub(r"[^a-z0-9]+", ".", ascii_name.lower()).strip(".")
    base = re.sub(r"\.+", ".", base)[:36].strip(".") or f"member{user.id}"
    candidate = f"{base}@tracepay"
    suffix = 2
    while (db.scalar(select(PilotProfile.id).where(PilotProfile.vpa_id == candidate)) or
           db.scalar(select(PilotMerchant.id).where(PilotMerchant.vpa_id == candidate))):
        tail = f".{suffix}"
        candidate = f"{base[:max(1, 36-len(tail))]}{tail}@tracepay"
        suffix += 1
    return candidate


def activity_event(db: Session, *, actor_user_id: int | None, event_type: str, object_ref: str | None = None, details: dict | None = None):
    """Persist a minimal audit event. Never send passwords, tokens, DOB or raw form contents."""
    safe_details = details or {}
    row = AuditEvent(actor_user_id=actor_user_id, action=event_type[:128], object_ref=(object_ref or "")[:255] or None,
                     detail=json.dumps(safe_details, separators=(",", ":"))[:4000])
    db.add(row)
    db.commit()
    db.refresh(row)
    return row

def pilot_transfer_json(t):
    return {"id": t.id, "transfer_ref": t.transfer_ref, "sender_vpa": t.sender_vpa, "receiver_vpa": t.receiver_vpa,
        "amount": str(t.amount), "currency": "INR", "note": t.note, "status": t.status, "mode": t.mode,
        "created_at": t.created_at.isoformat(), "settled": t.status == "SUCCESS",
        "failure_reason": getattr(t, "failure_reason", "") or None,
        "disclaimer": "Trace.Pay internal ledger transfer. External bank settlement is not connected."}

def ensure_wallet(db: Session, vpa: str) -> PilotWallet:
    wallet = db.scalar(select(PilotWallet).where(PilotWallet.owner_vpa == vpa))
    if wallet:
        return wallet
    wallet = PilotWallet(owner_vpa=vpa, balance=Decimal("0.00"), currency="INR", status="active")
    db.add(wallet)
    db.flush()
    return wallet

def wallet_json(wallet: PilotWallet):
    return {"wallet_id": wallet.id, "vpa_id": wallet.owner_vpa, "balance": str(wallet.balance),
        "currency": wallet.currency, "status": wallet.status, "ledger_type": "TRACEPAY_INTERNAL_LEDGER",
        "disclaimer": "Trace.Pay internal ledger balance. External bank settlement is not connected."}

def execute_ledger_transfer(db: Session, *, sender_vpa: str, receiver_vpa: str, amount: Decimal,
                            note: str, sender_user_id: int, idempotency_key: str, actor_user_id: int | None = None):
    """Post both sides atomically; failed insufficient-funds attempts are persisted as FAILED."""
    prior = db.scalar(select(PilotTransfer).where(PilotTransfer.sender_user_id == sender_user_id,
        PilotTransfer.idempotency_key == idempotency_key))
    if prior:
        return prior
    # Stable lock order reduces deadlocks under concurrent payments.
    ensure_wallet(db, sender_vpa)
    ensure_wallet(db, receiver_vpa)
    db.flush()
    wallets = list(db.scalars(select(PilotWallet).where(PilotWallet.owner_vpa.in_([sender_vpa, receiver_vpa]))
                              .order_by(PilotWallet.owner_vpa).with_for_update()).all())
    by_vpa = {w.owner_vpa: w for w in wallets}
    sender, receiver = by_vpa[sender_vpa], by_vpa[receiver_vpa]
    transfer = PilotTransfer(transfer_ref="TB-" + uuid4().hex[:16].upper(), sender_user_id=sender_user_id,
        sender_vpa=sender_vpa, receiver_vpa=receiver_vpa, amount=amount, note=note.strip(),
        status="FAILED", mode="tracebank_internal_ledger", idempotency_key=idempotency_key)
    db.add(transfer)
    db.flush()
    if sender.status != "active" or receiver.status != "active":
        transfer.status = "FAILED"
        failure_reason = "One of the Trace.Pay accounts is inactive."
    elif Decimal(str(sender.balance)) < amount:
        transfer.status = "FAILED"
        failure_reason = "Insufficient Trace.Pay balance. No ledger value was moved."
    else:
        sender.balance = (Decimal(str(sender.balance)) - amount).quantize(Decimal("0.01"))
        receiver.balance = (Decimal(str(receiver.balance)) + amount).quantize(Decimal("0.01"))
        db.add(PilotLedgerEntry(transfer_ref=transfer.transfer_ref, wallet_vpa=sender_vpa, direction="DEBIT",
            amount=amount, balance_after=sender.balance))
        db.add(PilotLedgerEntry(transfer_ref=transfer.transfer_ref, wallet_vpa=receiver_vpa, direction="CREDIT",
            amount=amount, balance_after=receiver.balance))
        transfer.status = "SUCCESS"
        failure_reason = ""
    transfer.failure_reason = failure_reason
    db.add(AuditEvent(actor_user_id=actor_user_id or sender_user_id,
        action="tracebank.transfer." + transfer.status.lower(), object_ref=transfer.transfer_ref,
        detail=(f"{sender_vpa} -> {receiver_vpa}; INR {amount}; status={transfer.status}; " + failure_reason)))
    db.commit()
    db.refresh(transfer)
    return transfer

origins = [x.strip() for x in os.getenv("CORS_ORIGINS", "http://localhost:5173").split(",") if x.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins, allow_credentials=True, allow_methods=["GET", "POST", "OPTIONS"], allow_headers=["Authorization", "Content-Type"])

LIVE_CHANNEL = "tracepay:live"
REPLICA_ID = uuid4().hex


class LiveHub:
    """Authenticated WebSocket fan-out.

    Operations roles receive every event. Pilot users only receive events addressed to their own
    Trace.Pay ID, so one participant can never watch another participant's transfers.
    """
    def __init__(self): self.clients: dict[WebSocket, dict] = {}
    async def connect(self, ws, *, user_id: int, role: str, vpa: str | None):
        await ws.accept(); self.clients[ws] = {"user_id": user_id, "role": role, "vpa": vpa}
    def disconnect(self, ws): self.clients.pop(ws, None)
    async def publish(self, event, *, vpas: set[str] | None = None):
        """Deliver locally, and relay through Redis so clients connected to other API replicas get it too."""
        await self.deliver(event, vpas)
        try:
            from redis import asyncio as aioredis
            if not hasattr(self, "_redis"):
                self._redis = aioredis.Redis.from_url(os.getenv("REDIS_URL", "redis://redis:6379/0"), socket_connect_timeout=1, socket_timeout=1)
            await self._redis.publish(LIVE_CHANNEL, json.dumps({"origin": REPLICA_ID, "event": event, "vpas": sorted(vpas) if vpas is not None else None}, default=str))
        except Exception:
            pass  # Redis is coordination only; local delivery already happened.

    async def relay_forever(self):
        """Receive events published by other replicas. Restarts quietly if Redis is unavailable."""
        import asyncio
        from redis import asyncio as aioredis
        while True:
            try:
                client = aioredis.Redis.from_url(os.getenv("REDIS_URL", "redis://redis:6379/0"))
                pubsub = client.pubsub()
                await pubsub.subscribe(LIVE_CHANNEL)
                async for message in pubsub.listen():
                    if message.get("type") != "message":
                        continue
                    data = json.loads(message["data"])
                    if data.get("origin") == REPLICA_ID:
                        continue
                    vpas = set(data["vpas"]) if data.get("vpas") is not None else None
                    await self.deliver(data["event"], vpas)
            except asyncio.CancelledError:
                raise
            except Exception:
                await asyncio.sleep(5)

    async def deliver(self, event, vpas: set[str] | None = None):
        dead = []
        for ws, who in list(self.clients.items()):
            allowed = who["role"] in OPS_ROLES or (vpas is not None and who["vpa"] in vpas)
            if not allowed:
                continue
            try: await ws.send_json(event)
            except Exception: dead.append(ws)
        for ws in dead: self.disconnect(ws)
hub = LiveHub()

@app.on_event("startup")
async def start_live_relay():
    import asyncio
    app.state.live_relay = asyncio.create_task(hub.relay_forever())


@app.on_event("startup")
def startup():
    Base.metadata.create_all(bind=engine)
    # Backwards-compatible schema evolution for existing local installations.
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE pilot_profiles ADD COLUMN IF NOT EXISTS gender VARCHAR(32) NOT NULL DEFAULT 'Prefer not to say'"))
        conn.execute(text("ALTER TABLE pilot_profiles ADD COLUMN IF NOT EXISTS photo_storage_key TEXT"))
        conn.execute(text("ALTER TABLE pilot_profiles ADD COLUMN IF NOT EXISTS face_count INTEGER NOT NULL DEFAULT 0"))
        # 4.2.0 provenance, evidence and conflict columns for installations created by earlier versions.
        for statement in (
            "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS ingestion_job_id INTEGER",
            "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS source_file VARCHAR(255)",
            "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS source_sheet VARCHAR(128)",
            "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS source_row INTEGER",
            "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS fingerprint VARCHAR(64)",
            "CREATE INDEX IF NOT EXISTS ix_transactions_ingestion_job_id ON transactions (ingestion_job_id)",
            "CREATE INDEX IF NOT EXISTS ix_transactions_fingerprint ON transactions (fingerprint)",
            "CREATE INDEX IF NOT EXISTS ix_tx_receiver_time ON transactions (receiver_id, occurred_at)",
            "ALTER TABLE ingestion_jobs ADD COLUMN IF NOT EXISTS conflicts INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE ingestion_jobs ADD COLUMN IF NOT EXISTS filename VARCHAR(255)",
            "ALTER TABLE ingestion_jobs ADD COLUMN IF NOT EXISTS checksum_sha256 VARCHAR(64)",
            "ALTER TABLE ingestion_jobs ADD COLUMN IF NOT EXISTS raw_blob_url TEXT",
            "ALTER TABLE risk_assessments ADD COLUMN IF NOT EXISTS evidence_json TEXT NOT NULL DEFAULT '[]'",
            "ALTER TABLE risk_assessments ADD COLUMN IF NOT EXISTS window_start TIMESTAMPTZ",
            "ALTER TABLE risk_assessments ADD COLUMN IF NOT EXISTS window_end TIMESTAMPTZ",
            "ALTER TABLE pilot_transfers ADD COLUMN IF NOT EXISTS failure_reason TEXT NOT NULL DEFAULT ''",
            "ALTER TABLE investigation_cases ADD COLUMN IF NOT EXISTS account_ref VARCHAR(255)",
        ):
            conn.execute(text(statement))
    Path(os.getenv("PRIVATE_PHOTO_DIR", "/var/lib/tracepay/private-photos")).mkdir(parents=True, exist_ok=True)
    # Fernet-encrypted PII is longer than plaintext. Keep legacy databases compatible too.
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE pilot_profiles ALTER COLUMN full_name TYPE TEXT, ALTER COLUMN date_of_birth TYPE TEXT, ALTER COLUMN bank_name TYPE TEXT, ALTER COLUMN account_last4 TYPE TEXT"))
    email = os.getenv("BOOTSTRAP_ADMIN_EMAIL", "").strip().lower()
    password = os.getenv("BOOTSTRAP_ADMIN_PASSWORD", "")
    if email and password:
        with SessionLocal() as db:
            if not db.scalar(select(User).where(User.email == email)):
                db.add(User(email=email, password_hash=hash_password(password), role="admin")); db.commit()

@app.get("/health")
def health(): return {"status": "ok", "service": "tracepay-api", "version": APP_VERSION, "data_mode": "database-backed", "time": datetime.now(timezone.utc).isoformat()}

@app.post("/api/v1/auth/register", response_model=UserOut, status_code=201)
def register(body: RegisterIn, db: Session = Depends(get_db)):
    email = body.email.lower()
    if db.scalar(select(User).where(User.email == email)): raise HTTPException(409, "An account with this email already exists")
    # Self-registration is analyst-only. Elevated roles are assigned out-of-band by an administrator.
    user = User(email=email, password_hash=hash_password(body.password), role="pilot_user")
    db.add(user)
    try: db.commit()
    except IntegrityError: db.rollback(); raise HTTPException(409, "Account already exists")
    db.refresh(user)
    db.add(AuditEvent(actor_user_id=user.id, action="auth.register", object_ref=str(user.id))); db.commit()
    return user

@app.post("/api/v1/auth/login", response_model=TokenOut)
def login(body: LoginIn, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == body.email.lower()))
    if not user or not user.active or not verify_password(body.password, user.password_hash):
        raise HTTPException(401, "Invalid email or password")
    db.add(AuditEvent(actor_user_id=user.id, action="auth.login", object_ref=str(user.id))); db.commit()
    return TokenOut(access_token=create_token(user), role=user.role)

@app.post("/api/v1/auth/refresh", response_model=TokenOut)
def refresh_token(user: User = Depends(current_user), credentials=Depends(bearer_scheme)):
    """Renew a still-valid access token. Expired tokens cannot be renewed; sessions end 12 hours after sign-in."""
    return TokenOut(access_token=renew_token(user, credentials.credentials), role=user.role)

@app.get("/api/v1/auth/me", response_model=UserOut)
def me(user: User = Depends(current_user)): return user



@app.get("/api/v1/cases", response_model=list[CaseOut])
def list_cases(limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst", "reviewer"))):
    return list(db.scalars(select(InvestigationCase).order_by(desc(InvestigationCase.updated_at)).limit(limit)))

@app.post("/api/v1/cases", response_model=CaseOut, status_code=201)
def create_case(body: CaseIn, db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst", "reviewer"))):
    case = InvestigationCase(case_ref="CASE-" + uuid4().hex[:12].upper(), title=body.title.strip(), description=body.description.strip(),
                             account_ref=(body.account_ref or "").strip() or None, created_by=user.id)
    db.add(case); db.flush(); db.add(AuditEvent(actor_user_id=user.id, action="case.created", object_ref=case.case_ref)); db.commit(); db.refresh(case); return case

@app.get("/api/v1/reports", response_model=list[ReportOut])
def list_reports(limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst", "reviewer"))):
    return list(db.scalars(select(InvestigationReport).order_by(desc(InvestigationReport.created_at)).limit(limit)))

@app.post("/api/v1/reports", response_model=ReportOut, status_code=201)
def create_report(body: ReportIn, db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst", "reviewer"))):
    report = InvestigationReport(report_ref="RPT-" + uuid4().hex[:12].upper(), title=body.title.strip(), report_type=body.report_type.strip(), case_ref=body.case_ref.strip() if body.case_ref else None, body=body.body, created_by=user.id)
    db.add(report); db.flush(); db.add(AuditEvent(actor_user_id=user.id, action="report.created", object_ref=report.report_ref)); db.commit(); db.refresh(report); return report

def trace_shield(db: Session, user: User, recipient: str, amount: Decimal | None) -> dict:
    """TraceShield: payer-specific warnings shown before a payment, each with a plain reason. Advisory only."""
    reasons: list[dict] = []
    payer_vpa = db.scalar(select(PilotProfile.vpa_id).where(PilotProfile.user_id == user.id))
    mine = _movements_for(db, {payer_vpa}, include_failed=False) if payer_vpa else []
    paid_before = any(m.sender == payer_vpa and m.receiver == recipient for m in mine)
    if payer_vpa and not paid_before:
        reasons.append({"code": "FIRST_TIME_PAYEE", "severity": 1, "text": "You have never paid this account before."})
    sent = [m.amount for m in mine if m.sender == payer_vpa]
    if amount and sent:
        usual = sorted(sent)[len(sent) // 2]
        if usual > 0 and amount >= usual * 5 and amount >= 2000:
            reasons.append({"code": "UNUSUAL_AMOUNT", "severity": 2, "text": f"This is {int(amount / usual)}× your usual payment of ₹{usual}."})
    rec = _movements_for(db, {recipient}, include_failed=False)
    if rec:
        first_seen = min(m.at for m in rec)
        if datetime.now(timezone.utc) - first_seen <= timedelta(days=7):
            reasons.append({"code": "NEW_ACCOUNT", "severity": 1, "text": "This account first appeared in the last 7 days."})
        vc = tracesense.victim_convergence(recipient, sorted(rec, key=lambda m: m.at), datetime.now(timezone.utc))
        if vc["first_time_payers_24h"] >= 5 and vc["first_time_share"] >= 0.8:
            reasons.append({"code": "MANY_NEW_PAYERS", "severity": 2, "text": f"{vc['first_time_payers_24h']} people paid this account for the first time in the last 24 hours."})
        score = tracesense.trace_score(recipient, rec)
        if score["score"] is not None and score["score"] >= 50:
            reasons.append({"code": "TRACESCORE", "severity": 3, "text": f"TraceScore {score['score']}/100 ({score['band_label']}): {', '.join(c['label'].lower() for c in score['contributions'][:2])}."})
    complaints = db.scalar(select(func.count(Complaint.id)).where(Complaint.paid_to == recipient)) or 0
    if complaints:
        reasons.append({"code": "COMPLAINTS", "severity": 3, "text": f"{complaints} complaint(s) name this account."})
    label = db.scalar(select(AccountLabel).where(AccountLabel.account_ref == recipient))
    if label and label.label == "confirmed_fraud":
        reasons.append({"code": "CONFIRMED", "severity": 3, "text": "Investigators have flagged this account."})
    level = "stop" if any(r["severity"] >= 3 for r in reasons) else "caution" if any(r["severity"] >= 2 for r in reasons) else "info" if reasons else "clear"
    return {"engine": "TraceShield", "level": level, "reasons": sorted(reasons, key=lambda r: -r["severity"])}


class ReportGenerateIn(BaseModel):
    account_ref: str = Field(min_length=2, max_length=255)
    title: str | None = Field(default=None, max_length=180)
    case_ref: str | None = Field(default=None, max_length=40)
    hops: int = Field(default=2, ge=1, le=4)
    include_ai_summary: bool = False


@app.post("/api/v1/reports/generate", response_model=ReportOut, status_code=201)
def generate_report(body: ReportGenerateIn, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    """Build an evidence report from persisted records for one account and store it."""
    account = body.account_ref.strip()
    content = tp_assistant.build_report(db, account, hops=body.hops, include_ai_summary=body.include_ai_summary)
    if not content["transactions"] and not content["ledger_transfers"]:
        raise HTTPException(404, f"No records mention {account}. Check the account reference.")
    report = InvestigationReport(report_ref="RPT-" + uuid4().hex[:12].upper(), title=(body.title or f"Evidence report: {account}").strip()[:180],
                                 report_type="account_evidence", status="FINAL", case_ref=body.case_ref, body=json.dumps(content, default=str),
                                 created_by=user.id)
    db.add(report); db.flush()
    db.add(AuditEvent(actor_user_id=user.id, action="report.generated", object_ref=report.report_ref, detail=json.dumps({"account": account})))
    db.commit(); db.refresh(report)
    return report


@app.get("/api/v1/reports/{report_id}", response_model=ReportOut)
def get_report(report_id: int, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    report = db.get(InvestigationReport, report_id)
    if not report:
        raise HTTPException(404, "Report not found")
    return report


@app.delete("/api/v1/reports/{report_id}", status_code=204)
def delete_report(report_id: int, db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst"))):
    report = db.get(InvestigationReport, report_id)
    if not report:
        raise HTTPException(404, "Report not found")
    db.add(AuditEvent(actor_user_id=user.id, action="report.deleted", object_ref=report.report_ref))
    db.delete(report); db.commit()


class CaseUpdateIn(BaseModel):
    status: str | None = Field(default=None, pattern="^(OPEN|IN_REVIEW|CLOSED)$")
    description: str | None = Field(default=None, max_length=4000)
    account_ref: str | None = Field(default=None, max_length=255)


@app.patch("/api/v1/cases/{case_id}", response_model=CaseOut)
def update_case(case_id: int, body: CaseUpdateIn, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    case = db.get(InvestigationCase, case_id)
    if not case:
        raise HTTPException(404, "Case not found")
    for field in ("status", "description", "account_ref"):
        value = getattr(body, field)
        if value is not None:
            setattr(case, field, value.strip() if isinstance(value, str) else value)
    db.add(AuditEvent(actor_user_id=user.id, action="case.updated", object_ref=case.case_ref, detail=body.model_dump_json(exclude_none=True)))
    db.commit(); db.refresh(case)
    return case


class AssistantIn(BaseModel):
    question: str = Field(min_length=2, max_length=1000)
    account_ref: str | None = Field(default=None, max_length=255)
    screen: str | None = Field(default=None, max_length=60)


@app.get("/api/v1/assistant/topics")
def assistant_topics(user: User = Depends(require_roles(*OPS_ROLES))):
    return {"topics": tp_assistant.TOPICS, "gemini": gemini_status()}


@app.post("/api/v1/assistant/ask")
def assistant_ask(body: AssistantIn, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    return tp_assistant.ask(db, body.question.strip(), (body.account_ref or "").strip() or None, body.screen)


@app.get("/api/v1/system/gemini")
def system_gemini(user: User = Depends(require_roles(*OPS_ROLES))):
    """Check the Gemini configuration with a tiny live request."""
    from .gemini_service import generate_json
    info = gemini_status()
    if info["enabled"]:
        probe = generate_json('Reply with JSON only: {"ok": true}')
        info.update({"reachable": probe["ok"], "model_used": probe.get("model"), "error": probe.get("error")})
    return info


class ResetIn(BaseModel):
    scope: str = Field(pattern="^(ingested|investigation)$")
    confirm: str


@app.post("/api/v1/admin/reset")
async def reset_data(body: ResetIn, db: Session = Depends(get_db), user: User = Depends(require_roles("admin"))):
    """Delete imported evidence (and optionally cases and reports). Users, wallets and the TraceBank ledger are kept."""
    if body.confirm != "RESET":
        raise HTTPException(400, 'Type RESET to confirm.')
    from sqlalchemy import delete as sql_delete
    counts = {}
    counts["conflicts"] = db.execute(sql_delete(SourceConflict)).rowcount
    counts["transactions"] = db.execute(sql_delete(Transaction)).rowcount
    counts["ingestion_jobs"] = db.execute(sql_delete(IngestionJob)).rowcount
    referenced = select(PaymentIntent.assessment_id)
    counts["risk_assessments"] = db.execute(sql_delete(RiskAssessment).where(RiskAssessment.id.not_in(referenced))).rowcount
    if body.scope == "investigation":
        counts["reports"] = db.execute(sql_delete(InvestigationReport)).rowcount
        counts["cases"] = db.execute(sql_delete(InvestigationCase)).rowcount
    db.add(AuditEvent(actor_user_id=user.id, action="admin.reset", object_ref=body.scope, detail=json.dumps(counts)))
    db.commit()
    await hub.publish({"type": "ingestion.completed", "reset": True})
    return {"scope": body.scope, "deleted": counts, "kept": ["users", "profiles", "wallets", "TraceBank ledger", "audit log"]}


# ------------------------------------------------------------------------------------------
# TraceFlow · TraceSense / TraceScore · TraceRank · TraceBench
# ------------------------------------------------------------------------------------------

@app.get("/api/v1/traceflow/{account_ref}")
def traceflow_overview(account_ref: str, hops: int = Query(3, ge=1, le=5), db: Session = Depends(get_db),
                       user: User = Depends(require_roles(*OPS_ROLES))):
    """Naive vs time-respecting view of an account's neighbourhood, plus peel chains."""
    root = account_ref.strip()
    moves, truncated = collect_neighbourhood(db, root, hops, 800)
    reach = traceflow.causal_reach(moves, root, max_hops=hops + 2)
    return {"root": root, "truncated": truncated, **reach, "peel_chains": traceflow.peel_chains(moves),
            "exits": sorted({a for m in moves for a in (m.sender, m.receiver) if traceflow.exit_kind(a)})}


class FollowIn(BaseModel):
    edge_key: str = Field(min_length=3, max_length=120)
    root: str = Field(min_length=2, max_length=255)
    hops: int = Field(default=4, ge=1, le=6)
    method: str = Field(default="fifo", pattern="^(fifo|lifo|proportional)$")


@app.post("/api/v1/traceflow/follow")
def traceflow_follow(body: FollowIn, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    """Follow one payment's money forward: attribution by three methods, holds, bottlenecks, golden hour."""
    moves, truncated = collect_neighbourhood(db, body.root.strip(), body.hops, 1500)
    if not any(m.key == body.edge_key for m in moves):
        raise HTTPException(404, "That transfer is not in this trace. Trace from one of its accounts first.")
    both = traceflow.attribute_all(moves, body.edge_key)
    chosen = both["methods"][body.method]
    cut = traceflow.bottlenecks(moves, chosen)
    seed_receiver = chosen["seed"]["to"]
    reach = traceflow.causal_reach(moves, seed_receiver, since=datetime.fromisoformat(chosen["seed"]["at"]), max_hops=body.hops + 2)
    return {"seed": chosen["seed"], "method": body.method, "attribution": chosen, "comparison": both["comparison"],
            "disagreement": both["disagreement"], "uncertainty_note": both["uncertainty_note"], "bottlenecks": cut,
            "hold_list": traceflow.hold_list(chosen, cut), "golden_hour": traceflow.golden_hour(chosen),
            "causal_edges": reach["forward_edges"], "truncated": truncated}


@app.get("/api/v1/tracescore/{account_ref}")
def tracescore(account_ref: str, as_of: datetime | None = None, db: Session = Depends(get_db),
               user: User = Depends(require_roles(*OPS_ROLES))):
    ref = account_ref.strip()
    moves, _ = collect_neighbourhood(db, ref, 2, 1200)
    network = tracesense.network_signals(moves)
    result = tracesense.trace_score(ref, moves, as_of=as_of, network=network)
    label = db.scalar(select(AccountLabel).where(AccountLabel.account_ref == ref))
    result["label"] = None if not label else {"label": label.label, "reason": label.reason, "updated_at": label.updated_at.isoformat()}
    result["complaints"] = db.scalar(select(func.count(Complaint.id)).where(Complaint.paid_to == ref)) or 0
    return result


class ComplaintIn(BaseModel):
    victim_name: str = Field(min_length=2, max_length=160)
    victim_account: str | None = Field(default=None, max_length=255)
    paid_to: str = Field(min_length=2, max_length=255)
    amount: Decimal = Field(gt=0, le=Decimal("100000000"))
    paid_at: datetime
    scam_type: str = Field(default="unknown", max_length=60)
    description: str = Field(default="", max_length=4000)


@app.post("/api/v1/complaints", status_code=201)
def create_complaint(body: ComplaintIn, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    """Record a victim complaint, match it to a recorded payment when possible, and start the trace."""
    paid_to = body.paid_to.strip().lower()
    paid_at = body.paid_at if body.paid_at.tzinfo else body.paid_at.replace(tzinfo=timezone.utc)
    near = [m for m in _movements_for(db, {paid_to}, start=paid_at - timedelta(days=1), end=paid_at + timedelta(days=1), include_failed=False)
            if m.receiver == paid_to and abs(m.amount - body.amount) <= max(Decimal("1"), body.amount * Decimal("0.01"))]
    if body.victim_account:
        near = [m for m in near if m.sender == body.victim_account.strip().lower()] or near
    match = min(near, key=lambda m: abs((m.at - paid_at).total_seconds()), default=None)
    complaint = Complaint(complaint_ref="CMP-" + uuid4().hex[:10].upper(), victim_name=body.victim_name.strip(),
                          victim_account=(body.victim_account or "").strip().lower() or None, paid_to=paid_to, amount=body.amount,
                          paid_at=paid_at, scam_type=body.scam_type, description=body.description.strip(),
                          matched_transaction_key=match.key if match else None, created_by=user.id)
    db.add(complaint); db.flush()
    db.add(AuditEvent(actor_user_id=user.id, action="complaint.created", object_ref=complaint.complaint_ref,
                      detail=json.dumps({"paid_to": paid_to, "matched": bool(match)})))
    db.commit(); db.refresh(complaint)
    trace = None
    if match:
        moves, _ = collect_neighbourhood(db, paid_to, 4, 1500)
        chosen = traceflow.attribute(moves, match.key, "fifo")
        cut = traceflow.bottlenecks(moves, chosen)
        trace = {"seed": chosen["seed"], "hold_list": traceflow.hold_list(chosen, cut), "golden_hour": traceflow.golden_hour(chosen)}
    return {**_complaint_json(complaint), "trace": trace}


def _complaint_json(c: Complaint) -> dict:
    return {"id": c.id, "complaint_ref": c.complaint_ref, "victim_name": c.victim_name, "victim_account": c.victim_account,
            "paid_to": c.paid_to, "amount": str(c.amount), "paid_at": c.paid_at.isoformat(), "scam_type": c.scam_type,
            "description": c.description, "matched_transaction_key": c.matched_transaction_key, "status": c.status,
            "created_at": c.created_at.isoformat()}


@app.get("/api/v1/complaints")
def list_complaints(db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    return [_complaint_json(c) for c in db.scalars(select(Complaint).order_by(desc(Complaint.created_at)).limit(300))]


class LabelIn(BaseModel):
    account_ref: str = Field(min_length=2, max_length=255)
    label: str = Field(pattern="^(confirmed_fraud|not_suspicious|watch)$")
    reason: str = Field(default="", max_length=2000)


@app.post("/api/v1/labels")
def set_label(body: LabelIn, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    ref = body.account_ref.strip().lower()
    row = db.scalar(select(AccountLabel).where(AccountLabel.account_ref == ref))
    if row:
        row.label, row.reason, row.created_by = body.label, body.reason.strip(), user.id
    else:
        row = AccountLabel(account_ref=ref, label=body.label, reason=body.reason.strip(), created_by=user.id); db.add(row)
    db.add(AuditEvent(actor_user_id=user.id, action="label.set", object_ref=ref, detail=json.dumps({"label": body.label, "reason": body.reason})))
    db.commit()
    return {"account_ref": ref, "label": body.label}


@app.get("/api/v1/labels")
def list_labels(db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    return [{"account_ref": l.account_ref, "label": l.label, "reason": l.reason, "updated_at": l.updated_at.isoformat()}
            for l in db.scalars(select(AccountLabel).order_by(desc(AccountLabel.updated_at)))]


@app.delete("/api/v1/labels/{account_ref}", status_code=204)
def delete_label(account_ref: str, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    row = db.scalar(select(AccountLabel).where(AccountLabel.account_ref == account_ref.strip().lower()))
    if row:
        db.add(AuditEvent(actor_user_id=user.id, action="label.removed", object_ref=row.account_ref))
        db.delete(row); db.commit()


@app.get("/api/v1/tracerank")
def tracerank_endpoint(limit: int = Query(40, ge=1, le=200), db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    """Accounts ranked by how strongly their money connects to confirmed fraud and complaints."""
    seeds: dict[str, float] = {}
    for l in db.scalars(select(AccountLabel).where(AccountLabel.label == "confirmed_fraud")):
        seeds[l.account_ref] = seeds.get(l.account_ref, 0) + 2.0
    for c in db.scalars(select(Complaint)):
        seeds[c.paid_to] = seeds.get(c.paid_to, 0) + 1.0
    cleared = {l.account_ref for l in db.scalars(select(AccountLabel).where(AccountLabel.label == "not_suspicious"))}
    return tracerank.trace_rank(recent_movements(db), seeds, cleared, limit=limit)


class BenchIn(BaseModel):
    seed: int = Field(default=42, ge=0, le=100000)
    quick: bool = False


@app.post("/api/v1/tracebench/run")
def tracebench_run(body: BenchIn, user: User = Depends(require_roles(*OPS_ROLES))):
    """Run the synthetic fraud world and every experiment. Uses generated data only; nothing is stored."""
    return tracebench.run(seed=body.seed, quick=body.quick)


@app.get("/api/v1/transactions", response_model=list[TransactionOut])
def transactions(limit: int = Query(100, ge=1, le=500), account_ref: str | None = None, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    stmt = select(Transaction).order_by(desc(Transaction.occurred_at)).limit(limit)
    if account_ref: stmt = select(Transaction).where((Transaction.sender_id == account_ref) | (Transaction.receiver_id == account_ref)).order_by(desc(Transaction.occurred_at)).limit(limit)
    return list(db.scalars(stmt))

@app.get("/api/v1/metrics")
def metrics(db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    transaction_count = db.scalar(select(func.count(Transaction.id))) or 0
    account_refs = select(Transaction.sender_id.label("account_ref")).union(select(Transaction.receiver_id.label("account_ref"))).subquery()
    account_count = db.scalar(select(func.count()).select_from(account_refs)) or 0
    latest_transaction_at = db.scalar(select(func.max(Transaction.occurred_at)))
    latest_ingested_at = db.scalar(select(func.max(Transaction.ingested_at)))
    # Latest assessment per recipient, so re-checking one account does not inflate the counts.
    latest_ids = select(func.max(RiskAssessment.id)).group_by(RiskAssessment.recipient_ref)
    risk_levels = {level: n for level, n in db.execute(select(RiskAssessment.level, func.count(RiskAssessment.id))
                   .where(RiskAssessment.id.in_(latest_ids)).group_by(RiskAssessment.level)).all()}
    provenance = {status: n for status, n in db.execute(select(Transaction.provenance_status, func.count(Transaction.id))
                  .group_by(Transaction.provenance_status)).all()}
    ledger = {status: n for status, n in db.execute(select(PilotTransfer.status, func.count(PilotTransfer.id))
              .group_by(PilotTransfer.status)).all()}
    job_totals = db.execute(select(func.coalesce(func.sum(IngestionJob.received), 0), func.coalesce(func.sum(IngestionJob.accepted), 0),
                                   func.coalesce(func.sum(IngestionJob.rejected), 0), func.coalesce(func.sum(IngestionJob.duplicates), 0),
                                   func.coalesce(func.sum(IngestionJob.conflicts), 0))).one()
    ingestion = dict(zip(("received", "accepted", "rejected", "duplicates", "conflicts"), (int(x) for x in job_totals)))
    return {"transaction_count": transaction_count, "account_count": account_count,
            "latest_transaction_at": latest_transaction_at.isoformat() if latest_transaction_at else None,
            "latest_ingested_at": latest_ingested_at.isoformat() if latest_ingested_at else None,
            "source_mode": "persisted_ingested_records",
            "risk_levels": risk_levels, "high_risk_count": risk_levels.get("review", 0),
            "provenance": provenance, "ledger": ledger, "ingestion": ingestion,
            "open_conflicts": db.scalar(select(func.count(SourceConflict.id)).where(SourceConflict.status == "UNRESOLVED")) or 0}

class StreamTransactionIn(BaseModel):
    transaction_id: str | None = Field(default=None, max_length=128)
    event_id: str | None = Field(default=None, max_length=128)
    sender_id: str = Field(min_length=1, max_length=255)
    receiver_id: str = Field(min_length=1, max_length=255)
    amount: Decimal = Field(gt=0, max_digits=18, decimal_places=2)
    currency: str = Field(default="INR", min_length=3, max_length=3)
    timestamp: datetime
    source_id: str = Field(default="realtime-api", max_length=255)
    source_record_ref: str | None = Field(default=None, max_length=255)


@app.post("/api/v1/stream/transactions")
async def stream_transaction(body: StreamTransactionIn, db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst"))):
    """Accept one real-time event, persist it first, then broadcast it to authorized live subscribers."""
    event_id = (body.event_id or ("EVT-" + uuid4().hex)).strip()[:128]
    existing = db.scalar(select(Transaction).where(Transaction.event_id == event_id))
    if existing:
        return {"status": "DUPLICATE", "transaction_ref": existing.transaction_ref, "event_id": existing.event_id}
    occurred = body.timestamp
    if occurred.tzinfo is None:
        occurred = occurred.replace(tzinfo=timezone.utc)
    tx = Transaction(
        transaction_ref=(body.transaction_id or "TXN-" + uuid4().hex[:16].upper())[:128],
        event_id=event_id,
        sender_id=body.sender_id.strip(), receiver_id=body.receiver_id.strip(), amount=body.amount,
        currency=body.currency.upper(), occurred_at=occurred.astimezone(timezone.utc),
        source_id=body.source_id.strip(), source_record_ref=(body.source_record_ref or event_id)[:255],
        provenance_status="stream_observed",
    )
    db.add(tx)
    try:
        db.commit(); db.refresh(tx)
    except IntegrityError:
        db.rollback()
        existing = db.scalar(select(Transaction).where(Transaction.event_id == event_id))
        if existing:
            return {"status": "DUPLICATE", "transaction_ref": existing.transaction_ref, "event_id": existing.event_id}
        raise HTTPException(409, "Event could not be persisted")
    event = activity_event(db, actor_user_id=user.id, event_type="stream.transaction.accepted", object_ref=tx.transaction_ref,
                           details={"event_id": tx.event_id, "source_id": tx.source_id, "sender_id": tx.sender_id,
                                    "receiver_id": tx.receiver_id, "amount": str(tx.amount)})
    await hub.publish({"type": "transaction.accepted", "transaction": TransactionOut.model_validate(tx, from_attributes=True).model_dump(mode="json")})
    await hub.publish({"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
                       "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()})
    return {"status": "ACCEPTED", "transaction_ref": tx.transaction_ref, "event_id": tx.event_id}


@app.get("/api/v1/analytics/overview")
def analytics_overview(db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    total = db.scalar(select(func.count(Transaction.id))) or 0
    volume = db.scalar(select(func.coalesce(func.sum(Transaction.amount), 0)).select_from(Transaction)) or 0
    currencies = list(db.execute(select(Transaction.currency, func.count(Transaction.id)).group_by(Transaction.currency)).all())
    top_senders = list(db.execute(select(Transaction.sender_id, func.count(Transaction.id), func.coalesce(func.sum(Transaction.amount), 0)).group_by(Transaction.sender_id).order_by(desc(func.count(Transaction.id))).limit(10)).all())
    top_receivers = list(db.execute(select(Transaction.receiver_id, func.count(Transaction.id), func.coalesce(func.sum(Transaction.amount), 0)).group_by(Transaction.receiver_id).order_by(desc(func.count(Transaction.id))).limit(10)).all())
    return {
        "transaction_count": total,
        "total_volume": str(volume),
        "currency_breakdown": [{"currency": c, "count": n} for c, n in currencies],
        "top_senders": [{"account": a, "count": n, "volume": str(v)} for a, n, v in top_senders],
        "top_receivers": [{"account": a, "count": n, "volume": str(v)} for a, n, v in top_receivers],
        "data_source": "persisted Trace.Pay transaction records",
    }


@app.post("/api/v1/risk/check", response_model=RiskOut)
async def risk_check(body: RiskIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    as_of = body.as_of if user.role in OPS_ROLES else None  # pilot users always get the live window
    recipient = body.recipient_ref.strip()
    if user.role not in OPS_ROLES:
        try:
            recipient = normalize_tracepay_id(recipient)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
    assessment = assess_recipient(db, recipient, as_of=as_of)
    reasons = json.loads(assessment.reasons_json)
    shield = trace_shield(db, user, recipient, body.amount)
    event = activity_event(db, actor_user_id=user.id, event_type="risk.assessed", object_ref=assessment.recipient_ref,
                           details={"assessment_id": assessment.id, "level": assessment.level, "rule_version": assessment.rule_version,
                                    "observed_record_count": assessment.transaction_count})
    await hub.publish({"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
                       "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()})
    return RiskOut(assessment_id=assessment.id, recipient_ref=assessment.recipient_ref, level=assessment.level, reasons=reasons,
        observed_transaction_count=assessment.transaction_count, data_as_of=assessment.assessed_at, rule_version=assessment.rule_version,
        evidence=json.loads(assessment.evidence_json or "[]") if user.role in OPS_ROLES else [],
        window_start=assessment.window_start, window_end=assessment.window_end, shield=shield,
        disclaimer="Advisory only. Based solely on records currently ingested into Trace.Pay; not proof of fraud and not a guarantee of safety.")

@app.get("/api/v1/graph/paths/{account_ref}")
def graph(account_ref: str, max_hops: int = Query(3, ge=1, le=6), limit: int = Query(500, ge=1, le=2000),
          start: datetime | None = None, end: datetime | None = None,
          db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    return graph_for_account(db, account_ref.strip(), max_hops, limit, start, end)


@app.get("/api/v1/accounts")
def list_accounts(q: str | None = None, limit: int = Query(60, ge=1, le=300), db: Session = Depends(get_db),
                  user: User = Depends(require_roles(*OPS_ROLES))):
    """Every account that appears in persisted records, ranked by activity."""
    from sqlalchemy import union_all, literal
    parts = union_all(
        select(Transaction.sender_id.label("ref"), Transaction.amount.label("amount"), literal(0).label("inbound"), Transaction.occurred_at.label("at")),
        select(Transaction.receiver_id.label("ref"), Transaction.amount.label("amount"), literal(1).label("inbound"), Transaction.occurred_at.label("at")),
        select(PilotTransfer.sender_vpa.label("ref"), PilotTransfer.amount.label("amount"), literal(0).label("inbound"), PilotTransfer.created_at.label("at")).where(PilotTransfer.status == "SUCCESS"),
        select(PilotTransfer.receiver_vpa.label("ref"), PilotTransfer.amount.label("amount"), literal(1).label("inbound"), PilotTransfer.created_at.label("at")).where(PilotTransfer.status == "SUCCESS"),
    ).subquery()
    stmt = select(parts.c.ref, func.count().label("records"), func.sum(parts.c.inbound).label("inbound"),
                  func.coalesce(func.sum(parts.c.amount), 0).label("volume"), func.max(parts.c.at).label("last_seen")).group_by(parts.c.ref)
    if q:
        stmt = stmt.where(parts.c.ref.ilike(f"%{q.strip()}%"))
    rows = db.execute(stmt.order_by(desc("records"), parts.c.ref).limit(limit)).all()
    return [{"account": r.ref, "records": r.records, "in_count": int(r.inbound or 0), "out_count": r.records - int(r.inbound or 0),
             "volume": str(r.volume), "last_seen": r.last_seen.isoformat() if r.last_seen else None} for r in rows]


@app.get("/api/v1/accounts/{account_ref}/summary")
def account_summary_endpoint(account_ref: str, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    return summarize_account(db, account_ref.strip())


@app.get("/api/v1/analytics/timeseries")
def analytics_timeseries(days: int = Query(14, ge=3, le=90), db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    """Daily observed activity, anchored to the latest record so historical datasets still chart."""
    return network_timeseries(db, days)


@app.get("/api/v1/conflicts")
def list_conflicts(limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    rows = db.scalars(select(SourceConflict).order_by(desc(SourceConflict.created_at)).limit(limit)).all()
    return [{"id": c.id, "transaction_ref": c.transaction_ref, "existing_transaction_id": c.existing_transaction_id,
             "ingestion_job_id": c.ingestion_job_id, "differing_fields": c.differing_fields.split(","),
             "incoming": json.loads(c.incoming_json), "status": c.status, "created_at": c.created_at.isoformat()} for c in rows]

@app.post("/api/v1/payment-intents", response_model=PaymentIntentOut, status_code=201)
def create_payment_intent(body: PaymentIntentIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    assessment = db.get(RiskAssessment, body.assessment_id)
    if not assessment or assessment.recipient_ref != body.recipient_ref:
        raise HTTPException(400, "A matching recipient risk assessment is required before creating a payment intent")
    intent = PaymentIntent(user_id=user.id, assessment_id=assessment.id, recipient_ref=body.recipient_ref, amount=body.amount, note=body.note, status="handoff_pending")
    db.add(intent); db.flush()
    db.add(AuditEvent(actor_user_id=user.id, action="payment_intent.created", object_ref=str(intent.id), detail="Payment intent created before opening external payment app"))
    db.commit(); db.refresh(intent)
    return PaymentIntentOut(id=intent.id, recipient_ref=intent.recipient_ref, amount=intent.amount, currency=intent.currency, status=intent.status, created_at=intent.created_at, disclaimer="This is a payment handoff intent, not evidence that money was transferred.")

@app.post("/api/v1/payment-intents/{intent_id}/handoff-result")
def payment_handoff_result(intent_id: int, opened: bool, db: Session = Depends(get_db), user: User = Depends(current_user)):
    intent = db.get(PaymentIntent, intent_id)
    if not intent or intent.user_id != user.id:
        raise HTTPException(404, "Payment intent not found")
    if intent.status != "handoff_pending":
        raise HTTPException(409, "Payment handoff result has already been recorded")
    intent.status = "handoff_opened" if opened else "handoff_failed"
    db.add(AuditEvent(actor_user_id=user.id, action="payment_intent.handoff_result", object_ref=str(intent.id), detail=intent.status))
    db.commit()
    return {"id": intent.id, "status": intent.status, "payment_completed": False, "message": "Opening a payment app does not confirm that a payment was authorised or completed."}

@app.get("/api/v1/payment-intents", response_model=list[PaymentIntentOut])
def list_payment_intents(limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db), user: User = Depends(current_user)):
    from sqlalchemy import desc
    rows = list(db.scalars(select(PaymentIntent).where(PaymentIntent.user_id == user.id).order_by(desc(PaymentIntent.created_at)).limit(limit)))
    return [PaymentIntentOut(id=r.id, recipient_ref=r.recipient_ref, amount=r.amount, currency=r.currency, status=r.status, created_at=r.created_at, disclaimer="Handoff status only. This is not evidence that money was transferred.") for r in rows]

@app.get("/api/v1/console/payment-intents")
def console_payment_intents(limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst", "reviewer"))):
    rows = list(db.scalars(select(PaymentIntent).order_by(desc(PaymentIntent.created_at)).limit(limit)))
    return [{"id": r.id, "user_id": r.user_id, "assessment_id": r.assessment_id, "recipient_ref": r.recipient_ref, "amount": str(r.amount) if r.amount is not None else None, "currency": r.currency, "note": r.note, "status": r.status, "created_at": r.created_at.isoformat(), "updated_at": r.updated_at.isoformat(), "meaning": "Handoff state only; not proof of payment completion"} for r in rows]

REQUIRED_FIELDS = {"sender_id", "receiver_id", "amount", "timestamp"}
MAPPABLE_FIELDS = {"transaction_id", "event_id", "sender_id", "receiver_id", "amount", "currency", "timestamp", "source_record_ref"}


def _record_conflict(db: Session, job: IngestionJob, normalized, existing: Transaction) -> str | None:
    """Return a description if an incoming row contradicts an existing record with the same reference."""
    differing = []
    if existing.sender_id != normalized.sender_id: differing.append("sender_id")
    if existing.receiver_id != normalized.receiver_id: differing.append("receiver_id")
    if Decimal(str(existing.amount)) != normalized.amount: differing.append("amount")
    if existing.occurred_at.astimezone(timezone.utc) != normalized.timestamp: differing.append("timestamp")
    if not differing:
        return None
    incoming = {"sender_id": normalized.sender_id, "receiver_id": normalized.receiver_id, "amount": str(normalized.amount),
                "currency": normalized.currency, "timestamp": normalized.timestamp.isoformat(), "source_id": job.source_id,
                "source_file": job.filename, "source_sheet": normalized.sheet, "source_row": normalized.row_no,
                "source_record_ref": normalized.source_record_ref}
    with db.begin_nested():
        db.add(SourceConflict(transaction_ref=existing.transaction_ref, existing_transaction_id=existing.id, ingestion_job_id=job.id,
                              differing_fields=",".join(differing), incoming_json=json.dumps(incoming)))
    return ", ".join(differing)


def _ingest_frames(db: Session, job: IngestionJob, sheets: dict, plans: dict[str, dict]) -> dict:
    """Validate, deduplicate and persist rows using the per-sheet plans from the schema agent."""
    errors: list[str] = []
    counts = {"received": 0, "accepted": 0, "rejected": 0, "duplicates": 0, "conflicts": 0, "skipped": 0}
    occurrences: dict[str, int] = {}
    for sheet_name, info in sheets.items():
        frame, plan = info["frame"], plans[sheet_name]
        if not plan.get("ready"):
            counts["received"] += len(frame); counts["rejected"] += len(frame)
            errors.append(f"Sheet {sheet_name}: not imported. Missing: {', '.join(plan.get('missing') or ['a recognisable layout'])}")
            continue
        for offset, (_, row) in enumerate(frame.iterrows()):
            row_no = info["header_row"] + 2 + offset
            try:
                normalized = schema_agent.normalize_with_plan(row.to_dict(), plan, row_no, sheet_name, occurrences)
            except (ValueError, InvalidOperation, TypeError, KeyError) as exc:
                counts["received"] += 1; counts["rejected"] += 1
                if len(errors) < 200: errors.append(f"{sheet_name} row {row_no}: {str(exc)[:220]}")
                continue
            if normalized is None:
                counts["skipped"] += 1
                continue
            counts["received"] += 1
            tx = Transaction(
                transaction_ref=normalized.transaction_id, event_id=normalized.event_id,
                sender_id=normalized.sender_id, receiver_id=normalized.receiver_id, amount=normalized.amount,
                currency=normalized.currency, occurred_at=normalized.timestamp, source_id=job.source_id,
                source_record_ref=normalized.source_record_ref, provenance_status=normalized.quality,
                ingestion_job_id=job.id, source_file=job.filename, source_sheet=str(sheet_name)[:128],
                source_row=row_no, fingerprint=normalized.fingerprint)
            try:
                with db.begin_nested():
                    db.add(tx); db.flush()
                counts["accepted"] += 1
            except IntegrityError:
                existing = db.scalar(select(Transaction).where(Transaction.transaction_ref == normalized.transaction_id))
                conflict = _record_conflict(db, job, normalized, existing) if existing else None
                if conflict:
                    counts["conflicts"] += 1
                    if len(errors) < 200:
                        errors.append(f"{sheet_name} row {row_no}: CONFLICT with existing {existing.transaction_ref} ({conflict}); both versions preserved")
                else:
                    counts["duplicates"] += 1
            except Exception as exc:
                counts["received"] += 1; counts["rejected"] += 1
                if len(errors) < 200: errors.append(f"{sheet_name} row {row_no}: invalid record ({type(exc).__name__})")
    return {**counts, "errors": errors}


def _plans_for(sheets: dict, filename: str, *, use_gemini: bool, statement_account: str, requested: dict | None) -> dict[str, dict]:
    plans = {}
    for name, info in sheets.items():
        base = schema_agent.build_plan(name, info, filename, use_gemini=use_gemini, statement_account=statement_account)
        wanted = (requested or {}).get(name)
        plans[name] = schema_agent.plan_from_request(wanted, [str(c) for c in info["frame"].columns], base) if wanted else base
    return plans


def _read_sheets(filename: str, raw: bytes) -> dict:
    try:
        sheets = schema_agent.load_sheets(filename, raw)
    except Exception as exc:
        raise HTTPException(400, f"Could not read dataset: {exc}") from exc
    if not sheets:
        raise HTTPException(400, "The uploaded dataset contains no non-empty sheets/rows")
    return sheets


async def _read_upload_limited(file: UploadFile) -> bytes:
    max_bytes = int(os.getenv("UPLOAD_MAX_MB", "100")) * 1024 * 1024
    raw = await file.read(max_bytes + 1)
    if len(raw) > max_bytes:
        raise HTTPException(413, f"Upload exceeds configured size limit of {max_bytes // 1024 // 1024} MB")
    if not raw:
        raise HTTPException(400, "Empty upload")
    return raw


def _plan_view(plan: dict) -> dict:
    keys = ("sheet", "mode", "mapping", "source", "missing", "ready", "statement_account", "statement_account_source",
            "notes", "warnings", "gemini", "timings")
    return {k: plan.get(k) for k in keys}


@app.post("/api/v1/ingestion/preview")
async def ingestion_preview(
    file: UploadFile = File(...), use_gemini: bool = Form(True), statement_account: str = Form(""),
    plan: str = Form(""), user: User = Depends(require_roles("admin", "analyst")),
):
    """Read the file and propose how to import it, without saving anything.

    Returns, per sheet: the detected header row, column profile, the plan (mode, field → column, which of
    rules / Gemini / you chose each mapping, what is missing) and the first rows normalised with that plan.
    """
    stages = []
    t0 = time.perf_counter()
    raw = await _read_upload_limited(file)
    filename = (file.filename or "upload").strip() or "upload"
    sheets = _read_sheets(filename, raw)
    stages.append({"key": "read", "ms": round((time.perf_counter() - t0) * 1000, 1),
                   "detail": f"{len(sheets)} sheet(s), {sum(len(i['frame']) for i in sheets.values())} data rows"})
    t1 = time.perf_counter()
    requested = json.loads(plan).get("sheets") if plan else None
    plans = _plans_for(sheets, filename, use_gemini=use_gemini, statement_account=statement_account, requested=requested)
    stages.append({"key": "plan", "ms": round((time.perf_counter() - t1) * 1000, 1),
                   "detail": ", ".join(f"{n}: {p.get('mode') or 'unknown layout'}" for n, p in plans.items())})
    out = []
    for name, info in sheets.items():
        p = plans[name]
        out.append({"name": name, "rows": len(info["frame"]), "header_row": info["header_row"] + 1,
                    "preamble": info["preamble"][:400], "columns": schema_agent.profile_columns(info["frame"]),
                    "plan": _plan_view(p), "sample": schema_agent.preview_rows(info["frame"], p, name, info["header_row"])})
    return {"filename": filename, "size_bytes": len(raw), "sheets": out, "stages": stages, "fields": schema_agent.FIELD_HELP,
            "gemini": gemini_status()}


async def _run_ingestion(db: Session, user: User, *, filename: str, raw: bytes, content_type: str | None,
                         source_id: str, use_gemini: bool, statement_account: str = "", plan: dict | None = None) -> IngestionOut:
    stages = []
    source = (source_id.strip() or Path(filename).stem)[:255]
    checksum = hashlib.sha256(raw).hexdigest()
    t0 = time.perf_counter()
    sheets = _read_sheets(filename, raw)
    stages.append({"key": "read", "ms": round((time.perf_counter() - t0) * 1000, 1), "detail": f"{len(sheets)} sheet(s)"})
    t1 = time.perf_counter()
    plans = _plans_for(sheets, filename, use_gemini=use_gemini, statement_account=statement_account,
                       requested=(plan or {}).get("sheets"))
    stages.append({"key": "plan", "ms": round((time.perf_counter() - t1) * 1000, 1),
                   "detail": ", ".join(f"{n}: {p.get('mode') or 'unknown'}" for n, p in plans.items())})
    t2 = time.perf_counter()
    raw_blob_url = None
    try:
        raw_blob_url = upload_raw_blob(filename, raw, content_type)
    except Exception as exc:
        print(f"[blob] archival upload failed: {type(exc).__name__}: {exc}", flush=True)
    stages.append({"key": "archive", "ms": round((time.perf_counter() - t2) * 1000, 1),
                   "detail": "raw file archived to Blob storage" if raw_blob_url else "archive skipped (Blob not configured)"})

    job = IngestionJob(source_id=source, status="processing", filename=filename[:255], checksum_sha256=checksum, raw_blob_url=raw_blob_url)
    db.add(job); db.commit(); db.refresh(job)
    t3 = time.perf_counter()
    result = _ingest_frames(db, job, sheets, plans)
    job.received, job.accepted, job.rejected = result["received"], result["accepted"], result["rejected"]
    job.duplicates, job.conflicts = result["duplicates"], result["conflicts"]
    job.errors_json = json.dumps(result["errors"])
    job.status = "completed" if result["rejected"] == 0 and result["conflicts"] == 0 else ("completed_with_errors" if result["accepted"] else "failed")
    job.completed_at = datetime.now(timezone.utc)
    db.commit()
    stages.append({"key": "validate", "ms": round((time.perf_counter() - t3) * 1000, 1),
                   "detail": f"{result['received']} rows checked, {result['rejected']} rejected, {result['skipped']} blank/summary rows skipped"})
    stages.append({"key": "dedupe", "ms": 0, "detail": f"{result['duplicates']} duplicates, {result['conflicts']} conflicts"})
    stages.append({"key": "save", "ms": 0, "detail": f"{result['accepted']} records saved with file/sheet/row provenance"})

    ai_used = any(p.get("gemini", {}).get("used") for p in plans.values())
    event = activity_event(
        db, actor_user_id=user.id, event_type="ingestion.completed", object_ref=str(job.id),
        details={"source_id": source, "filename": filename, "checksum_sha256": checksum, "accepted": job.accepted,
                 "rejected": job.rejected, "duplicates": job.duplicates, "conflicts": job.conflicts, "sheets": len(sheets),
                 "modes": {n: p.get("mode") for n, p in plans.items()}, "gemini_mapping_used": ai_used, "raw_blob_archived": bool(raw_blob_url)})
    await hub.publish({"type": "ingestion.completed", "job_id": job.id, "accepted": job.accepted, "rejected": job.rejected,
                       "duplicates": job.duplicates, "conflicts": job.conflicts, "gemini_mapping_used": ai_used})
    await hub.publish({"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
                       "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()})
    return IngestionOut(job_id=job.id, status=job.status, received=job.received, accepted=job.accepted, rejected=job.rejected,
                        duplicates=job.duplicates, conflicts=job.conflicts, errors=result["errors"][:200],
                        checksum_sha256=checksum, raw_archived=bool(raw_blob_url), skipped=result["skipped"], stages=stages,
                        sheets=[_plan_view(p) for p in plans.values()])


@app.post("/api/v1/ingestion/file", response_model=IngestionOut)
async def ingest_file(
    file: UploadFile = File(...),
    source_id: str = Form(""),
    use_gemini: bool = Form(True),
    statement_account: str = Form(""),
    plan: str = Form(""),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles("admin", "analyst")),
):
    """Import CSV/TXT/TSV/XLS/XLSX/XLSM transfer files or bank/UPI statements.

    ``plan`` is the (optionally edited) plan from /ingestion/preview as JSON: {"sheets": {name: {mode, mapping,
    statement_account}}}. Without it the schema agent plans automatically. Gemini may propose column mappings;
    it never supplies values, and the deterministic validator decides what reaches PostgreSQL.
    """
    raw = await _read_upload_limited(file)
    filename = (file.filename or "upload").strip() or "upload"
    requested = json.loads(plan) if plan else None
    return await _run_ingestion(db, user, filename=filename, raw=raw, content_type=file.content_type, source_id=source_id,
                                use_gemini=use_gemini, statement_account=statement_account, plan=requested)


@app.post("/api/v1/ingestion/csv", response_model=IngestionOut)
async def ingest_csv_compat(source_id: str = "csv-import", file: UploadFile = File(...), db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst"))):
    """Backward-compatible CSV route; uses the same pipeline as /ingestion/file without Gemini."""
    raw = await file.read()
    if not raw:
        raise HTTPException(400, "Empty upload")
    return await _run_ingestion(db, user, filename=file.filename or "upload.csv", raw=raw, content_type=file.content_type,
                                source_id=source_id, use_gemini=False)

@app.get("/api/v1/ingestion/jobs")
def ingestion_jobs(limit: int = Query(50, ge=1, le=200), db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    jobs = list(db.scalars(select(IngestionJob).order_by(desc(IngestionJob.created_at)).limit(limit)))
    return [{"id": j.id, "source_id": j.source_id, "status": j.status, "received": j.received, "accepted": j.accepted, "rejected": j.rejected,
             "duplicates": j.duplicates, "conflicts": j.conflicts or 0, "filename": j.filename, "checksum_sha256": j.checksum_sha256,
             "raw_archived": bool(j.raw_blob_url), "created_at": j.created_at, "completed_at": j.completed_at,
             "errors": json.loads(j.errors_json)} for j in jobs]

@app.get("/api/v1/pilot/profile")
def get_pilot_profile(db: Session = Depends(get_db), user: User = Depends(current_user)):
    profile = db.scalar(select(PilotProfile).where(PilotProfile.user_id == user.id))
    return {"profile": pilot_profile_json(profile, user.email, include_private=True) if profile else None}

@app.post("/api/v1/pilot/profile", status_code=201)
async def create_pilot_profile(
    full_name: str = Form(...), date_of_birth: str = Form(...), gender: str = Form(...),
    consent_profile: bool = Form(...), consent_pilot_ledger: bool = Form(...),
    face_photo: UploadFile = File(...), db: Session = Depends(get_db), user: User = Depends(current_user)
):
    """Create a complete profile only after validating and encrypting a single-face photo."""
    full_name = full_name.strip()
    if len(full_name) < 2 or len(full_name) > 160 or not full_name[0].isalpha() or not all(ch.isalpha() or ch in " .’'‑-" for ch in full_name):
        raise HTTPException(422, "Enter a valid full name without numbers")
    try: dob = date.fromisoformat(date_of_birth)
    except ValueError: raise HTTPException(422, "Enter a valid date of birth")
    if dob > date.today() or (date.today().year - dob.year - ((date.today().month, date.today().day) < (dob.month, dob.day))) < 18:
        raise HTTPException(422, "You must be at least 18 years old")
    allowed_gender = {"Male", "Female", "Non-binary", "Prefer not to say", "Other"}
    if gender not in allowed_gender: raise HTTPException(422, "Choose a valid gender option")
    if not consent_profile or not consent_pilot_ledger:
        raise HTTPException(400, "Please confirm the required profile and service consents")
    if db.scalar(select(PilotProfile).where(PilotProfile.user_id == user.id)):
        raise HTTPException(409, "A profile is already linked to this account")
    content_type = (face_photo.content_type or "").lower()
    allowed_types = {"image/jpeg": ("jpg",), "image/png": ("png",), "image/webp": ("webp",)}
    if content_type not in allowed_types: raise HTTPException(415, "Photo must be JPEG, PNG or WebP")
    max_bytes = 4 * 1024 * 1024
    raw = await face_photo.read(max_bytes + 1)
    if not raw or len(raw) > max_bytes: raise HTTPException(413, "Photo must be between 1 byte and 4 MB")
    signatures = {"image/jpeg": raw.startswith(b"\xff\xd8\xff"), "image/png": raw.startswith(b"\x89PNG\r\n\x1a\n"), "image/webp": len(raw) >= 12 and raw[:4] == b"RIFF" and raw[8:12] == b"WEBP"}
    if not signatures.get(content_type, False): raise HTTPException(415, "The uploaded file content does not match its image format")
    decoded = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_COLOR)
    if decoded is None: raise HTTPException(422, "The photo could not be decoded. Try another image.")
    height, width = decoded.shape[:2]
    if width < 160 or height < 160 or width > 8000 or height > 8000: raise HTTPException(422, "Photo dimensions must be between 160 and 8000 pixels")
    gray = cv2.cvtColor(decoded, cv2.COLOR_BGR2GRAY)
    cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    faces = cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
    if len(faces) != 1: raise HTTPException(422, "Please ensure only your face is clearly visible in the photo (exactly one face is required). Try good lighting and remove sunglasses or hats.")
    assigned_vpa = generate_pilot_vpa(db, user, full_name)
    photo_key = uuid4().hex + ".enc"
    photo_dir = Path(os.getenv("PRIVATE_PHOTO_DIR", "/var/lib/tracepay/private-photos"))
    encrypted_photo = _pii_fernet.encrypt(raw)
    photo_path = photo_dir / photo_key
    try:
        with open(photo_path, "xb") as photo_file:
            os.chmod(photo_path, 0o600)
            photo_file.write(encrypted_photo)
        profile = PilotProfile(user_id=user.id, full_name=protect_pii(full_name), date_of_birth=protect_pii(date_of_birth),
            vpa_id=assigned_vpa, bank_name=protect_pii(""), account_last4=protect_pii(""), participant_type="pilot_user",
            selfie_status="face_detected", gender=gender, photo_storage_key=photo_key, face_count=1)
        db.add(profile); ensure_wallet(db, assigned_vpa); db.commit(); db.refresh(profile)
    except IntegrityError:
        db.rollback(); photo_path.unlink(missing_ok=True)
        raise HTTPException(409, "A profile is already linked to this account")
    except Exception:
        db.rollback(); photo_path.unlink(missing_ok=True); raise
    event = activity_event(db, actor_user_id=user.id, event_type="profile.created", object_ref=assigned_vpa,
        details={"profile_id": profile.id, "identity_assigned": True, "photo_verified": True, "face_count": 1})
    await hub.publish({"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
        "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()})
    return pilot_profile_json(profile, user.email, include_private=True)

@app.get("/api/v1/pilot/profile/photo")
def get_own_profile_photo(db: Session = Depends(get_db), user: User = Depends(current_user)):
    profile = db.scalar(select(PilotProfile).where(PilotProfile.user_id == user.id))
    if not profile or not profile.photo_storage_key: raise HTTPException(404, "Profile photo not found")
    path = Path(os.getenv("PRIVATE_PHOTO_DIR", "/var/lib/tracepay/private-photos")) / profile.photo_storage_key
    try: raw = _pii_fernet.decrypt(path.read_bytes())
    except (OSError, InvalidToken): raise HTTPException(404, "Profile photo is unavailable")
    # Re-detect the MIME type from the signature; never trust a filename.
    mime = "image/jpeg" if raw.startswith(b"\xff\xd8\xff") else "image/png" if raw.startswith(b"\x89PNG\r\n\x1a\n") else "image/webp"
    return Response(content=raw, media_type=mime, headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"})

@app.get("/api/v1/pilot/users/{vpa_id}/photo")
def get_member_photo(vpa_id: str, db: Session = Depends(get_db), user: User = Depends(require_roles(*OPS_ROLES))):
    """Investigators can view a member's live selfie in the console. Every view is audited."""
    profile = db.scalar(select(PilotProfile).where(PilotProfile.vpa_id == vpa_id.strip().lower()))
    if not profile or not profile.photo_storage_key: raise HTTPException(404, "Profile photo not found")
    path = Path(os.getenv("PRIVATE_PHOTO_DIR", "/var/lib/tracepay/private-photos")) / profile.photo_storage_key
    try: raw = _pii_fernet.decrypt(path.read_bytes())
    except (OSError, InvalidToken): raise HTTPException(404, "Profile photo is unavailable")
    db.add(AuditEvent(actor_user_id=user.id, action="member.photo_viewed", object_ref=profile.vpa_id)); db.commit()
    mime = "image/jpeg" if raw.startswith(b"\xff\xd8\xff") else "image/png" if raw.startswith(b"\x89PNG\r\n\x1a\n") else "image/webp"
    return Response(content=raw, media_type=mime, headers={"Cache-Control": "private, max-age=300", "X-Content-Type-Options": "nosniff"})

@app.get("/api/v1/pilot/recipients/{vpa_id}")
async def lookup_pilot_recipient(vpa_id: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    try:
        vpa = normalize_tracepay_id(vpa_id)
    except ValueError as exc:
        raise HTTPException(422, str(exc))
    profile = db.scalar(select(PilotProfile).where(PilotProfile.vpa_id == vpa))
    if profile:
        result = {"registered": True, "recipient_type": "pilot_user", "display_name": reveal_pii(profile.full_name), "vpa_id": profile.vpa_id,
                  "profile_id": profile.id, "message": "Registered Trace.Pay account."}
    else:
        merchant = db.scalar(select(PilotMerchant).where(PilotMerchant.vpa_id == vpa, PilotMerchant.status == "active"))
        if not merchant: raise HTTPException(404, "This QR or Trace.Pay ID is not registered")
        result = {"registered": True, "recipient_type": "merchant", "display_name": merchant.display_name, "vpa_id": merchant.vpa_id,
                  "profile_id": merchant.id, "message": "Registered Trace.Pay merchant."}
    event = activity_event(db, actor_user_id=user.id, event_type="recipient.resolved", object_ref=vpa,
                           details={"recipient_type": result["recipient_type"], "screen": "recipient_lookup"})
    await hub.publish({"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
                       "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()})
    return result


class ClientEventIn(BaseModel):
    event_type: str = Field(min_length=3, max_length=80, pattern=r"^[a-zA-Z0-9_.-]+$")
    object_ref: str | None = Field(default=None, max_length=255)
    screen: str | None = Field(default=None, max_length=80)
    outcome: str | None = Field(default=None, max_length=40)


@app.post("/api/v1/pilot/events", status_code=202)
async def record_client_event(body: ClientEventIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    # Milestone telemetry only: no keystrokes, passwords, tokens, DOB, or raw form values.
    event = activity_event(db, actor_user_id=user.id, event_type="app." + body.event_type,
                           object_ref=body.object_ref, details={"screen": body.screen, "outcome": body.outcome})
    payload = {"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
               "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()}
    await hub.publish(payload)
    return {"accepted": True, "event_id": event.id}


@app.get("/api/v1/console/activity")
def console_activity(limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst", "reviewer"))):
    rows = db.scalars(select(AuditEvent).order_by(desc(AuditEvent.created_at)).limit(limit)).all()
    return [{"id": row.id, "event_type": row.action, "object_ref": row.object_ref, "actor_user_id": row.actor_user_id,
             "details": _parse_detail(row.detail), "created_at": row.created_at.isoformat()} for row in rows]


def _parse_detail(detail: str):
    """Audit details are JSON for structured events and plain text for older ledger entries."""
    try:
        value = json.loads(detail or "{}")
        return value if isinstance(value, dict) else {"text": str(value)}
    except (TypeError, ValueError):
        return {"text": detail}


@app.get("/api/v1/pilot/observability")
def pilot_observability(db: Session = Depends(get_db), user: User = Depends(current_user)):
    try:
        db.execute(select(1))
        database_status = "connected"
    except Exception:
        database_status = "unavailable"
    try:
        redis_client.ping()
        redis_status = "connected"
    except redis.RedisError:
        redis_status = "unavailable"
    return {"checked_at": datetime.now(timezone.utc).isoformat(), "services": [
        {"name": "FastAPI", "status": "connected", "role": "API and orchestration", "technology": "FastAPI / Pydantic"},
        {"name": "PostgreSQL", "status": database_status, "role": "Profiles, ledger, audit and evidence records", "technology": "PostgreSQL / SQLAlchemy"},
        {"name": "Redis", "status": redis_status, "role": "Rate limiting and ephemeral coordination", "technology": "Redis"},
        {"name": "Temporal graph engine", "status": "ready", "role": "Source-linked records plus confirmed ledger transfer paths", "technology": "NetworkX MultiDiGraph"},
        {"name": "Explainable risk rules", "status": "ready", "role": "Evidence-backed rule assessment", "technology": "rules-v1"},
        {"name": "CNN model", "status": "not_configured", "role": "Potential research extension; not used for live decisions", "technology": "CNN / deep learning"},
        {"name": "Live event stream", "status": "ready", "role": "Authenticated WebSocket updates", "technology": "WebSocket"}
    ], "research_context": {"provenance_first": True, "explicit_evidence_gaps": True, "risk_is_advisory": True,
        "graph_scope": "Source-linked observed records and internal ledger entries; failed attempts are not treated as completed value movement. Missing records remain unknown."}}

@app.get("/api/v1/pilot/users")
def list_pilot_users(db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst", "reviewer"))):
    rows = db.execute(select(PilotProfile, User.email).join(User, User.id == PilotProfile.user_id).order_by(desc(PilotProfile.created_at))).all()
    return [pilot_profile_json(profile, email) for profile, email in rows]

@app.get("/api/v1/pilot/merchants")
def list_pilot_merchants(db: Session = Depends(get_db), user: User = Depends(current_user)):
    rows = db.scalars(select(PilotMerchant).order_by(desc(PilotMerchant.created_at))).all()
    return [{"id": m.id, "display_name": m.display_name, "vpa_id": m.vpa_id, "category": m.category,
        "location": m.location, "status": m.status, "created_at": m.created_at.isoformat()} for m in rows]

@app.post("/api/v1/pilot/merchants", status_code=201)
async def create_pilot_merchant(body: MerchantIn, db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst"))):
    vpa = body.vpa_id  # already normalised to name@tracepay by MerchantIn
    if db.scalar(select(PilotMerchant).where(PilotMerchant.vpa_id == vpa)) or db.scalar(select(PilotProfile).where(PilotProfile.vpa_id == vpa)):
        raise HTTPException(409, "This Trace.Pay ID is already registered")
    merchant = PilotMerchant(display_name=body.display_name.strip(), vpa_id=vpa, category=body.category.strip(), location=body.location.strip())
    db.add(merchant)
    ensure_wallet(db, vpa)
    db.commit(); db.refresh(merchant)
    event = activity_event(db, actor_user_id=user.id, event_type="merchant.created", object_ref=vpa,
        details={"merchant_id": merchant.id, "category": merchant.category})
    await hub.publish({"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
        "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()})
    return {"id": merchant.id, "display_name": merchant.display_name, "vpa_id": merchant.vpa_id, "category": merchant.category,
        "location": merchant.location, "status": merchant.status, "created_at": merchant.created_at.isoformat()}

_local_transfer_hits: dict[int, list[float]] = {}


def allow_pilot_transfer(user_id: int, limit: int = 20, window: int = 60) -> bool:
    """Per-user transfer rate limit (20 per minute).

    Uses Redis when available so every API replica shares one count. Without Redis (a single-replica
    pilot), it falls back to an in-process sliding window instead of refusing all payments.
    """
    key = f"tracepay:pilot-transfer-rate:{user_id}"
    try:
        count = redis_client.incr(key)
        if count == 1:
            redis_client.expire(key, window)
        return count <= limit
    except redis.RedisError:
        import time
        now = time.monotonic()
        hits = [t for t in _local_transfer_hits.get(user_id, []) if now - t < window]
        hits.append(now)
        _local_transfer_hits[user_id] = hits
        return len(hits) <= limit


@app.post("/api/v1/pilot/transfers", status_code=201)
async def create_pilot_transfer(body: PilotTransferIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    profile = db.scalar(select(PilotProfile).where(PilotProfile.user_id == user.id))
    if not profile: raise HTTPException(409, "Complete TraceBank pilot profile setup before transferring")
    if profile.vpa_id == body.receiver_vpa: raise HTTPException(400, "Choose a different recipient")
    receiver_exists = db.scalar(select(PilotProfile.id).where(PilotProfile.vpa_id == body.receiver_vpa)) or db.scalar(select(PilotMerchant.id).where(PilotMerchant.vpa_id == body.receiver_vpa))
    if not receiver_exists: raise HTTPException(404, "Recipient is not a registered Trace.Pay account")
    if not allow_pilot_transfer(user.id):
        raise HTTPException(429, "Pilot transfer rate limit reached. Try again in a minute.")
    try:
        transfer = execute_ledger_transfer(db, sender_vpa=profile.vpa_id, receiver_vpa=body.receiver_vpa,
            amount=body.amount, note=body.note, sender_user_id=user.id, idempotency_key=body.idempotency_key, actor_user_id=user.id)
    except IntegrityError:
        db.rollback()
        prior = db.scalar(select(PilotTransfer).where(PilotTransfer.sender_user_id == user.id, PilotTransfer.idempotency_key == body.idempotency_key))
        if prior: return pilot_transfer_json(prior)
        raise HTTPException(409, "Transfer could not be completed; retry using the same idempotency key")
    payload = pilot_transfer_json(transfer)
    event = activity_event(db, actor_user_id=user.id, event_type="transfer." + transfer.status.lower(),
        object_ref=transfer.transfer_ref, details={"sender_vpa": transfer.sender_vpa, "receiver_vpa": transfer.receiver_vpa,
        "amount": str(transfer.amount), "status": transfer.status, "source": "internal_ledger"})
    await hub.publish({"type": "pilot.transfer", "transfer": payload}, vpas={transfer.sender_vpa, transfer.receiver_vpa})
    await hub.publish({"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
        "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()})
    return payload

@app.post("/api/v1/pilot/admin/transfers", status_code=201)
async def admin_create_pilot_transfer(body: AdminPilotTransferIn, db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst"))):
    sender_vpa, receiver_vpa = body.sender_vpa, body.receiver_vpa  # normalised to name@tracepay by the schema
    sender = db.scalar(select(PilotProfile).where(PilotProfile.vpa_id == sender_vpa))
    if not sender: raise HTTPException(404, "Sender is not a registered Trace.Pay account")
    if sender_vpa == receiver_vpa: raise HTTPException(400, "Choose a different recipient")
    receiver_exists = db.scalar(select(PilotProfile.id).where(PilotProfile.vpa_id == receiver_vpa)) or db.scalar(select(PilotMerchant.id).where(PilotMerchant.vpa_id == receiver_vpa))
    if not receiver_exists: raise HTTPException(404, "Recipient is not a registered Trace.Pay account")
    try:
        transfer = execute_ledger_transfer(db, sender_vpa=sender_vpa, receiver_vpa=receiver_vpa,
            amount=body.amount, note=body.note, sender_user_id=sender.user_id,
            idempotency_key=body.idempotency_key, actor_user_id=user.id)
    except IntegrityError:
        db.rollback()
        prior = db.scalar(select(PilotTransfer).where(PilotTransfer.sender_user_id == sender.user_id, PilotTransfer.idempotency_key == body.idempotency_key))
        if prior: return pilot_transfer_json(prior)
        raise HTTPException(409, "Transfer could not be completed")
    payload = pilot_transfer_json(transfer)
    event = activity_event(db, actor_user_id=user.id, event_type="transfer." + transfer.status.lower(),
        object_ref=transfer.transfer_ref, details={"sender_vpa": transfer.sender_vpa, "receiver_vpa": transfer.receiver_vpa,
        "amount": str(transfer.amount), "status": transfer.status, "source": "internal_ledger"})
    await hub.publish({"type": "pilot.transfer", "transfer": payload}, vpas={transfer.sender_vpa, transfer.receiver_vpa})
    await hub.publish({"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
        "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()})
    return payload

class PilotFundingIn(BaseModel):
    vpa_id: str = Field(min_length=2, max_length=255)

    @field_validator("vpa_id")
    @classmethod
    def tracepay_only(cls, value): return normalize_tracepay_id(value)
    amount: Decimal = Field(gt=0, le=1000000)
    note: str = Field(default="Pilot test-fund allocation", max_length=255)
    idempotency_key: str = Field(min_length=8, max_length=100)

@app.get("/api/v1/pilot/wallet")
def get_pilot_wallet(db: Session = Depends(get_db), user: User = Depends(current_user)):
    profile = db.scalar(select(PilotProfile).where(PilotProfile.user_id == user.id))
    if not profile: raise HTTPException(409, "Complete your Trace.Pay profile first")
    wallet = ensure_wallet(db, profile.vpa_id); db.commit(); db.refresh(wallet)
    return wallet_json(wallet)

@app.get("/api/v1/pilot/ledger")
def get_pilot_ledger(limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db), user: User = Depends(current_user)):
    profile = db.scalar(select(PilotProfile).where(PilotProfile.user_id == user.id))
    if not profile: raise HTTPException(409, "Complete your Trace.Pay profile first")
    rows = db.scalars(select(PilotLedgerEntry).where(PilotLedgerEntry.wallet_vpa == profile.vpa_id).order_by(desc(PilotLedgerEntry.created_at)).limit(limit)).all()
    return [{"id": x.id, "transfer_ref": x.transfer_ref, "wallet_vpa": x.wallet_vpa, "direction": x.direction,
        "amount": str(x.amount), "balance_after": str(x.balance_after), "created_at": x.created_at.isoformat(),
        "ledger_type": "TRACEPAY_INTERNAL_LEDGER"} for x in rows]

@app.post("/api/v1/pilot/admin/fund", status_code=201)
async def fund_pilot_wallet(body: PilotFundingIn, db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst"))):
    vpa = body.vpa_id
    profile = db.scalar(select(PilotProfile).where(PilotProfile.vpa_id == vpa))
    merchant = db.scalar(select(PilotMerchant).where(PilotMerchant.vpa_id == vpa))
    if not profile and not merchant: raise HTTPException(404, "Trace.Pay user or merchant not found")
    prior = db.scalar(select(AuditEvent).where(AuditEvent.action == "tracebank.wallet_funded", AuditEvent.object_ref == body.idempotency_key))
    if prior: return {"status": "SUCCESS", "message": "This funding request was already processed", "idempotency_key": body.idempotency_key}
    wallet = ensure_wallet(db, vpa)
    wallet.balance = (Decimal(str(wallet.balance)) + body.amount).quantize(Decimal("0.01"))
    funding_audit = AuditEvent(actor_user_id=user.id, action="tracebank.wallet_funded", object_ref=body.idempotency_key,
        detail=json.dumps({"vpa_id": vpa, "amount": str(body.amount), "note": body.note[:120], "source": "internal_ledger"}))
    db.add(funding_audit)
    db.add(PilotLedgerEntry(transfer_ref="FUND-" + uuid4().hex[:16].upper(), wallet_vpa=vpa, direction="CREDIT",
        amount=body.amount, balance_after=wallet.balance))
    db.commit(); db.refresh(wallet); db.refresh(funding_audit)
    await hub.publish({"type": "pilot.wallet_funded", "vpa_id": vpa, "amount": str(body.amount), "created_at": datetime.now(timezone.utc).isoformat()}, vpas={vpa})
    await hub.publish({"type": "activity", "id": funding_audit.id, "event_type": funding_audit.action, "object_ref": funding_audit.object_ref,
        "actor_user_id": user.id, "details": json.loads(funding_audit.detail), "created_at": funding_audit.created_at.isoformat()})
    return {"status": "SUCCESS", "wallet": wallet_json(wallet), "message": "Ledger balance allocated."}

@app.get("/api/v1/pilot/admin/wallets")
def list_pilot_wallets(db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst", "reviewer"))):
    wallets = db.scalars(select(PilotWallet).order_by(PilotWallet.owner_vpa)).all()
    return [wallet_json(w) for w in wallets]

@app.post("/api/v1/pilot/admin/generate-transfers", status_code=201)
async def generate_pilot_transfers(body: GeneratePilotTransfersIn, db: Session = Depends(get_db), user: User = Depends(require_roles("admin", "analyst"))):
    if body.max_amount < body.min_amount: raise HTTPException(422, "max_amount must be greater than or equal to min_amount")
    profiles = list(db.scalars(select(PilotProfile)).all())
    merchants = list(db.scalars(select(PilotMerchant).where(PilotMerchant.status == "active")).all())
    recipients = [(p.vpa_id, p.user_id) for p in profiles] + [(m.vpa_id, None) for m in merchants]
    if len(profiles) < 1 or len(recipients) < 2:
        raise HTTPException(409, "Register at least two Trace.Pay accounts or one account and one merchant before generating a batch")
    created = []
    for _ in range(body.count):
        sender = random.choice(profiles)
        possible = [r for r in recipients if r[0] != sender.vpa_id]
        receiver_vpa, _ = random.choice(possible)
        amount = Decimal(str(round(random.uniform(float(body.min_amount), float(body.max_amount)), 2))).quantize(Decimal("0.01"))
        try:
            transfer = execute_ledger_transfer(db, sender_vpa=sender.vpa_id, receiver_vpa=receiver_vpa,
                amount=amount, note="Admin-generated Trace.Pay ledger transfer", sender_user_id=sender.user_id,
                idempotency_key="batch:" + uuid4().hex, actor_user_id=user.id)
            created.append(transfer)
        except IntegrityError:
            db.rollback()
    succeeded = sum(1 for t in created if t.status == "SUCCESS")
    failed = len(created) - succeeded
    event = activity_event(db, actor_user_id=user.id, event_type="transfer.batch_processed",
        object_ref=f"batch:{created[0].transfer_ref}" if created else None,
        details={"created": len(created), "succeeded": succeeded, "failed": failed, "source": "internal_ledger"})
    await hub.publish({"type": "activity", "id": event.id, "event_type": event.action, "object_ref": event.object_ref,
        "actor_user_id": user.id, "details": json.loads(event.detail), "created_at": event.created_at.isoformat()})
    return {"created": len(created), "succeeded": succeeded, "failed": failed, "mode": "tracepay_internal_ledger",
        "transfers": [pilot_transfer_json(t) for t in created],
        "message": "Transfers were processed against the Trace.Pay internal ledger. SUCCESS means both ledger postings committed; FAILED means no value moved."}

@app.get("/api/v1/pilot/transfers")
def list_pilot_transfers(limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db), user: User = Depends(current_user)):
    stmt = select(PilotTransfer).order_by(desc(PilotTransfer.created_at)).limit(limit)
    if user.role not in OPS_ROLES:
        # Participants see transfers they sent and transfers they received.
        own_vpa = db.scalar(select(PilotProfile.vpa_id).where(PilotProfile.user_id == user.id))
        cond = PilotTransfer.sender_user_id == user.id
        if own_vpa:
            cond = cond | ((PilotTransfer.receiver_vpa == own_vpa) & (PilotTransfer.status == "SUCCESS"))
        stmt = select(PilotTransfer).where(cond).order_by(desc(PilotTransfer.created_at)).limit(limit)
    return [pilot_transfer_json(t) for t in db.scalars(stmt).all()]

@app.get("/api/v1/pilot/health")
def pilot_health(user: User = Depends(current_user)):
    try: redis_client.ping(); redis_status = "connected"
    except redis.RedisError: redis_status = "unavailable"
    return {"pilot_mode": "TRACEBANK_CLOSED_LOOP_LEDGER", "ledger": "connected", "redis": redis_status, "real_upi_connected": False,
        "message": "Internal TraceBank test-value transfers are processed by a double-entry ledger. No bank funds or UPI rails are involved."}

@app.websocket("/ws/live")
async def live_updates(ws: WebSocket, token: str = ""):
    # Browsers cannot attach custom Authorization headers to a WebSocket handshake.
    # Validate the short-lived bearer token before accepting the connection.
    import jwt
    from .security import JWT_SECRET, JWT_ALGORITHM
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        with SessionLocal() as db:
            user = db.get(User, int(payload["sub"]))
            if not user or not user.active: raise ValueError("inactive")
            profile_vpa = db.scalar(select(PilotProfile.vpa_id).where(PilotProfile.user_id == user.id))
            user_id, role = user.id, user.role
    except Exception:
        await ws.close(code=1008, reason="Authentication required")
        return
    await hub.connect(ws, user_id=user_id, role=role, vpa=profile_vpa)
    try:
        while True: await ws.receive_text()
    except WebSocketDisconnect: hub.disconnect(ws)
