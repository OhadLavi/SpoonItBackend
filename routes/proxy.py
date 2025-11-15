# routes/proxy.py
"""Image proxy endpoint for CORS bypass."""

from __future__ import annotations

import httpx
from bs4 import BeautifulSoup
from fastapi import APIRouter, HTTPException
from fastapi.responses import Response

from config import HTTP_TIMEOUT, logger
from errors import APIError

router = APIRouter()


@router.get("/proxy_image")
async def proxy_image(url: str):
    """Proxy image requests to bypass CORS restrictions."""
    try:
        async with httpx.AsyncClient(
            timeout=HTTP_TIMEOUT, follow_redirects=True
        ) as client:
            r = await client.get(url)
            r.raise_for_status()
            content_type = r.headers.get("Content-Type", "image/jpeg")
            content = r.content

            if not content_type or not content_type.startswith("image/"):
                logger.warning(
                    "[PROXY] Non-image content type: %s for URL: %s",
                    content_type,
                    url,
                )
                if content_type and "text/html" in content_type:
                    soup = BeautifulSoup(content, "html.parser")
                    img_tags = soup.find_all("img")
                    for img in img_tags:
                        src = img.get("src")
                        if not src:
                            continue
                        if src.startswith("//"):
                            src = "https:" + src
                        if src.startswith("http"):
                            logger.info("[PROXY] Found nested image in HTML: %s", src)
                            # recurse once
                            async with httpx.AsyncClient(
                                timeout=HTTP_TIMEOUT, follow_redirects=True
                            ) as client2:
                                r2 = await client2.get(src)
                                r2.raise_for_status()
                                return Response(
                                    content=r2.content,
                                    media_type=r2.headers.get(
                                        "Content-Type", "image/jpeg"
                                    ),
                                    headers={
                                        "Access-Control-Allow-Origin": "*",
                                        "Cache-Control": "public, max-age=86400",
                                    },
                                )

                raise HTTPException(status_code=400, detail="URL does not point to an image")

        return Response(
            content=content,
            media_type=content_type,
            headers={"Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=86400"},
        )
    except HTTPException:
        raise
    except Exception as e:  # pragma: no cover
        logger.error("[PROXY] error: %s", e, exc_info=True)
        raise APIError(f"Failed to proxy image: {str(e)}", status_code=500)
