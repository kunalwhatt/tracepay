from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Numeric, ForeignKey, Text, Boolean, UniqueConstraint, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .db import Base

def utcnow(): return datetime.now(timezone.utc)

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(32), default="analyst")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

class Account(Base):
    __tablename__ = "accounts"
    id: Mapped[int] = mapped_column(primary_key=True)
    external_ref: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

class Transaction(Base):
    __tablename__ = "transactions"
    __table_args__ = (UniqueConstraint("source_id", "source_record_ref", name="uq_source_record"), Index("ix_tx_time", "occurred_at"), Index("ix_tx_sender_time", "sender_id", "occurred_at"))
    id: Mapped[int] = mapped_column(primary_key=True)
    transaction_ref: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    event_id: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    sender_id: Mapped[str] = mapped_column(String(255), index=True)
    receiver_id: Mapped[str] = mapped_column(String(255), index=True)
    amount: Mapped[float] = mapped_column(Numeric(18, 2))
    currency: Mapped[str] = mapped_column(String(3), default="INR")
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    source_id: Mapped[str] = mapped_column(String(255), index=True)
    source_record_ref: Mapped[str] = mapped_column(String(255))
    provenance_status: Mapped[str] = mapped_column(String(32), default="observed")
    ingested_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    # Provenance: which upload, file, sheet and row produced this record.
    ingestion_job_id: Mapped[int | None] = mapped_column(nullable=True, index=True)
    source_file: Mapped[str | None] = mapped_column(String(255), nullable=True)
    source_sheet: Mapped[str | None] = mapped_column(String(128), nullable=True)
    source_row: Mapped[int | None] = mapped_column(nullable=True)
    fingerprint: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)

class RiskAssessment(Base):
    __tablename__ = "risk_assessments"
    id: Mapped[int] = mapped_column(primary_key=True)
    recipient_ref: Mapped[str] = mapped_column(String(255), index=True)
    level: Mapped[str] = mapped_column(String(24))
    reasons_json: Mapped[str] = mapped_column(Text)
    transaction_count: Mapped[int] = mapped_column(default=0)
    rule_version: Mapped[str] = mapped_column(String(64), default="rules-v1")
    evidence_json: Mapped[str] = mapped_column(Text, default="[]")
    window_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    window_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    assessed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

class IngestionJob(Base):
    __tablename__ = "ingestion_jobs"
    id: Mapped[int] = mapped_column(primary_key=True)
    source_id: Mapped[str] = mapped_column(String(255), index=True)
    status: Mapped[str] = mapped_column(String(32), default="processing")
    received: Mapped[int] = mapped_column(default=0)
    accepted: Mapped[int] = mapped_column(default=0)
    rejected: Mapped[int] = mapped_column(default=0)
    duplicates: Mapped[int] = mapped_column(default=0)
    conflicts: Mapped[int] = mapped_column(default=0)
    filename: Mapped[str | None] = mapped_column(String(255), nullable=True)
    checksum_sha256: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    raw_blob_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    errors_json: Mapped[str] = mapped_column(Text, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

class AuditEvent(Base):
    __tablename__ = "audit_events"
    id: Mapped[int] = mapped_column(primary_key=True)
    actor_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    action: Mapped[str] = mapped_column(String(128), index=True)
    object_ref: Mapped[str | None] = mapped_column(String(255), nullable=True)
    detail: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class PaymentIntent(Base):
    __tablename__ = "payment_intents"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    assessment_id: Mapped[int] = mapped_column(ForeignKey("risk_assessments.id"), index=True)
    recipient_ref: Mapped[str] = mapped_column(String(255), index=True)
    amount: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
    currency: Mapped[str] = mapped_column(String(3), default="INR")
    note: Mapped[str] = mapped_column(String(255), default="")
    status: Mapped[str] = mapped_column(String(32), default="created")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

# Pilot-only identity and transaction records. These never represent bank settlement.
class PilotProfile(Base):
    __tablename__ = "pilot_profiles"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True, index=True)
    # Encrypted Fernet payloads are longer than their plaintext values.
    full_name: Mapped[str] = mapped_column(Text)
    date_of_birth: Mapped[str] = mapped_column(Text)
    vpa_id: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    bank_name: Mapped[str] = mapped_column(Text, default="")
    account_last4: Mapped[str] = mapped_column(Text, default="")
    participant_type: Mapped[str] = mapped_column(String(24), default="pilot_user")
    selfie_status: Mapped[str] = mapped_column(String(32), default="verified")
    gender: Mapped[str] = mapped_column(String(32), default="Prefer not to say")
    photo_storage_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    face_count: Mapped[int] = mapped_column(default=1)
    consent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

