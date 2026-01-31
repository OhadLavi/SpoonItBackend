"""Tests for service modules."""

import socket
import pytest
import requests
from unittest.mock import patch, MagicMock

from app.config import settings
from app.services.scraper_service import BRIGHTDATA_API_URL, ScraperService
from app.utils.validators import validate_ingredients_list, validate_url
from app.utils.exceptions import ValidationError


@patch("socket.getaddrinfo")
def test_validate_url_valid(mock_getaddrinfo):
    """Test URL validation with valid URLs."""
    # Mock return value for example.com -> 93.184.216.34 (public IP)
    mock_getaddrinfo.return_value = [
        (socket.AF_INET, socket.SOCK_STREAM, 6, '', ('93.184.216.34', 80))
    ]

    assert validate_url("https://example.com/recipe") == "https://example.com/recipe"
    assert validate_url("http://example.com/recipe") == "http://example.com/recipe"


def test_validate_url_invalid_scheme():
    """Test URL validation with invalid scheme."""
    with pytest.raises(ValidationError, match="URL must use http or https protocol"):
        validate_url("ftp://example.com")


def test_validate_url_localhost():
    """Test URL validation blocks localhost."""
    with pytest.raises(ValidationError, match="URL cannot point to localhost"):
        validate_url("http://localhost/recipe")


def test_validate_url_private_ips():
    """Test URL validation blocks private IPs."""
    private_ips = [
        "http://127.0.0.1",
        "http://10.0.0.1",
        "http://192.168.1.1",
        "http://172.16.0.1",
        "http://169.254.169.254", # Link-local / Cloud metadata
        "http://[::1]", # IPv6 localhost
        "http://[fd00::1]", # IPv6 private
    ]

    for url in private_ips:
        with pytest.raises(ValidationError, match="URL resolves to restricted IP"):
            validate_url(url)


def test_validate_url_obscured_ips():
    """Test URL validation blocks obscured IPs."""
    # Note: These might rely on system resolver or ipaddress parsing
    # ipaddress handles these correctly in newer python versions or raises ValueError
    # If ValueError, validate_url tries to resolve them.
    # If we want to test resolution of obscured IPs, we need to mock getaddrinfo
    # or rely on system behavior.
    # For hermetic tests, let's mock getaddrinfo for a "domain" that resolves to private IP.

    with patch("socket.getaddrinfo") as mock_getaddrinfo:
        # Mock "internal.dev" resolving to 192.168.1.5
        mock_getaddrinfo.return_value = [
            (socket.AF_INET, socket.SOCK_STREAM, 6, '', ('192.168.1.5', 80))
        ]
        with pytest.raises(ValidationError, match="URL resolves to restricted IP"):
            validate_url("http://internal.dev")


def test_validate_ingredients_list_valid():
    """Test ingredients list validation with valid list."""
    ingredients = ["chicken", "rice", "vegetables"]
    result = validate_ingredients_list(ingredients)
    assert result == ingredients


def test_validate_ingredients_list_empty():
    """Test ingredients list validation with empty list."""
    with pytest.raises(ValidationError):
        validate_ingredients_list([])


def test_validate_ingredients_list_not_list():
    """Test ingredients list validation with non-list."""
    with pytest.raises(ValidationError):
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
