import base64
import hashlib
import json
import time

"""
Mock JWT-validation function that simulates ~25 ms of real authz work.

All Python benchmark configurations deploy this same ZIP. Instrumentation is
controlled entirely via environment variables and Lambda layers — no code
changes needed between configs.
"""

# Set to False after the first invocation; lets k6 detect cold starts from
# the response body without needing CloudWatch access during the test run.
_cold_start = True

DEFAULT_TOKEN = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    ".eyJzdWIiOiJiZW5jaC11c2VyIiwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjk5OTk5OTk5OTl9"
    ".mock-signature-not-verified"
)


def lambda_handler(event, context):
    global _cold_start
    is_cold_start = _cold_start
    _cold_start = False

    start_ms = time.monotonic() * 1000

    token = _extract_token(event.get("body"))
    authorized = _validate_token(token)
    subject = _extract_subject(token)

    # Pad to ~25 ms to simulate consistent authz latency regardless of how
    # quickly the crypto work finishes on a given instance type / memory tier.
    elapsed = time.monotonic() * 1000 - start_ms
    if elapsed < 25:
        time.sleep((25 - elapsed) / 1000)

    total_ms = int(time.monotonic() * 1000 - start_ms)

    body = json.dumps({
        "authorized": authorized,
        "subject": subject,
        "coldStart": is_cold_start,
        "processingTimeMs": total_ms,
    })

    return {
        "statusCode": 200 if authorized else 403,
        "headers": {"Content-Type": "application/json"},
        "body": body,
    }


def _extract_token(body):
    if not body:
        return DEFAULT_TOKEN
    try:
        parsed = json.loads(body)
        return parsed.get("token") or DEFAULT_TOKEN
    except Exception:
        return DEFAULT_TOKEN


def _pad_base64(s):
    padding = 4 - len(s) % 4
    return s + ("=" * (padding % 4))


def _validate_token(token):
    """
    Simulates real authz work: decode the JWT payload, run a SHA-256 loop to
    mimic HMAC verification, and do a simple policy check. The 50-iteration
    digest loop provides consistent CPU work without depending on system calls.
    """
    if not token:
        return False
    parts = token.split(".")
    if len(parts) != 3:
        return False
    try:
        payload_bytes = base64.urlsafe_b64decode(_pad_base64(parts[1]))
        payload = payload_bytes.decode("utf-8")
        if '"sub"' not in payload:
            return False

        signing_input = (parts[0] + "." + parts[1]).encode("utf-8")
        secret = b"benchmark-secret-key-32-bytes!!"

        h = hashlib.sha256()
        h.update(secret)
        h.update(signing_input)
        hash_bytes = h.digest()

        for _ in range(50):
            hash_bytes = hashlib.sha256(hash_bytes).digest()

        return len(hash_bytes) == 32
    except Exception:
        return False


def _extract_subject(token):
    try:
        parts = token.split(".")
        payload_bytes = base64.urlsafe_b64decode(_pad_base64(parts[1]))
        claims = json.loads(payload_bytes)
        return claims.get("sub", "unknown")
    except Exception:
        return "unknown"
