"""Pytest configuration and fixtures."""

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client():
    """Create test client."""
    return TestClient(app)


@pytest.fixture
def mock_api_key(monkeypatch):
    """Mock API key for testing."""
    monkeypatch.setenv("API_KEYS", "test-api-key-123")
    monkeypatch.setenv("GEMINI_API_KEY", "test-gemini-key")
    monkeypatch.setenv("ZYTE_API_KEY", "test-zyte-key")
    # Reload settings
    from app.config import settings
    settings.api_keys = "test-api-key-123"
    settings.gemini_api_key = "test-gemini-key"
    settings.zyte_api_key = "test-zyte-key"

