"""Health check endpoint."""

import asyncio
import logging
from typing import Any, Dict

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
async def readiness_check() -> Dict[str, Any]:
    """
    Readiness check for Cloud Run.
    Called before traffic is routed to this instance.
    """
    return {
        "status": "ready",
        "startup": True
    }


