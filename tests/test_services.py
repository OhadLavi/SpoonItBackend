"""Tests for service modules."""

import socket
import pytest
from unittest.mock import patch, MagicMock

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
