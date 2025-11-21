"""Web scraping service with Zyte fallback."""

import logging
from typing import Optional

import httpx

from app.config import settings
from app.utils.exceptions import ScrapingError, ZyteError

logger = logging.getLogger(__name__)


class ScraperService:
    """Service for scraping recipe content from URLs."""

    def __init__(self):
        """Initialize scraper service."""
        self.timeout = settings.http_timeout
        self.zyte_timeout = settings.zyte_timeout

    async def fetch_recipe_content(self, url: str) -> str:
        """
        Fetch recipe content from URL, using Zyte if direct scraping fails.

        Args:
            url: Recipe URL to scrape

        Returns:
            Extracted text content

        Raises:
            ScrapingError: If scraping fails
        """
        # Try direct HTTP request first
        try:
            content = await self._fetch_direct(url)
            logger.info(f"Successfully fetched content directly from {url}")
            return content
        except Exception as e:
            logger.warning(f"Direct fetch failed for {url}: {str(e)}, trying Zyte...")
            # Fallback to Zyte
            try:
                content = await self._fetch_with_zyte(url)
                logger.info(f"Successfully fetched content via Zyte from {url}")
                return content
            except Exception as zyte_error:
                logger.error(f"Both direct and Zyte fetch failed for {url}")
                raise ScrapingError(
                    f"Failed to fetch content: Direct fetch failed ({str(e)}), "
                    f"Zyte fetch failed ({str(zyte_error)})"
                ) from zyte_error

    async def _fetch_direct(self, url: str) -> str:
        """
        Fetch content directly via HTTP.

        Args:
            url: URL to fetch

        Returns:
            HTML content as string

        Raises:
            ScrapingError: If fetch fails
        """
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        }

        async with httpx.AsyncClient(timeout=self.timeout, follow_redirects=True) as client:
            try:
                response = await client.get(url, headers=headers)
                response.raise_for_status()

                # Check if blocked (403, 429, etc.)
                if response.status_code in (403, 429, 451):
                    raise ScrapingError(f"Access blocked (HTTP {response.status_code})")

                return response.text

            except httpx.HTTPStatusError as e:
                raise ScrapingError(f"HTTP error {e.response.status_code}: {str(e)}") from e
            except httpx.TimeoutException as e:
                raise ScrapingError(f"Request timeout: {str(e)}") from e
            except httpx.RequestError as e:
                raise ScrapingError(f"Request failed: {str(e)}") from e

    async def _fetch_with_zyte(self, url: str) -> str:
        """
        Fetch content using Zyte Extract API (pageContent mode).

        Args:
            url: URL to fetch

        Returns:
            Extracted text content

        Raises:
            ZyteError: If Zyte API call fails
        """
        zyte_url = "https://api.zyte.com/v1/extract"

        payload = {
            "url": url,
            "browserHtml": True,
            "extractionType": "pageContent",
        }

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"apikey {settings.zyte_api_key}",
        }

        async with httpx.AsyncClient(timeout=self.zyte_timeout) as client:
            try:
                response = await client.post(zyte_url, json=payload, headers=headers)
                response.raise_for_status()

                data = response.json()
                # Zyte returns content in different formats depending on extractionType
                # For pageContent, it should return the cleaned text
                if "pageContent" in data:
                    return data["pageContent"]
                elif "browserHtml" in data:
                    # Fallback to HTML if pageContent not available
                    return data["browserHtml"]
                else:
                    raise ZyteError("Unexpected Zyte response format")

            except httpx.HTTPStatusError as e:
                raise ZyteError(f"Zyte API HTTP error {e.response.status_code}: {str(e)}") from e
            except httpx.TimeoutException as e:
                raise ZyteError(f"Zyte API timeout: {str(e)}") from e
            except httpx.RequestError as e:
                raise ZyteError(f"Zyte API request failed: {str(e)}") from e
            except KeyError as e:
                raise ZyteError(f"Unexpected Zyte response format: {str(e)}") from e