class PilotMerchant(Base):
    __tablename__ = "pilot_merchants"
    id: Mapped[int] = mapped_column(primary_key=True)
    display_name: Mapped[str] = mapped_column(String(160))
    vpa_id: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    category: Mapped[str] = mapped_column(String(80), default="General")
    location: Mapped[str] = mapped_column(String(160), default="")
    status: Mapped[str] = mapped_column(String(24), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

class PilotTransfer(Base):
    __tablename__ = "pilot_transfers"
    __table_args__ = (UniqueConstraint("sender_user_id", "idempotency_key", name="uq_pilot_transfer_idempotency"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    transfer_ref: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    sender_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    sender_vpa: Mapped[str] = mapped_column(String(255), index=True)
    receiver_vpa: Mapped[str] = mapped_column(String(255), index=True)
    amount: Mapped[float] = mapped_column(Numeric(18, 2))
    note: Mapped[str] = mapped_column(String(255), default="")
    status: Mapped[str] = mapped_column(String(32), default="SIMULATED_ONLY")
    mode: Mapped[str] = mapped_column(String(32), default="pilot_simulation")
    idempotency_key: Mapped[str] = mapped_column(String(100))
    failure_reason: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class PilotWallet(Base):
    """Closed-loop TraceBank pilot wallet. Balance is test value, not a bank deposit."""
    __tablename__ = "pilot_wallets"
    id: Mapped[int] = mapped_column(primary_key=True)
    owner_vpa: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    balance: Mapped[float] = mapped_column(Numeric(18, 2), default=0)
    currency: Mapped[str] = mapped_column(String(3), default="INR")
    status: Mapped[str] = mapped_column(String(24), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

class PilotLedgerEntry(Base):
    """Immutable double-entry posting; each successful transfer has debit and credit rows."""
    __tablename__ = "pilot_ledger_entries"
    __table_args__ = (UniqueConstraint("transfer_ref", "wallet_vpa", "direction", name="uq_pilot_ledger_posting"), Index("ix_pilot_ledger_wallet_time", "wallet_vpa", "created_at"))
    id: Mapped[int] = mapped_column(primary_key=True)
    transfer_ref: Mapped[str] = mapped_column(String(40), index=True)
    wallet_vpa: Mapped[str] = mapped_column(String(255), index=True)
    direction: Mapped[str] = mapped_column(String(8))
    amount: Mapped[float] = mapped_column(Numeric(18, 2))
    balance_after: Mapped[float] = mapped_column(Numeric(18, 2))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)



class InvestigationCase(Base):
    __tablename__ = "investigation_cases"
    id: Mapped[int] = mapped_column(primary_key=True)
    case_ref: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(180))
    status: Mapped[str] = mapped_column(String(24), default="OPEN")
    description: Mapped[str] = mapped_column(Text, default="")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

class InvestigationReport(Base):
    __tablename__ = "investigation_reports"
    id: Mapped[int] = mapped_column(primary_key=True)
    report_ref: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(180))
    report_type: Mapped[str] = mapped_column(String(40), default="evidence")
    status: Mapped[str] = mapped_column(String(24), default="DRAFT")
    case_ref: Mapped[str | None] = mapped_column(String(40), nullable=True, index=True)
    body: Mapped[str] = mapped_column(Text, default="")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class SourceConflict(Base):
    """Two sources disagree about the same transaction reference. Both versions are preserved;
    the existing record is never silently overwritten."""
    __tablename__ = "source_conflicts"
    id: Mapped[int] = mapped_column(primary_key=True)
    transaction_ref: Mapped[str] = mapped_column(String(128), index=True)
    existing_transaction_id: Mapped[int] = mapped_column(ForeignKey("transactions.id"), index=True)
    ingestion_job_id: Mapped[int | None] = mapped_column(ForeignKey("ingestion_jobs.id"), nullable=True, index=True)
    differing_fields: Mapped[str] = mapped_column(String(255))
    incoming_json: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(24), default="UNRESOLVED")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
