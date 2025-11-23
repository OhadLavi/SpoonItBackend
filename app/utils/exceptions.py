"""Custom exception classes."""


class SpoonItException(Exception):
    """Base exception for SpoonIt application."""

    pass


class AuthenticationError(SpoonItException):
    """Raised when authentication fails."""

    pass


class RateLimitExceeded(SpoonItException):
    """Raised when rate limit is exceeded."""

    pass


class ValidationError(SpoonItException):
    """Raised when input validation fails."""

    pass


class ScrapingError(SpoonItException):
    """Raised when recipe scraping fails."""

    pass


class GeminiError(SpoonItException):
    """Raised when Gemini API call fails."""

    pass


class ZyteError(SpoonItException):
    """Raised when Zyte API call fails."""

    pass


class ImageProcessingError(SpoonItException):
    """Raised when image processing fails."""

    pass

