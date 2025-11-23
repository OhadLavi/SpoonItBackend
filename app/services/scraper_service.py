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
        Fetch recipe content from URL, using Zyte if direct scraping fails or returns insufficient content.

        Args:
            url: Recipe URL to scrape

        Returns:
            Extracted text content

        Raises:
            ScrapingError: If scraping fails or content is insufficient
        """
        MIN_CONTENT_LENGTH = 200  # Minimum chars for valid recipe content
        
        # Try direct HTTP request first
        try:
            content = await self._fetch_direct(url)
            
            # Check if content is sufficient
            if len(content) < MIN_CONTENT_LENGTH:
                logger.warning(
                    f"Direct fetch returned insufficient content ({len(content)} chars) from {url}, trying Zyte..."
                )
                # Force Zyte fallback for better content
                content = await self._fetch_with_zyte(url)
                logger.info(f"Successfully fetched content via Zyte from {url}")
                return content
            
            logger.info(f"Successfully fetched content directly from {url}")
            return content
            
        except ScrapingError:
            # If direct fetch threw ScrapingError, try Zyte
            logger.warning(f"Direct fetch failed for {url}, trying Zyte...")
            try:
                content = await self._fetch_with_zyte(url)
                logger.info(f"Successfully fetched content via Zyte from {url}")
                return content
            except Exception as zyte_error:
                logger.error(f"Both direct and Zyte fetch failed for {url}")
                raise ScrapingError(
                    f"Failed to fetch content: Direct fetch failed, "
                    f"Zyte fetch failed ({str(zyte_error)})"
                ) from zyte_error
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

                # Clean HTML before returning
                return self._clean_html(response.text)

            except httpx.HTTPStatusError as e:
                raise ScrapingError(f"HTTP error {e.response.status_code}: {str(e)}") from e
            except httpx.TimeoutException as e:
                raise ScrapingError(f"Request timeout: {str(e)}") from e
            except httpx.RequestError as e:
                raise ScrapingError(f"Request failed: {str(e)}") from e

    async def _fetch_with_zyte(self, url: str) -> str:
        """
        Fetch content using Zyte Extract API (httpResponseBody mode).

        Args:
            url: URL to fetch

        Returns:
            Extracted text content

        Raises:
            ZyteError: If Zyte API call fails
        """
        # Check if Zyte API key is configured
        if not settings.zyte_api_key or settings.zyte_api_key == "your_zyte_api_key_here":
            raise ZyteError("Zyte API key is not configured. Please set ZYTE_API_KEY environment variable.")
        
        zyte_url = "https://api.zyte.com/v1/extract"

        payload = {
            "url": url,
            "httpResponseBody": True,
            "followRedirect": True,
        }

        headers = {
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=self.zyte_timeout) as client:
            try:
                response = await client.post(
                    zyte_url, 
                    json=payload, 
                    headers=headers,
                    auth=(settings.zyte_api_key, "")
                )
                response.raise_for_status()

                data = response.json()
                
                if "httpResponseBody" in data:
                    # Decode base64 response body
                    import base64
                    from bs4 import BeautifulSoup
                    
                    html_content = base64.b64decode(data["httpResponseBody"]).decode("utf-8")
                    return self._clean_html(html_content)
                else:
                    raise ZyteError("Unexpected Zyte response format: missing httpResponseBody")

            except httpx.HTTPStatusError as e:
                raise ZyteError(f"Zyte API HTTP error {e.response.status_code}: {str(e)}") from e
            except httpx.TimeoutException as e:
                raise ZyteError(f"Zyte API timeout: {str(e)}") from e
            except httpx.RequestError as e:
                raise ZyteError(f"Zyte API request failed: {str(e)}") from e
            except KeyError as e:
                raise ZyteError(f"Unexpected Zyte response format: {str(e)}") from e
            except Exception as e:
                raise ZyteError(f"Error processing Zyte response: {str(e)}") from e

    def _clean_html(self, html_content: str) -> str:
        """
        Clean HTML content by removing scripts, styles and extracting text.
        
        Args:
            html_content: Raw HTML string
            
        Returns:
            Cleaned text content
        """
        from bs4 import BeautifulSoup
        
        # Parse HTML
        soup = BeautifulSoup(html_content, "html.parser")
        
        # Remove script and style elements
        for script in soup(["script", "style"]):
            script.decompose()

        # Replace images with markers so Gemini can see them
        for img in soup.find_all('img'):
            src = img.get('src')
            if src:
                img.replace_with(f" [Image: {src}] ")
                
        # Get text
        text = soup.get_text()
        
        # Break into lines and remove leading/trailing space on each
        lines = (line.strip() for line in text.splitlines())
        # Break multi-headlines into a line each
        chunks = (phrase.strip() for line in lines for phrase in line.split("  "))
        # Drop blank lines
        text = '\n'.join(chunk for chunk in chunks if chunk)
        
        return text

