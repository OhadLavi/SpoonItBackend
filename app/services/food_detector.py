"""
Food detection service using ONNX Runtime with MobileNetV2.
Detects if images contain food to filter recipe images.
"""

import asyncio
import hashlib
import logging
import os
from pathlib import Path
from typing import List, Optional, Tuple
from urllib.parse import urlparse

import numpy as np
import requests
from PIL import Image
from io import BytesIO

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
    
    def _is_food_class(self, class_ids: List[int], probabilities: np.ndarray) -> Tuple[bool, float]:
        """Check if any of the top predicted classes are food-related."""
        food_score = 0.0
        
        for i, class_id in enumerate(class_ids[:5]):  # Check top 5 predictions
            if class_id in FOOD_CLASS_IDS:
                # Weight by probability and position
                weight = 1.0 - (i * 0.15)  # Decrease weight for lower positions
                food_score += probabilities[class_id] * weight
        
        # Return True if food score exceeds threshold
        threshold = 0.15  # Relatively low threshold since we're filtering candidates
        return food_score > threshold, food_score
    
    async def detect_food_in_image(self, image_data: bytes) -> Tuple[bool, float]:
        """
        Detect if an image contains food.
        
        Args:
            image_data: Raw image bytes
            
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
            
            # Run inference
            loop = asyncio.get_event_loop()
            outputs = await loop.run_in_executor(
                None,
                lambda: self._session.run(None, {'input': input_tensor})
            )
            
            # Get predictions
            logits = outputs[0][0]
            probabilities = self._softmax(logits)
            
            # Get top-5 class IDs
            top_5_indices = np.argsort(probabilities)[-5:][::-1]
            
            # Check if food-related
            is_food, score = self._is_food_class(top_5_indices.tolist(), probabilities)
            
            logger.debug(f"Food detection: is_food={is_food}, score={score:.3f}")
            return is_food, score
            
        except Exception as e:
            logger.warning(f"Food detection failed: {e}")
            # On error, assume might be food
            return True, 0.5
    
    def _softmax(self, x: np.ndarray) -> np.ndarray:
        """Compute softmax probabilities."""
        exp_x = np.exp(x - np.max(x))
        return exp_x / exp_x.sum()
    
    async def filter_food_images(
        self,
        image_urls: List[str],
        min_score: float = 0.1,
        timeout: float = 5.0
    ) -> List[str]:
        """
        Filter a list of image URLs to only include those containing food.
        Downloads and analyzes images in parallel.
        
        Args:
            image_urls: List of image URLs to analyze
            min_score: Minimum food confidence score to include
            timeout: Timeout for downloading each image
            
        Returns:
            List of image URLs that contain food, sorted by confidence
        """
        if not image_urls:
            return []
        
        async def analyze_image(url: str) -> Tuple[str, bool, float]:
            """Download and analyze a single image."""
            try:
                # Download image
                loop = asyncio.get_event_loop()
                response = await loop.run_in_executor(
                    None,
                    lambda: requests.get(url, timeout=timeout, headers={
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                    })
                )
                response.raise_for_status()
                
                # Detect food
                is_food, score = await self.detect_food_in_image(response.content)
                return url, is_food, score
                
            except Exception as e:
                logger.debug(f"Failed to analyze image {url}: {e}")
                # On error, assume might be food with low confidence
                return url, True, 0.3
        
        # Analyze all images in parallel
        tasks = [analyze_image(url) for url in image_urls[:10]]  # Limit to 10 images
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Filter and sort by confidence
        food_images = []
        for result in results:
            if isinstance(result, Exception):
                continue
            url, is_food, score = result
            if is_food and score >= min_score:
                food_images.append((url, score))
        
        # Sort by score (descending) and return URLs
        food_images.sort(key=lambda x: x[1], reverse=True)
        
        filtered_urls = [url for url, _ in food_images]
        logger.info(f"Food detection: {len(filtered_urls)}/{len(image_urls)} images contain food")
        
        return filtered_urls


# Global instance for reuse
_food_detector: Optional[FoodDetector] = None


def get_food_detector() -> FoodDetector:
    """Get the singleton food detector instance."""
    global _food_detector
    if _food_detector is None:
        _food_detector = FoodDetector()
    return _food_detector
