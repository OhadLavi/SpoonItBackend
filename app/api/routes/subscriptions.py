"""Subscription verification endpoints.

The backend is the single source of truth for subscription status.
These endpoints verify purchases with Apple/Google, write Firestore,
and return the computed subscription state.
"""

import logging
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException, Header, status
from pydantic import BaseModel

from firebase_admin import auth as firebase_auth

from app.services.subscriptions.firebase_admin_init import init_firebase
from app.services.subscriptions.update_user_subscription import (
    update_user_subscription,
)
from app.services.subscriptions.store_entitlements import link_entitlement

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/subscriptions", tags=["subscriptions"])

# Ensure Firebase Admin SDK is initialized
init_firebase()


# ── Request / Response models ──────────────────────────────────────────

class VerifyPurchaseRequest(BaseModel):
    userId: str
    platform: str  # 'ios' or 'android'
    productId: str
    receipt: Optional[str] = None        # iOS receipt
    purchaseToken: Optional[str] = None  # Android purchaseToken


class VerifyPurchaseResponse(BaseModel):
    isPremium: bool
    premiumExpiresAt: Optional[str] = None
    subscriptionType: str


# ── Auth helper ────────────────────────────────────────────────────────

async def _verify_firebase_token(authorization: str) -> str:
    """Verify Firebase ID token from Authorization header.

    Returns the authenticated user's UID.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
        )
    token = authorization[7:]
    try:
        decoded = firebase_auth.verify_id_token(token)
        return decoded["uid"]
    except Exception as e:
        logger.warning(f"Firebase token verification failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Firebase token",
        )


# ── Product → subscription type mapping ────────────────────────────────

_PRODUCT_TYPE_MAP = {
    "premium_monthly": "monthly",
    "premium_yearly": "yearly",
    "premium_lifetime": "lifetime",
}

_PRODUCT_DURATION_MAP = {
    "premium_monthly": timedelta(days=30),
    "premium_yearly": timedelta(days=365),
    "premium_lifetime": None,  # no expiration
}


# ── Verification endpoints ─────────────────────────────────────────────

@router.post("/verify", response_model=VerifyPurchaseResponse)
async def verify_purchase(
    body: VerifyPurchaseRequest,
    authorization: str = Header(...),
):
    """Verify a purchase with the store and update Firestore.

    The client sends the receipt/purchaseToken; the backend verifies it,
    links the entitlement, writes subscription fields, and returns the result.
    """
    # 1. Authenticate
    auth_uid = await _verify_firebase_token(authorization)

    # 2. Enforce that the verified user matches the request
    if auth_uid != body.userId:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="userId does not match authenticated user",
        )

    # 3. Determine subscription type
    sub_type = _PRODUCT_TYPE_MAP.get(body.productId)
    if not sub_type:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown productId: {body.productId}",
        )

    # 4. Verify with store
    # TODO: Replace with real store verification.
    # For now, we trust the receipt for development/testing.
    # In production:
    #   - iOS: Verify receipt with App Store server API
    #   - Android: Verify purchaseToken with Google Play Developer API
    identifier = body.receipt or body.purchaseToken
    if not identifier:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="receipt (iOS) or purchaseToken (Android) is required",
        )

    environment = "production"  # TODO: detect sandbox vs production

    # 5. Link entitlement (ownership check)
    try:
        link_entitlement(
            platform=body.platform,
            environment=environment,
            identifier=identifier,
            user_id=body.userId,
            product_id=body.productId,
        )
    except ValueError as e:
        if "OWNERSHIP_MISMATCH" in str(e):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This purchase belongs to another account. Log in to that account.",
            )
        raise

    # 6. Calculate expiration
    duration = _PRODUCT_DURATION_MAP.get(body.productId)
    expires_at = None
    if duration is not None:
        expires_at = datetime.now(timezone.utc) + duration

    # 7. Write subscription to Firestore
    result = update_user_subscription(
        user_id=body.userId,
        is_premium=True,
        subscription_type=sub_type,
        premium_expires_at=expires_at,
    )

    return VerifyPurchaseResponse(
        isPremium=result["isPremium"],
        premiumExpiresAt=result["premiumExpiresAt"],
        subscriptionType=result["subscriptionType"],
    )


@router.post("/verify-apple")
async def verify_apple_purchase(
    body: VerifyPurchaseRequest,
    authorization: str = Header(...),
):
    """Convenience alias for iOS purchases."""
    body.platform = "ios"
    return await verify_purchase(body, authorization)


@router.post("/verify-google")
async def verify_google_purchase(
    body: VerifyPurchaseRequest,
    authorization: str = Header(...),
):
    """Convenience alias for Android purchases."""
    body.platform = "android"
    return await verify_purchase(body, authorization)
