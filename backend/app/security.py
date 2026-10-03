import os
from datetime import datetime, timedelta, timezone
import jwt
from pwdlib import PasswordHash
from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from .db import get_db
from .models import User

password_hash = PasswordHash.recommended()
JWT_SECRET = os.environ["JWT_SECRET"]
JWT_ALGORITHM = "HS256"
security = HTTPBearer(auto_error=False)

def hash_password(password: str) -> str:
    return password_hash.hash(password)

def verify_password(password: str, hashed: str) -> bool:
    return password_hash.verify(password, hashed)

ACCESS_TOKEN_MINUTES = 20
MAX_SESSION_HOURS = 12  # a session can be renewed, but never beyond this long after the original sign-in


def create_token(user: User, auth_time: datetime | None = None) -> str:
    now = datetime.now(timezone.utc)
    auth_time = auth_time or now
    payload = {"sub": str(user.id), "role": user.role, "iat": now, "auth_time": int(auth_time.timestamp()),
               "exp": now + timedelta(minutes=ACCESS_TOKEN_MINUTES)}
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def renew_token(user: User, token: str) -> str:
    """Issue a fresh 20-minute token for a still-valid session, up to MAX_SESSION_HOURS after sign-in."""
    payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    auth_time = datetime.fromtimestamp(int(payload.get("auth_time") or payload["iat"]), tz=timezone.utc)
    if datetime.now(timezone.utc) - auth_time > timedelta(hours=MAX_SESSION_HOURS):
        raise HTTPException(401, "Session has reached its maximum length. Please sign in again.")
    return create_token(user, auth_time)

def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(security), db: Session = Depends(get_db)) -> User:
    if not credentials:
        raise HTTPException(401, "Authentication required")
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = int(payload["sub"])
    except (jwt.InvalidTokenError, KeyError, ValueError):
        raise HTTPException(401, "Invalid or expired access token")
    user = db.get(User, user_id)
    if not user or not user.active:
        raise HTTPException(401, "User is inactive or no longer exists")
    return user

def require_roles(*roles: str):
    def dependency(user: User = Depends(current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(403, "Insufficient permissions")
        return user
    return dependency
