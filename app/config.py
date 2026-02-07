""""Application configuration using pydantic-settings."""

from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # API Keys
    gemini_api_key: str
    brightdata_api_key: str

    # Server
    port: int = 8080
    host: str = "0.0.0.0"

    # Logging
    log_level: str = "INFO"

    # HTTP Settings
    http_timeout: int = 30  # seconds
    max_request_size: int = 10 * 1024 * 1024  # 10MB

    # Rate Limiting
    rate_limit_per_hour: int = 100

    # CORS
    # Comma-separated origins or "*" for all (e.g., "http://localhost:3000,http://localhost:52300")
    cors_origins: str = "*"

    # Optional regex (useful for localhost with random ports, e.g. Flutter web)
    # Example: r"^http://localhost:\d+$|^http://127\.0\.0\.1:\d+$"
    cors_allow_origin_regex: str = r"^http://localhost:\d+$|^http://127\.0\.0\.1:\d+$"

    # Gemini Settings
    gemini_model: str = "gemini-2.5-flash-lite"
    gemini_temperature: float = 0.3
    gemini_max_tokens: int = 4096
    gemini_max_content_chars: int = 25000  # Max chars of page content sent to Gemini

    # Rate Limiting Storage
    rate_limit_storage_uri: str = "memory://"  # Use "redis://host:port" for shared rate limiting

    # Worker Settings
    workers: int = 2  # Number of Gunicorn workers (2 for 1 CPU Cloud Run instance)
    worker_timeout: int = 120  # Worker timeout in seconds

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @property
    def cors_origins_list(self) -> List[str]:
        """Get list of CORS origins."""
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


# Global settings instance
settings = Settings()
