# services/ocr_service.py
"""OCR service for extracting text from images."""

import io
from PIL import Image, ImageOps, ImageFilter
import pytesseract

from config import logger
from errors import APIError


def extract_text_from_image(image_bytes: bytes) -> str:
    """Extract text from image bytes using OCR."""
    try:
        image = Image.open(io.BytesIO(image_bytes))
        img = ImageOps.exif_transpose(image).convert("L")
        img = img.filter(ImageFilter.SHARPEN)
        img = img.point(lambda x: 0 if x < 160 else 255, mode="1")
        config = "--psm 6"
        text = pytesseract.image_to_string(img, lang="eng+heb", config=config)
        logger.debug("[OCR] extracted %d chars", len(text))
        return text
    except Exception as e:
        logger.error("[OCR] failure: %s", e, exc_info=True)
        raise APIError(f"OCR processing failed: {str(e)}")

