"""The code on a cover pass, which the door scans: the same one the apps and the other SDKs make.

``HMC1.<admission id>.<window>.<signature>``, where window is the Unix time divided by 30 seconds and signature is the
first 16 characters of the unpadded URL-safe Base64 HMAC-SHA256 of ``<admission id>.<window>``, keyed with the
Base64-decoded pass secret. It changes every 30 seconds, so a screenshot stops working within a minute: draw it fresh
rather than caching it.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import re
import time

PREFIX = "HMC1"
WINDOW_SECONDS = 30


def window(epoch_seconds: float) -> int:
    """The window ``epoch_seconds`` falls in."""
    return int(epoch_seconds // WINDOW_SECONDS)


def seconds_until_next_window(epoch_seconds: float) -> int:
    """Seconds from ``epoch_seconds`` until the code changes."""
    return WINDOW_SECONDS - int(epoch_seconds) % WINDOW_SECONDS


def signature(admission_id: str, pass_secret: str, at_window: int) -> str:
    key = base64.b64decode(pass_secret + "=" * (-len(pass_secret) % 4))
    digest = hmac.new(key, f"{admission_id}.{at_window}".encode(), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest).decode().rstrip("=")[:16]


def cover_pass_code(admission_id: str, pass_secret: str, epoch_seconds: float | None = None) -> str:
    """The pass's code at ``epoch_seconds`` (now by default)."""
    current = window(time.time() if epoch_seconds is None else epoch_seconds)
    return f"{PREFIX}.{admission_id}.{current}.{signature(admission_id, pass_secret, current)}"


def is_cover_pass_code(code: str) -> bool:
    """Whether ``code`` looks like a cover pass, before asking the API."""
    parts = code.strip().split(".")
    return (
        len(parts) == 4
        and parts[0] == PREFIX
        and bool(parts[1])
        and bool(re.fullmatch(r"[0-9]+", parts[2]))
        and bool(parts[3])
    )
