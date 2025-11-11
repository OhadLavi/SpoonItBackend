# routes/proxy.py
"""Image proxy endpoint for CORS bypass."""

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
import httpx
from bs4 import BeautifulSoup

from config import logger, HTTP_TIMEOUT
from errors import APIError

router = APIRouter()


@router.get("/proxy_image")
async def proxy_image(url: str):
    """Proxy image requests to bypass CORS restrictions."""
    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, follow_redirects=True) as client:
            r = await client.get(url)
            r.raise_for_status()
            content_type = r.headers.get("Content-Type", "image/jpeg")
            content = r.content

            if not content_type or not content_type.startswith("image/"):
                logger.warning("[PROXY] Non-image content type: %s for URL: %s", content_type, url)
                if content_type and "text/html" in content_type:
                    soup = BeautifulSoup(content, "html.parser")
                    img_tags = soup.find_all("img")
                    if img_tags:
                        for img in img_tags:
                            src = img.get("src")
                            if src and (src.startswith("http") or src.startswith("//")):
                                if src.startswith("//"):
                                    src = "https:" + src
                                logger.info("[PROXY] Found image in HTML: %s", src)
                                return await proxy_image(src)

                raise HTTPException(status_code=400, detail="URL does not point to an image")

        return Response(
            content=content,
            media_type=content_type,
            headers={"Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=86400"},
        )
    except Exception as e:
        logger.error("[PROXY] error: %s", e, exc_info=True)
        raise APIError(f"Failed to proxy image: {str(e)}", status_code=500)

