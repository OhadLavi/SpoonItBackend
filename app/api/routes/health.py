"""Health check endpoint."""

import asyncio
import logging
from typing import Any, Dict

import httpx
from fastapi import APIRouter

from app.config import settings
from app.middleware.performance import metrics

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


@router.get("/metrics")
async def performance_metrics() -> Dict[str, Any]:
    """
    Get performance metrics.
    
    Returns:
        Performance metrics including request counts, durations, and error rates
    """
    return {
        "status": "ok",
        **metrics.get_summary()
    }

