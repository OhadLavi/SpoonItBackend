"""Store webhook handlers for subscription lifecycle events.

- App Store Server Notifications (Apple)
- Google Play Real-Time Developer Notifications (RTDN)

These endpoints are called by Apple/Google when subscription events happen
(renewal, cancellation, expiration, etc.).
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Request, HTTPException, status

from app.services.subscriptions.store_entitlements import lookup_user_by_identifier
from app.services.subscriptions.update_user_subscription import (
    update_user_subscription,
    revoke_user_subscription,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/webhooks", tags=["webhooks"])


# ── Apple App Store Server Notifications ────────────────────────────────

@router.post("/app-store")
async def app_store_webhook(request: Request):
    """Handle App Store Server Notifications v2.

    In production:
    1. Verify the JWS signed payload per Apple's docs.
    2. Extract the notification type and transaction info.
    3. Look up the user via originalTransactionId.
    4. Update Firestore subscription fields accordingly.
    """
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON")

    # TODO: Verify JWS signature before trusting the payload.
    # For now, log and acknowledge.
    notification_type = body.get("notificationType", "UNKNOWN")
    logger.info(f"App Store notification received: {notification_type}")

    # Example handling (implement fully after store setup):
    # signed_payload = body.get("signedPayload")
    # decoded = verify_and_decode_jws(signed_payload)
    # original_txn_id = decoded["data"]["signedTransactionInfo"]["originalTransactionId"]
    # user_id = lookup_user_by_identifier("ios", "production", original_txn_id)
    # if notification_type in ("DID_RENEW", "SUBSCRIBED"):
    #     update_user_subscription(user_id, ...)
    # elif notification_type in ("EXPIRED", "DID_FAIL_TO_RENEW", "REVOKE"):
    #     revoke_user_subscription(user_id)

    return {"status": "ok"}


# ── Google Play Real-Time Developer Notifications ───────────────────────

@router.post("/google-play")
async def google_play_webhook(request: Request):
    """Handle Google Play RTDN (Real-Time Developer Notifications).

    In production:
    1. Verify Pub/Sub push authenticity (JWT, push auth).
    2. Decode the notification.
    3. Look up the user via purchaseToken.
    4. Update Firestore subscription fields accordingly.
    """
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON")

    # TODO: Verify message authenticity (Pub/Sub push auth).
    logger.info(f"Google Play RTDN received: {body}")

    # Example handling (implement fully after store setup):
    # import base64, json
    # message = body.get("message", {})
    # data = json.loads(base64.b64decode(message.get("data", "")))
    # notification_type = data.get("subscriptionNotification", {}).get("notificationType")
    # purchase_token = data.get("subscriptionNotification", {}).get("purchaseToken")
    # user_id = lookup_user_by_identifier("android", "production", purchase_token)
    # Handle accordingly...

    return {"status": "ok"}
