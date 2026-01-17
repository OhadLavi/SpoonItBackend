"""
Food detection service using ONNX Runtime with MobileNetV2.
Detects if images contain food to filter recipe images.
"""

import asyncio
import hashlib
import logging
import os
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse

import numpy as np
import requests
from PIL import Image
from io import BytesIO

try:
    import imagehash
    _IMAGEHASH_AVAILABLE = True
except ImportError:
    _IMAGEHASH_AVAILABLE = False

logger = logging.getLogger(__name__)

# Model configuration
MODEL_URL = "https://github.com/onnx/models/raw/main/validated/vision/classification/mobilenet/model/mobilenetv2-7.onnx"
MODEL_FILENAME = "mobilenetv2-7.onnx"
MODEL_DIR = Path(__file__).parent.parent.parent / "models"

# ImageNet food-related class IDs (approximate ranges and specific classes)
# These are class indices from ImageNet that relate to food
FOOD_CLASS_IDS = set([
    # Fruits (948-969 range)
    *range(948, 970),
    # Vegetables and produce
    937, 938, 939, 940, 941, 942, 943, 944, 945, 946, 947,
    # Prepared foods, dishes
    923, 924, 925, 926, 927, 928, 929, 930, 931, 932, 933, 934, 935, 936,
    # Bread, baked goods
    930, 931, 932,
    # Pizza, hotdog, burger
    963, 964, 965,
    # Ice cream, desserts
    928, 929,
    # Beverages
    898, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908, 909, 910,
    # Kitchen items that suggest food context
    567, 968, 969, 970, 971, 972, 973,
    # Additional food items
    567,  # frying pan (indicates cooking)
    968,  # espresso
    966,  # potpie
    967,  # mashed potato
    959,  # carbonara
    960,  # chocolate sauce
    961,  # dough
    962,  # meat loaf
    954,  # banana
    955,  # jackfruit
    956,  # custard apple
    957,  # pomegranate
    950,  # orange
    951,  # lemon
    952,  # fig
    953,  # pineapple
    949,  # strawberry
    948,  # Granny Smith apple
])

# Additional keywords to boost food detection (in top-5 class names)
FOOD_KEYWORDS = [
    'food', 'dish', 'meal', 'cuisine', 'plate', 'bowl', 'soup', 'salad',
    'bread', 'cake', 'pizza', 'burger', 'sandwich', 'pasta', 'rice',
    'meat', 'fish', 'vegetable', 'fruit', 'dessert', 'sauce', 'cheese',
    'egg', 'chicken', 'beef', 'pork', 'seafood', 'sushi', 'noodle',
    'curry', 'stew', 'roast', 'grill', 'fry', 'bake', 'cook',
    'breakfast', 'lunch', 'dinner', 'snack', 'appetizer',
]


