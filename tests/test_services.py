"""Tests for service modules."""

import pytest

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

