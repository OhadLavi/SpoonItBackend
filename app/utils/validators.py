"""Input validation utilities."""

from urllib.parse import urlparse
from app.utils.exceptions import ValidationError


def validate_url(url: str) -> str:
    """
    Validate and sanitize URL to prevent SSRF attacks.

    Args:
        url: URL to validate

    Returns:
        Validated URL string

    Raises:
        ValidationError: If URL is invalid or potentially dangerous
    """
    if not url or not isinstance(url, str):
        raise ValidationError("URL must be a non-empty string")

    url = url.strip()

    # Parse URL
    try:
        parsed = urlparse(url)
    except Exception as e:
        raise ValidationError(f"Invalid URL format: {str(e)}")

    # Check scheme
    if parsed.scheme not in ("http", "https"):
        raise ValidationError("URL must use http or https protocol")

    # Check for localhost/private IPs (SSRF protection)
    hostname = parsed.hostname
    if not hostname:
        raise ValidationError("URL must have a valid hostname")

    # Block localhost and private IPs
    blocked_hosts = {
        "localhost",
        "127.0.0.1",
        "0.0.0.0",
        "::1",
    }

    if hostname.lower() in blocked_hosts:
        raise ValidationError("URL cannot point to localhost or private IPs")

    # Block private IP ranges
    if hostname.startswith("10.") or hostname.startswith("192.168.") or hostname.startswith("172."):
        # More thorough check for 172.16-31.x.x range
        parts = hostname.split(".")
        if len(parts) >= 2 and parts[0] == "172":
            try:
                second_octet = int(parts[1])
                if 16 <= second_octet <= 31:
                    raise ValidationError("URL cannot point to private IP ranges")
            except ValueError:
                pass

    return url


def validate_ingredients_list(ingredients: list) -> list:
    """
    Validate ingredients list.

    Args:
        ingredients: List of ingredient strings

    Returns:
        Validated list of ingredients

    Raises:
        ValidationError: If ingredients list is invalid
    """
    if not isinstance(ingredients, list):
        raise ValidationError("Ingredients must be a list")

    if not ingredients:
        raise ValidationError("Ingredients list cannot be empty")

    if len(ingredients) > 50:  # Reasonable limit
        raise ValidationError("Ingredients list cannot exceed 50 items")

    validated = []
    for ingredient in ingredients:
        if not isinstance(ingredient, str):
            raise ValidationError("All ingredients must be strings")
        ingredient = ingredient.strip()
        if not ingredient:
            continue
        if len(ingredient) > 500:  # Reasonable limit per ingredient
            raise ValidationError("Ingredient text cannot exceed 500 characters")
        validated.append(ingredient)

    if not validated:
        raise ValidationError("At least one valid ingredient is required")

    return validated

