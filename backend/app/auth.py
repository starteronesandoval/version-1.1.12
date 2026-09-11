from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from google.auth.exceptions import GoogleAuthError
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from jwt import InvalidTokenError
from pwdlib import PasswordHash
from sqlalchemy.orm import Session

from .config import settings
from .database import get_db
from .models import User, UserRole


password_hash = PasswordHash.recommended()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


def hash_password(password: str) -> str:
    return password_hash.hash(password)


def verify_password(password: str, hashed: str) -> bool:
    # A damaged or legacy value in the database must be treated as invalid
    # credentials instead of turning the login endpoint into a 500 response.
    try:
        return password_hash.verify(password, hashed)
    except Exception:
        return False


def verify_google_token(token: str) -> dict:
    if not settings.google_client_ids:
        raise HTTPException(
            status_code=503,
            detail="El acceso con Google todavía no está configurado",
        )
    for audience in settings.google_client_ids:
        try:
            claims = google_id_token.verify_oauth2_token(
                token, google_requests.Request(), audience=audience
            )
        except (ValueError, GoogleAuthError):
            continue
        if claims.get("email_verified") is not True:
            raise HTTPException(
                status_code=401, detail="Google no verificó este correo"
            )
        if not claims.get("sub") or not claims.get("email"):
            raise HTTPException(
                status_code=401, detail="La cuenta de Google está incompleta"
            )
        return claims
    raise HTTPException(status_code=401, detail="Token de Google inválido")


def create_token(user: User) -> str:
    expires = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_minutes)
    return jwt.encode({"sub": str(user.id), "role": user.role.value, "exp": expires}, settings.secret_key, algorithm="HS256")


def current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    credentials_error = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Credenciales inválidas")
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        user_id = int(payload.get("sub", ""))
    except (InvalidTokenError, ValueError):
        raise credentials_error
    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise credentials_error
    return user


def require_role(role: UserRole):
    def check(user: User = Depends(current_user)) -> User:
        if user.role != role:
            raise HTTPException(status_code=403, detail="Este recurso no corresponde a tu modalidad")
        return user
    return check
