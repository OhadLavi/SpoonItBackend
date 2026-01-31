"""Input validation utilities."""

import ipaddress
import socket
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

    hostname = parsed.hostname
    if not hostname:
        raise ValidationError("URL must have a valid hostname")

    # Explicitly block "localhost" string
    if hostname.lower() == "localhost":
        raise ValidationError("URL cannot point to localhost")

    # Validate IP address/Hostname
    ips_to_check = []

    try:
        # First check if the hostname is an IP literal
        # strip brackets for IPv6 [::1] -> ::1
        clean_hostname = hostname.strip("[]")
        ip = ipaddress.ip_address(clean_hostname)
        ips_to_check.append(ip)
    except ValueError:
        # Not an IP literal, try to resolve it to catch domains pointing to private IPs
        try:
            # getaddrinfo handles both IPv4 and IPv6
            # We use proto=socket.IPPROTO_TCP to filter slightly
            addr_infos = socket.getaddrinfo(hostname, None, proto=socket.IPPROTO_TCP)
            seen_ips = set()
            for info in addr_infos:
                # info[4] is the sockaddr, info[4][0] is the IP string
                ip_str = info[4][0]
                if ip_str not in seen_ips:
                    ips_to_check.append(ipaddress.ip_address(ip_str))
                    seen_ips.add(ip_str)
        except (socket.gaierror, ValueError):
            # DNS resolution failed or result invalid.
            # We continue but if it was an internal domain it might fail later.
            pass

    # Validate all IPs
    for ip in ips_to_check:
        if (ip.is_private or
            ip.is_loopback or
            ip.is_link_local or
            ip.is_multicast or
            ip.is_reserved):
            raise ValidationError(f"URL resolves to restricted IP: {ip}")

        # Check IPv4-mapped IPv6 addresses (e.g. ::ffff:127.0.0.1)
        if ip.version == 6 and ip.ipv4_mapped:
            mapped = ip.ipv4_mapped
            if (mapped.is_private or
                mapped.is_loopback or
                mapped.is_link_local or
                mapped.is_multicast or
                mapped.is_reserved):
                raise ValidationError(f"URL resolves to restricted IP: {ip}")

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
