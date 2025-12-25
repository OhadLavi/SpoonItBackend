"""Web extraction service using Gemini url_context (TEXT ONLY)."""

from __future__ import annotations

import logging
from typing import Optional

from google import genai
from google.genai import types

from app.config import settings
from app.utils.exceptions import ScrapingError
from app.services.gemini_utils import get_response_text

logger = logging.getLogger(__name__)


class ScraperService:
    """Service for fetching recipe text from URLs using Gemini url_context."""

    def __init__(self):
        self._client: Optional[genai.Client] = None

    @property
    def client(self) -> genai.Client:
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    async def fetch_recipe_text_via_url_context(self, url: str) -> str:
        """
        Tool use + application/json is unsupported.
        So url_context must be text/plain, then JSON is created in a second call without tools.
        """
        prompt = self._build_url_text_prompt(url)

        last_text = ""
        for attempt in (1, 2):
            try:
                response = await self.client.aio.models.generate_content(
                    model="gemini-2.5-flash",
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        tools=[{"url_context": {}}],
                        response_mime_type="text/plain",
                        temperature=0.0,
                        max_output_tokens=3072,
                    ),
                )

                text = get_response_text(response).strip()
                last_text = text

                # Handle explicit sentinel
                if text.strip() == "UNABLE_TO_ACCESS_PAGE":
                    raise ScrapingError("url_context could not access the page (sentinel returned).")

                if text:
                    return text

                logger.warning(f"url_context returned empty text (attempt {attempt}/2).")

            except Exception as e:
                if attempt == 2:
                    logger.error(f"url_context fetch failed (final): {str(e)}", exc_info=True)
                    raise ScrapingError(f"Failed to fetch recipe text via url_context: {str(e)}") from e
                logger.warning(f"url_context attempt {attempt} failed: {e}")

        # Shouldn't reach here
        raise ScrapingError(f"url_context returned empty text after retries. last_text_len={len(last_text)}")

    def _build_url_text_prompt(self, url: str) -> str:
        return f"""
Use url_context to access and read this URL:
{url}

TASK:
Extract ONLY the recipe content exactly as it appears on the page.

If you cannot access/read the page for any reason, output EXACTLY:
UNABLE_TO_ACCESS_PAGE

STRICT RULES:
- Preserve ingredient lines and measurements EXACTLY as written.
- Do NOT normalize, translate, or convert units.
- Do NOT invent missing ingredients/steps.
- Output MUST be plain text, organized as:

TITLE:
<one line>

DESCRIPTION:
<one paragraph or empty>

INGREDIENTS:
- <line 1 exactly>
- <line 2 exactly>
...

INSTRUCTIONS:
1. <step 1 exactly>
2. <step 2 exactly>
...

NOTES:
- <note 1 exactly>
- <note 2 exactly>

IMAGES:
- <image url 1 if present>
- <image url 2 if present>

If a section does not exist, output it but leave it empty.
Return plain text ONLY (no JSON, no markdown).
""".strip()
