"""Store entitlements collection for mapping store identifiers to users.

This collection is backend-only; Firestore rules deny all client access.
Document ID: {platform}_{env}_{sha256(identifier)[:32]}
"""

import hashlib
import logging
from datetime import datetime, timezone
from typing import Optional

from .firebase_admin_init import get_firestore_client

logger = logging.getLogger(__name__)

COLLECTION = "storeEntitlements"


def _make_doc_id(platform: str, environment: str, identifier: str) -> str:
    """Create a deterministic document ID from the store identifier."""
    h = hashlib.sha256(identifier.encode()).hexdigest()[:32]
    return f"{platform}_{environment}_{h}"


def link_entitlement(
    platform: str,
    environment: str,
    identifier: str,  # purchaseToken (Android) or originalTransactionId (iOS)
    user_id: str,
    product_id: str,
) -> str:
    """Persist a store entitlement after successful verification.

    Returns the document ID.

    Raises ValueError if the identifier is already linked to a different user.
    """
    db = get_firestore_client()
    doc_id = _make_doc_id(platform, environment, identifier)
    doc_ref = db.collection(COLLECTION).document(doc_id)

    existing = doc_ref.get()
    if existing.exists:
        data = existing.to_dict()
        linked_user = data.get("userId") or data.get("linkedUserId")
        if linked_user and linked_user != user_id:
            raise ValueError(
                f"OWNERSHIP_MISMATCH: identifier already linked to user {linked_user}"
            )
        # Same user — update lastVerifiedAt
        doc_ref.update({"lastVerifiedAt": datetime.now(timezone.utc)})
        logger.info(f"Updated entitlement {doc_id} for user {user_id}")
        return doc_id

    doc_ref.set({
        "userId": user_id,
        "linkedUserId": user_id,
        "linkedAt": datetime.now(timezone.utc),
        "platform": platform,
        "environment": environment,
        "productId": product_id,
        "createdAt": datetime.now(timezone.utc),
        "lastVerifiedAt": datetime.now(timezone.utc),
    })
    logger.info(f"Created entitlement {doc_id} for user {user_id}")
    return doc_id


def lookup_user_by_identifier(
    platform: str,
    environment: str,
    identifier: str,
) -> Optional[str]:
    """Look up a user ID by store identifier (for webhooks)."""
    db = get_firestore_client()
    doc_id = _make_doc_id(platform, environment, identifier)
    doc_ref = db.collection(COLLECTION).document(doc_id)

    doc = doc_ref.get()
    if not doc.exists:
        return None
    return doc.to_dict().get("userId")
