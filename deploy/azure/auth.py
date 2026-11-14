"""Entra bearer-token verification; fails closed without explicit configuration."""
import os
import jwt
from jwt import PyJWKClient

TENANT = os.environ.get("ENTRA_TENANT_ID", "")
AUDIENCE = os.environ.get("ENTRA_AUDIENCE", "")
SCOPE = os.environ.get("ENTRA_REQUIRED_SCOPE", "AgentReach.Invoke")
if not TENANT or not AUDIENCE or not TENANT.replace("-", "").isalnum():
    raise RuntimeError("ENTRA_TENANT_ID and ENTRA_AUDIENCE are required")
ISSUER = f"https://login.microsoftonline.com/{TENANT}/v2.0"
JWKS = PyJWKClient(f"https://login.microsoftonline.com/{TENANT}/discovery/v2.0/keys")

def verify(authorization: str) -> dict:
    if not authorization.startswith("Bearer "):
        raise ValueError("Bearer token required")
    token = authorization[7:].strip()
    if not token or len(token) > 16384:
        raise ValueError("Invalid bearer token")
    key = JWKS.get_signing_key_from_jwt(token)
    claims = jwt.decode(token, key.key, algorithms=["RS256"], audience=AUDIENCE, issuer=ISSUER, options={"require": ["exp", "iat", "iss", "aud"]}, leeway=30)
    scopes = set(claims.get("scp", "").split())
    if SCOPE not in scopes:
        raise ValueError("Required delegated scope missing")
    return claims
