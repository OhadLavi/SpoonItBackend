"""Shared logic for writing subscription fields to the user document.

Only the backend (Admin SDK) may write these fields.
"""

import logging
from datetime import datetime, timezone
from typing import Optional

from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from .firebase_admin_init import get_firestore_client

logger = logging.getLogger(__name__)


def update_user_subscription(
    user_id: str,
    is_premium: bool,
    subscription_type: str,  # 'monthly', 'yearly', 'lifetime'
    premium_expires_at: Optional[datetime] = None,
) -> dict:
    """Write subscription fields to the user document in Firestore.

    Args:
        user_id: Firestore user document ID.
        is_premium: Whether the user has an active premium subscription.
        subscription_type: 'monthly', 'yearly', or 'lifetime'.
        premium_expires_at: Expiration datetime (None for lifetime).

    Returns:
        dict with the written fields.
    """
    db = get_firestore_client()
    user_ref = db.collection("users").document(user_id)

    data = {
        "isPremium": is_premium,
        "subscriptionType": subscription_type,
        "premiumExpiresAt": premium_expires_at,
        "subscriptionPurchasedAt": SERVER_TIMESTAMP,
    }

    user_ref.update(data)
    logger.info(f"Updated subscription for user {user_id}: type={subscription_type}, premium={is_premium}")

    return {
        "isPremium": is_premium,
        "subscriptionType": subscription_type,
        "premiumExpiresAt": premium_expires_at.isoformat() if premium_expires_at else None,
    }


def revoke_user_subscription(user_id: str) -> dict:
    """Revoke a user's subscription (e.g. on expiration or cancellation)."""
    db = get_firestore_client()
    user_ref = db.collection("users").document(user_id)

    data = {
        "isPremium": False,
        "subscriptionType": None,
        "premiumExpiresAt": None,
    }

    user_ref.update(data)
    logger.info(f"Revoked subscription for user {user_id}")

    return data
