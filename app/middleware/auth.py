"""API key authentication middleware."""

from fastapi import Header, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from app.config import settings
from app.utils.exceptions import AuthenticationError

security = HTTPBearer(auto_error=False)


async def verify_api_key(
    x_api_key: str = Header(None, alias="X-API-Key"),
    authorization: HTTPAuthorizationCredentials = None,
) -> str:
    """
    Verify API key from header.

    Args:
        x_api_key: API key from X-API-Key header
        authorization: Optional Bearer token

    Returns:
        API key string if valid

    Raises:
        HTTPException: If API key is missing or invalid
    """
    # Check X-API-Key header first
    api_key = x_api_key

    # Fallback to Authorization header if X-API-Key not provided
    if not api_key and authorization:
        api_key = authorization.credentials

    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing API key. Provide X-API-Key header or Authorization Bearer token.",
        )

    # Check if API key is valid
    if api_key not in settings.valid_api_keys:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key.",
        )

    return api_key

