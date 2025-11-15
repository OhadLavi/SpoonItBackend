# main.py
"""SpoonIt API - Recipe extraction and generation service."""

from __future__ import annotations

import os
import uvicorn
import requests
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from config import logger
from errors import APIError
from routes import chat, extraction, proxy


# =============================================================================
# FastAPI app
# =============================================================================
app = FastAPI(
    title="SpoonIt API",
    version="1.3.2",
    description=(
        "Generic recipe extraction via schema.org, DOM heuristics (Hebrew/English), "
        "and LLM fallback."
    ),
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # adjust if you want stricter CORS
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition", "Access-Control-Allow-Origin"],
)


@app.exception_handler(APIError)
async def api_error_handler(request, exc: APIError):
    """Handle custom API errors and return consistent JSON."""
    logger.error("APIError: %s | details=%s", exc.message, exc.details)
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.message, "details": exc.details},
    )


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {"message": "Welcome to SpoonIt API", "docs": "/docs", "redoc": "/redoc"}


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok"}


@app.get("/ip")
async def ip_check():
    """Return the public IP of outbound Cloud Run traffic."""
    try:
        r = requests.get("https://api64.ipify.org?format=json", timeout=10)
        return {"ip": r.json().get("ip")}
    except Exception as e:
        logger.error("IP check failed: %s", e, exc_info=True)
        return {"error": str(e)}


# =============================================================================
# Include routers
# =============================================================================
# NOTE: no prefix here → routes keep their existing paths:
# /chat, /extract_recipe, /extract_recipe_from_image, /upload_recipe_image, etc.
app.include_router(chat.router, tags=["Chat"])
app.include_router(extraction.router, tags=["Extraction"])
app.include_router(proxy.router, tags=["Proxy"])


# =============================================================================
# Entrypoint
# =============================================================================
if __name__ == "__main__":
    # Cloud Run requires listening on 0.0.0.0:$PORT (defaults to 8080).
    port = int(os.getenv("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)
