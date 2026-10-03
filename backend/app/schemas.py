from datetime import datetime
from decimal import Decimal
from pydantic import BaseModel, EmailStr, Field, ConfigDict, field_validator

class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=12, max_length=128)

    @field_validator("password")
    @classmethod
    def strong_password(cls, value: str) -> str:
        import re
        if not re.search(r"[A-Z]", value): raise ValueError("Password must include at least one uppercase letter")
        if not re.search(r"[0-9]", value): raise ValueError("Password must include at least one number")
        if not re.search(r"[^A-Za-z0-9]", value): raise ValueError("Password must include at least one special character")
        return value

class LoginIn(BaseModel):
    email: EmailStr
    password: str

class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str

class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    email: EmailStr
    role: str

class RiskIn(BaseModel):
    recipient_ref: str = Field(min_length=3, max_length=255)
    # Optional evaluation time. Omit for the live payment flow; investigators can assess a historical window.
    as_of: datetime | None = None

class RiskOut(BaseModel):
    assessment_id: int
    recipient_ref: str
    level: str
    reasons: list[str]
    observed_transaction_count: int
    data_as_of: datetime
    rule_version: str
    disclaimer: str
    evidence: list[dict] = []
    window_start: datetime | None = None
    window_end: datetime | None = None

class TransactionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    transaction_ref: str
    event_id: str
    sender_id: str
    receiver_id: str
    amount: Decimal
    currency: str
    occurred_at: datetime
    source_id: str
    source_record_ref: str
    provenance_status: str
    ingested_at: datetime
    ingestion_job_id: int | None = None
    source_file: str | None = None
    source_sheet: str | None = None
    source_row: int | None = None

class IngestionOut(BaseModel):
    job_id: int
    status: str
    received: int
    accepted: int
    rejected: int
    duplicates: int
    errors: list[str]
    conflicts: int = 0
    checksum_sha256: str | None = None
    raw_archived: bool = False


class PaymentIntentIn(BaseModel):
    assessment_id: int
    recipient_ref: str = Field(min_length=3, max_length=255)
    amount: Decimal | None = Field(default=None, gt=0, le=10000000)
    note: str = Field(default="", max_length=255)

class PaymentIntentOut(BaseModel):
    id: int
    recipient_ref: str
    amount: Decimal | None
    currency: str
    status: str
    created_at: datetime
    disclaimer: str


class CaseIn(BaseModel):
    title: str = Field(min_length=2, max_length=180)
    description: str = Field(default="", max_length=4000)

class CaseOut(BaseModel):
    id: int
    case_ref: str
    title: str
    status: str
    description: str
    created_by: int
    created_at: datetime
    updated_at: datetime

class ReportIn(BaseModel):
    title: str = Field(min_length=2, max_length=180)
    report_type: str = Field(default="evidence", max_length=40)
    case_ref: str | None = Field(default=None, max_length=40)
    body: str = Field(default="", max_length=12000)

class ReportOut(BaseModel):
    id: int
    report_ref: str
    title: str
    report_type: str
    status: str
    case_ref: str | None
    body: str
    created_by: int
    created_at: datetime
