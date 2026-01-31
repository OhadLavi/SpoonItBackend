"""Tests for service modules."""

import pytest
import requests

from app.config import settings
from app.services.scraper_service import BRIGHTDATA_API_URL, ScraperService
from app.utils.validators import validate_ingredients_list, validate_url


def test_validate_url_valid():
    """Test URL validation with valid URLs."""
    assert validate_url("https://example.com/recipe") == "https://example.com/recipe"
    assert validate_url("http://example.com/recipe") == "http://example.com/recipe"


def test_validate_url_invalid_scheme():
    """Test URL validation with invalid scheme."""
    with pytest.raises(Exception):
        validate_url("ftp://example.com")


def test_validate_url_localhost():
    """Test URL validation blocks localhost."""
    with pytest.raises(Exception):
        validate_url("http://localhost/recipe")


def test_validate_ingredients_list_valid():
    """Test ingredients list validation with valid list."""
    ingredients = ["chicken", "rice", "vegetables"]
    result = validate_ingredients_list(ingredients)
    assert result == ingredients


def test_validate_ingredients_list_empty():
    """Test ingredients list validation with empty list."""
    with pytest.raises(Exception):
        validate_ingredients_list([])


def test_validate_ingredients_list_not_list():
    """Test ingredients list validation with non-list."""
    with pytest.raises(Exception):
        validate_ingredients_list("not a list")


def test_fetch_html_content_from_url():
    """Test that scraper service successfully returns HTML content from a website given a URL."""
    scraper = ScraperService()
    # Use httpbin.org/html which returns a simple HTML page with more content
    test_url = "https://httpbin.org/html"
    
    html_content = scraper._try_direct_fetch_html(test_url)
    
    # Assert that HTML content is returned (not None)
    assert html_content is not None, "HTML content should not be None"
    
    # Assert that the content is actually HTML (contains HTML tags)
    assert len(html_content) > 0, "HTML content should not be empty"
    assert "<html" in html_content.lower() or "<!doctype" in html_content.lower() or "<body" in html_content.lower(), \
        "Content should contain HTML tags"
    
    # Assert minimum length (as per the implementation requirement of >= 600 chars)
    assert len(html_content) >= 600, "HTML content should be at least 600 characters"
    
    # Print sample of HTML content
    print(f"\n=== Direct Fetch HTML Content Sample (first 10 chars) ===")
    print(f"Total length: {len(html_content)} characters")
    print(f"Preview: {html_content[:10]}")
    print("=" * 60)


@pytest.mark.skipif(
    not settings.brightdata_api_key,
    reason="BRIGHTDATA_API_KEY environment variable is not configured",
)
def test_brightdata_fetch_html():
    """
    Integration-style test that BrightData can fetch HTML for a given URL.

    To run this test locally, set BRIGHTDATA_API_KEY in your .env file.
    """
    api_key = settings.brightdata_api_key
    assert api_key, "BRIGHTDATA_API_KEY must be set in .env file to run this test"

    test_url = "https://www.10dakot.co.il/recipe/%D7%A2%D7%95%D7%92%D7%AA-%D7%93%D7%91%D7%A9-3/"

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    payload = {
        "zone": "spoonit_unlocker_api",
        "url": test_url,
        "format": "raw",
    }

    response = requests.post(
        BRIGHTDATA_API_URL,
        json=payload,
        headers=headers,
        timeout=50,
    )
    response.raise_for_status()

    # Ensure we got some content back
    assert response.content, "BrightData returned empty response content"

    html_content = response.content.decode("utf-8", errors="replace")

    # Reuse the scraper's HTML heuristic to validate the response
    assert ScraperService._looks_like_html(
        html_content
    ), "BrightData response does not look like valid HTML"
    
    # Print sample of HTML content
    print(f"\n=== BrightData HTML Content Sample (first 10 chars) ===")
    print(f"Total length: {len(html_content)} characters")
    print(f"Preview: {html_content[:10]}")
    print("=" * 60)