class FoodDetector:
    """Detects food in images using ONNX Runtime with MobileNetV2."""
    
    _instance: Optional['FoodDetector'] = None
    _session = None
    _initialized = False
    
    def __new__(cls):
        """Singleton pattern to reuse the model session."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    def __init__(self):
        """Initialize the food detector (lazy loading)."""
        pass
    
    def _ensure_model_downloaded(self) -> Path:
        """Download the ONNX model if not already present."""
        MODEL_DIR.mkdir(parents=True, exist_ok=True)
        model_path = MODEL_DIR / MODEL_FILENAME
        
        if model_path.exists():
            logger.debug(f"Model already exists at {model_path}")
            return model_path
        
        logger.info(f"Downloading MobileNetV2 ONNX model to {model_path}...")
        try:
            response = requests.get(MODEL_URL, timeout=60)
            response.raise_for_status()
            model_path.write_bytes(response.content)
            logger.info(f"Model downloaded successfully ({len(response.content) / 1024 / 1024:.1f} MB)")
            return model_path
        except Exception as e:
            logger.error(f"Failed to download model: {e}")
            raise
    
    def _initialize_session(self):
        """Initialize the ONNX Runtime session."""
        if self._initialized:
            return
        
        try:
            import onnxruntime as ort
            
            model_path = self._ensure_model_downloaded()
            
            # Use CPU execution provider (lightweight)
            self._session = ort.InferenceSession(
                str(model_path),
                providers=['CPUExecutionProvider']
            )
            self._initialized = True
            logger.info("ONNX Runtime session initialized")
        except ImportError:
            logger.warning("onnxruntime not installed, food detection disabled")
            self._session = None
            self._initialized = True
        except Exception as e:
            logger.error(f"Failed to initialize ONNX session: {e}")
            self._session = None
            self._initialized = True
    
    def _preprocess_image(self, image: Image.Image) -> np.ndarray:
        """Preprocess image for MobileNetV2 input."""
        # Resize to 224x224
        image = image.convert('RGB')
        image = image.resize((224, 224), Image.Resampling.BILINEAR)
        
        # Convert to numpy array and normalize
        img_array = np.array(image, dtype=np.float32)
        
        # Normalize to [0, 1] then apply ImageNet normalization
        img_array = img_array / 255.0
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        img_array = (img_array - mean) / std
        
        # Transpose to NCHW format (batch, channels, height, width)
        img_array = img_array.transpose(2, 0, 1)
        img_array = np.expand_dims(img_array, axis=0)
        
        return img_array
    
    def _is_food_class(self, class_ids: List[int], probabilities: np.ndarray, threshold: float = 0.25) -> Tuple[bool, float]:
        """Check if any of the top predicted classes are food-related."""
        food_score = 0.0
        
        for i, class_id in enumerate(class_ids[:5]):  # Check top 5 predictions
            if class_id in FOOD_CLASS_IDS:
                # Weight by probability and position
                weight = 1.0 - (i * 0.15)  # Decrease weight for lower positions
                food_score += probabilities[class_id] * weight
        
        # Return True if food score exceeds threshold
        return food_score > threshold, food_score
    
    async def detect_food_in_image(self, image_data: bytes, threshold: float = 0.25) -> Tuple[bool, float]:
        """
        Detect if an image contains food.
        
        Args:
            image_data: Raw image bytes
            threshold: Food detection threshold (default: 0.25)
            
        Returns:
            Tuple of (is_food, confidence_score)
        """
        self._initialize_session()
        
        if self._session is None:
            # If ONNX not available, assume all images might be food
            return True, 0.5
        
        try:
            # Load image
            image = Image.open(BytesIO(image_data))
            
            # Preprocess
            input_tensor = self._preprocess_image(image)
            
            # Get the input name from the model (different models use different names)
            input_name = self._session.get_inputs()[0].name
            
            # Run inference
            loop = asyncio.get_event_loop()
            outputs = await loop.run_in_executor(
                None,
                lambda: self._session.run(None, {input_name: input_tensor})
            )
            
            # Get predictions
            logits = outputs[0][0]
            probabilities = self._softmax(logits)
            
            # Get top-5 class IDs
            top_5_indices = np.argsort(probabilities)[-5:][::-1]
            
            # Check if food-related
            is_food, score = self._is_food_class(top_5_indices.tolist(), probabilities, threshold)
            
            logger.debug(f"Food detection: is_food={is_food}, score={score:.3f} (threshold={threshold})")
            return is_food, score
            
        except Exception as e:
            logger.warning(f"Food detection failed: {e}")
            # On error, assume might be food
            return True, 0.5
    
    def _softmax(self, x: np.ndarray) -> np.ndarray:
        """Compute softmax probabilities."""
        exp_x = np.exp(x - np.max(x))
        return exp_x / exp_x.sum()
    
    def _calculate_image_hash_and_size(self, image_data: bytes) -> Tuple[Optional[str], Optional[Tuple[int, int]]]:
        """Calculate perceptual hash and dimensions for image deduplication."""
        if not _IMAGEHASH_AVAILABLE:
            return None, None
        try:
            image = Image.open(BytesIO(image_data))
            # Use average hash (aHash) - good for detecting similar images
            img_hash = imagehash.average_hash(image, hash_size=16)
            # Get image dimensions
            width, height = image.size
            return str(img_hash), (width, height)
        except Exception as e:
            logger.debug(f"Failed to calculate image hash/size: {e}")
            return None, None
    
    def _deduplicate_images(
        self,
        image_results: List[Tuple[str, float, Optional[str], Optional[Tuple[int, int]]]],
        hash_threshold: int = 5
    ) -> List[Tuple[str, float]]:
        """
        Remove duplicate/similar images using perceptual hashing.
        When duplicates are found, keeps the larger image (higher resolution).
        
        Args:
            image_results: List of (url, score, hash, dimensions) tuples
            hash_threshold: Maximum hash difference to consider images similar (0-64)
            
        Returns:
            List of (url, score) tuples with duplicates removed (larger images kept)
        """
        if not _IMAGEHASH_AVAILABLE:
            # If imagehash not available, just return sorted by score
            return [(url, score) for url, score, _, _ in image_results]
        
        # Track unique images: {hash: (url, score, width*height)}
        unique_by_hash: Dict[str, Tuple[str, float, int]] = {}
        # Track images without hash (include all of them)
        no_hash_images: List[Tuple[str, float]] = []
        
        for url, score, img_hash, dimensions in image_results:
            if img_hash is None:
                # If hash calculation failed, include it (better safe than sorry)
                no_hash_images.append((url, score))
                continue
            
            # Calculate image area (width * height) for size comparison
            area = 0
            if dimensions:
                width, height = dimensions
                area = width * height
            
            # Check if we've seen a similar hash
            found_duplicate = False
            for existing_hash, (existing_url, existing_score, existing_area) in unique_by_hash.items():
                try:
                    # Calculate hamming distance between hashes
                    hash1 = imagehash.hex_to_hash(img_hash)
                    hash2 = imagehash.hex_to_hash(existing_hash)
                    distance = hash1 - hash2
                    
                    if distance <= hash_threshold:
                        # Images are similar/duplicate - keep the larger one
                        found_duplicate = True
                        if area > existing_area:
                            # Current image is larger, replace the existing one
                            logger.debug(f"Replacing duplicate {existing_url} with larger image {url} "
                                       f"(area: {existing_area} -> {area}, hash distance: {distance})")
                            unique_by_hash[existing_hash] = (url, score, area)
                        else:
                            # Existing image is larger or same size, keep it
                            logger.debug(f"Skipping duplicate {url} (existing {existing_url} is larger, "
                                       f"area: {area} <= {existing_area}, hash distance: {distance})")
                        break
                except Exception as e:
                    logger.debug(f"Failed to compare hashes: {e}")
                    # If comparison fails, include the image
                    break
            
            if not found_duplicate:
                # New unique image
                unique_by_hash[img_hash] = (url, score, area)
        
        # Combine unique images and no-hash images, sort by score
        all_unique = [(url, score) for url, score, _ in unique_by_hash.values()] + no_hash_images
        all_unique.sort(key=lambda x: x[1], reverse=True)
        
        return all_unique
    
    async def filter_food_images(
        self,
        image_urls: List[str],
        min_score: float = 0.25,
        timeout: float = 5.0,
        min_width: int = 200,
        min_height: int = 200
    ) -> List[str]:
        """
        Filter a list of image URLs to only include those containing food.
        Downloads and analyzes images in parallel, then removes duplicates.
        
        Args:
            image_urls: List of image URLs to analyze
            min_score: Minimum food confidence score to include (default: 0.25)
            timeout: Timeout for downloading each image
            min_width: Minimum image width in pixels (default: 200)
            min_height: Minimum image height in pixels (default: 200)
            
        Returns:
            List of image URLs that contain food, sorted by confidence, with duplicates removed
        """
        if not image_urls:
            return []
        
        filter_start_time = time.time()
        total_images = len(image_urls[:10])  # Limit to 10 images
        
        async def analyze_image(url: str) -> Tuple[str, bool, float, Optional[str], Optional[Tuple[int, int]]]:
            """Download and analyze a single image."""
            image_start_time = time.time()
            try:
                # Quick check: filter GIFs by URL extension
                url_lower = url.lower()
                if url_lower.endswith('.gif') or '.gif?' in url_lower:
                    logger.debug(f"Skipping GIF image: {url}")
                    return url, False, 0.0, None, None
                
                # Download image
                loop = asyncio.get_event_loop()
                response = await loop.run_in_executor(
                    None,
                    lambda: requests.get(url, timeout=timeout, headers={
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                    })
                )
                response.raise_for_status()
                
                image_data = response.content
                
                # Check image format - filter out GIFs
                try:
                    image = Image.open(BytesIO(image_data))
                    image_format = image.format
                    
                    if image_format == 'GIF':
                        logger.debug(f"Skipping GIF image (format detected): {url}")
                        return url, False, 0.0, None, None
                    
                    # Check image dimensions - filter out small images
                    width, height = image.size
                    if width < min_width or height < min_height:
                        logger.debug(f"Skipping small image {url} ({width}x{height}, min: {min_width}x{min_height})")
                        return url, False, 0.0, None, None
                    
                except Exception as e:
                    logger.debug(f"Failed to check image format/size for {url}: {e}")
                    # If we can't check, continue anyway (better to include than miss)
                
                # Detect food (use default threshold 0.25, then filter by min_score)
                detect_start = time.time()
                is_food, score = await self.detect_food_in_image(image_data)
                detect_time = time.time() - detect_start
                
                # Calculate hash and dimensions for deduplication
                hash_start = time.time()
                img_hash, dimensions = self._calculate_image_hash_and_size(image_data)
                hash_time = time.time() - hash_start
                
                # Double-check dimensions after hash calculation (in case format check failed)
                if dimensions:
                    width, height = dimensions
                    if width < min_width or height < min_height:
                        logger.debug(f"Skipping small image {url} ({width}x{height})")
                        return url, False, 0.0, None, None
                
                image_time = time.time() - image_start_time
                logger.debug(f"Image processed: {url[:60]}... | "
                           f"is_food={is_food}, score={score:.3f} | "
                           f"time={image_time:.3f}s (detect={detect_time:.3f}s, hash={hash_time:.3f}s)")
                
                return url, is_food, score, img_hash, dimensions
                
            except Exception as e:
                logger.debug(f"Failed to analyze image {url}: {e}")
                # On error, don't include the image (better to miss than have false positives)
                return url, False, 0.0, None, None
        
        # Analyze all images in parallel
        tasks = [analyze_image(url) for url in image_urls[:10]]  # Limit to 10 images
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Filter by food detection and minimum score
        food_images = []
        for result in results:
            if isinstance(result, Exception):
                continue
            url, is_food, score, img_hash, dimensions = result
            if is_food and score >= min_score:
                food_images.append((url, score, img_hash, dimensions))
        
        # Remove duplicates using perceptual hashing (keeps larger images when duplicates found)
        dedup_start = time.time()
        unique_images = self._deduplicate_images(food_images)
        dedup_time = time.time() - dedup_start
        
        # Return URLs sorted by score (already sorted by deduplication)
        filtered_urls = [url for url, _ in unique_images]
        logger.info(f"Food detector keeping {len(filtered_urls)}/{len(unique_images)} unique images after deduplication. Raw unique: {unique_images}")
        
        total_time = time.time() - filter_start_time
        valid_count = len(filtered_urls)
        invalid_count = total_images - valid_count
        
        logger.info(f"Food detection complete: {valid_count}/{total_images} valid food images "
                   f"({invalid_count} invalid) | "
                   f"total_time={total_time:.3f}s (dedup={dedup_time:.3f}s)")
        
        return filtered_urls


# Global instance for reuse
_food_detector: Optional[FoodDetector] = None


def get_food_detector() -> FoodDetector:
    """Get the singleton food detector instance."""
    global _food_detector
    if _food_detector is None:
        _food_detector = FoodDetector()
    return _food_detector
