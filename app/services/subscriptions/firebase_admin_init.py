"""Firebase Admin SDK initialization (singleton)."""

import logging
import os

import firebase_admin
from firebase_admin import credentials, firestore

logger = logging.getLogger(__name__)

_initialized = False
_db = None


def init_firebase() -> None:
    """Initialize Firebase Admin SDK if not already initialized."""
    global _initialized
    if _initialized:
        return

    try:
        # Use default credentials (GCP environment) or a service account key file.
        cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        if cred_path:
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
        else:
            # In Cloud Run / GCE, default credentials are available automatically.
            firebase_admin.initialize_app()
        _initialized = True
        logger.info("Firebase Admin SDK initialized")
    except Exception as e:
        logger.error(f"Firebase Admin SDK init failed: {e}")
        raise


def get_firestore_client():
    """Return a Firestore client, initializing Firebase if needed."""
    global _db
    if _db is None:
        init_firebase()
        _db = firestore.client()
    return _db
