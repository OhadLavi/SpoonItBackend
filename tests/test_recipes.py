"""Tests for recipe endpoints."""

import pytest
from fastapi.testclient import TestClient


def test_health_check(client: TestClient):
    """Test health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_readiness_check(client: TestClient):
    """Test readiness check endpoint."""
    response = client.get("/health/ready")
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    assert "dependencies" in data


def test_extract_from_url_missing_api_key(client: TestClient):
    """Test extract from URL without API key."""
    response = client.post("/recipes/from-url", data={"url": "https://example.com"})
    assert response.status_code == 401


def test_extract_from_url_invalid_api_key(client: TestClient):
    """Test extract from URL with invalid API key."""
    response = client.post(
        "/recipes/from-url",
        data={"url": "https://example.com"},
        headers={"X-API-Key": "invalid-key"},
    )
    assert response.status_code == 401


def test_extract_from_image_missing_api_key(client: TestClient):
    """Test extract from image without API key."""
    response = client.post("/recipes/from-image", files={"file": ("test.jpg", b"fake image")})
    assert response.status_code == 401


def test_generate_recipe_missing_api_key(client: TestClient):
    """Test generate recipe without API key."""
    response = client.post("/recipes/generate", data={"ingredients": ["chicken", "rice"]})
    assert response.status_code == 401

