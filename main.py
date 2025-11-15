# main.py
"""SpoonIt / Recipe Keeper backend – FastAPI entrypoint."""

from __future__ import annotations

import os

import uvicorn
import requests
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from config import logger
from errors import APIError
from routes import chat, extraction, proxy


app = FastAPI(
    title="SpoonIt API",
    version="2.0.0",
    description=(
        "Recipe extraction and generation service. "
        "Uses Gemini for all LLM-based tasks and Zyte only as a content fetch fallback."
    ),
)

# ---------------------------------------------------------------------------
# CORS
# ---------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten later if needed
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition", "Access-Control-Allow-Origin"],
)


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------
@app.exception_handler(APIError)
async def api_error_handler(request: Request, exc: APIError):
    """Consistent JSON for custom API errors."""
    logger.error(
        "APIError | path=%s | status=%s | msg=%s | details=%s",
        request.url.path,
        exc.status_code,
        exc.message,
        exc.details,
    )
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.message, "details": exc.details},
    )


# ---------------------------------------------------------------------------
# Basic endpoints
# ---------------------------------------------------------------------------
@app.get("/")
async def root():
    return {"message": "Welcome to SpoonIt API", "docs": "/docs", "redoc": "/redoc"}


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/ip")
async def ip_check():
    """Return outbound public IP (useful when debugging Cloud Run / Zyte)."""
    try:
        r = requests.get("https://api64.ipify.org?format=json", timeout=10)
        return {"ip": r.json().get("ip")}
    except Exception as e:  # pragma: no cover
        logger.error("IP check failed: %s", e, exc_info=True)
        return {"error": str(e)}


# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------
app.include_router(extraction.router, tags=["Extraction"])
app.include_router(chat.router, tags=["Chat"])
app.include_router(proxy.router, tags=["Proxy"])


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
if __name__ == "__main__":  # pragma: no cover
    port = int(os.getenv("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)
