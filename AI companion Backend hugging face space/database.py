import os
import threading
import asyncio
from typing import Optional
from supabase import create_client, Client

SUPABASE_LOCK = threading.Lock()
SUPABASE_RETRYABLE_MARKERS = (
    "connectionterminated",
    "server disconnected",
    "remoteprotocolerror",
    "stream reset",
    "connection reset",
    "deque mutated during iteration",
)

def _create_supabase_client() -> Optional[Client]:
    try:
        url = os.getenv("SUPABASE_URL")
        key = os.getenv("SUPABASE_KEY")
        if not (url and key):
            return None
        return create_client(url, key)
    except Exception as e:
        print(f"Supabase re-init failed: {e}")
        return None

supabase: Optional[Client] = _create_supabase_client()
if supabase:
    print("Supabase connected.")
else:
    print("Warning: Supabase keys missing.")

async def _supabase_execute_threadsafe(op, retries: int = 2):
    """
    Serialize sync Supabase SDK calls and retry transient connection errors.
    """
    global supabase
    if not supabase:
        return None

    last_error: Optional[Exception] = None
    for attempt in range(retries + 1):
        try:
            def _run():
                with SUPABASE_LOCK:
                    return op()
            return await asyncio.to_thread(_run)
        except Exception as e:
            last_error = e
            err_text = str(e).lower()
            should_retry = any(marker in err_text for marker in SUPABASE_RETRYABLE_MARKERS)
            if not should_retry or attempt >= retries:
                raise
            print(f"Supabase transient error (attempt {attempt + 1}/{retries + 1}): {e}")
            supabase = _create_supabase_client()
            await asyncio.sleep(min(0.25 * (attempt + 1), 1.0))

    if last_error:
        raise last_error
    return None
