"""Image processing service."""

import logging
from typing import Tuple

from app.utils.exceptions import ImageProcessingError

logger = logging.getLogger(__name__)


class ImageService:
    """Service for processing uploaded images."""

    @staticmethod
    def validate_image(file_content: bytes, filename: str) -> Tuple[bytes, str]:
        """
        Validate and process uploaded image.

        Args:
            file_content: Image file bytes
            filename: Original filename

        Returns:
            Tuple of (image_bytes, mime_type)

        Raises:
            ImageProcessingError: If image is invalid
        """
        if not file_content:
            raise ImageProcessingError("Image file is empty")

        # Check file size (10MB max)
        max_size = 10 * 1024 * 1024  # 10MB
        if len(file_content) > max_size:
            raise ImageProcessingError(f"Image file too large (max {max_size / 1024 / 1024}MB)")

        # Determine MIME type from content (magic bytes)
        mime_type = ImageService._detect_mime_type(file_content)

        if mime_type not in ("image/jpeg", "image/png", "image/webp"):
            raise ImageProcessingError(
                f"Unsupported image format: {mime_type}. Supported: JPEG, PNG, WebP"
            )

        return file_content, mime_type

    @staticmethod
    def _detect_mime_type(file_content: bytes) -> str:
        """
        Detect MIME type from file content (magic bytes).

        Args:
            file_content: File bytes

        Returns:
            MIME type string
        """
        # Check magic bytes
        if file_content.startswith(b"\xff\xd8\xff"):
            return "image/jpeg"
        elif file_content.startswith(b"\x89PNG\r\n\x1a\n"):
            return "image/png"
        elif file_content.startswith(b"RIFF") and b"WEBP" in file_content[:12]:
            return "image/webp"
        else:
            # Try to use PIL as fallback
            try:
                from PIL import Image
                import io

                image = Image.open(io.BytesIO(file_content))
                return image.format.lower() if image.format else "application/octet-stream"
            except Exception:
                return "application/octet-stream"

