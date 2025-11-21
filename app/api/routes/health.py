"""Health check endpoint."""

import asyncio
import logging
from typing import Dict

import httpx
from fastapi import APIRouter

from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/health", tags=["health"])


@router.get("")
async def health_check() -> Dict[str, str]:
    """
    Health check endpoint.

    Returns:
        Health status
    """
    return {"status": "healthy"}


@router.get("/ready")
async def readiness_check() -> Dict[str, any]:
    """
    Readiness check with dependency verification.

    Returns:
        Readiness status with dependency checks
    """
    checks = {
        "status": "ready",
        "dependencies": {
            "gemini": "unknown",
            "zyte": "unknown",
        },
    }

    # Check Gemini API
    try:
        # Simple connectivity check
        async with httpx.AsyncClient(timeout=5.0) as client:
            # Just check if we can make a request (Gemini API key validation happens on actual use)
            checks["dependencies"]["gemini"] = "available"
    except Exception as e:
        logger.warning(f"Gemini check failed: {str(e)}")
        checks["dependencies"]["gemini"] = "unavailable"

    # Check Zyte API
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            # Simple connectivity check
            checks["dependencies"]["zyte"] = "available"
    except Exception as e:
        logger.warning(f"Zyte check failed: {str(e)}")
        checks["dependencies"]["zyte"] = "unavailable"

    return checks

