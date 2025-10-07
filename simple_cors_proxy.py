#!/usr/bin/env python3
"""
Simple CORS proxy server for images
"""
import asyncio
import logging
from urllib.parse import urlparse
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/proxy_image")
async def proxy_image(url: str):
    """Proxy images with CORS headers"""
    try:
        logger.info(f"Proxying image: {url}")
        
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            response = await client.get(url)
            response.raise_for_status()
            
            content_type = response.headers.get("Content-Type", "image/jpeg")
            content = response.content
            
            # Check if it's actually an image
            if not content_type.startswith("image/"):
                logger.warning(f"Non-image content type: {content_type}")
                raise HTTPException(status_code=400, detail="URL does not point to an image")
            
            logger.info(f"Successfully proxied image: {content_type}, {len(content)} bytes")
            
            return Response(
                content=content,
                media_type=content_type,
                headers={
                    "Access-Control-Allow-Origin": "*",
                    "Cache-Control": "public, max-age=86400"
                }
            )
            
    except Exception as e:
        logger.error(f"Proxy error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to proxy image: {str(e)}")

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "ok"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
