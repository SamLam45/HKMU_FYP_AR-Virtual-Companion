import os
import time
import httpx
import asyncio
from typing import List, Dict, Tuple
from config import JINA_EMBED_CACHE_TTL_SECONDS, JINA_MIN_REQUEST_INTERVAL_SECONDS
from utils import _truncate_text

JINA_API_KEY = os.getenv("JINA_API_KEY")
if not JINA_API_KEY:
    print("Warning: JINA_API_KEY not found. Jina Embeddings will fail.")

# 建立全域 HTTPX Async Client，利用 Connection Pooling 加速請求
jina_async_client = httpx.AsyncClient(timeout=10.0)
JINA_429_COOLDOWN_UNTIL = 0.0
JINA_LAST_REQUEST_AT = 0.0
JINA_EMBED_CACHE: Dict[str, Tuple[float, List[float]]] = {}

async def get_embedding_async(text: str) -> List[float]:
    """非同步版本 get_embedding (已優化: 加上 HTTP Keep-Alive)"""
    global JINA_429_COOLDOWN_UNTIL, JINA_LAST_REQUEST_AT
    if not JINA_API_KEY:
        print("Error: JINA_API_KEY missing.")
        return [0.0] * 768

    clean_text = (text or "").strip()
    if not clean_text:
        return [0.0] * 768

    now_ts = time.time()
    cached = JINA_EMBED_CACHE.get(clean_text)
    if cached:
        cached_at, cached_vec = cached
        if (now_ts - cached_at) <= JINA_EMBED_CACHE_TTL_SECONDS:
            return cached_vec

    if now_ts < JINA_429_COOLDOWN_UNTIL:
        wait_left = max(0.0, JINA_429_COOLDOWN_UNTIL - now_ts)
        print(f"Jina API cooldown active ({wait_left:.2f}s left), skip embedding.")
        return [0.0] * 768

    delta = now_ts - JINA_LAST_REQUEST_AT
    if delta < JINA_MIN_REQUEST_INTERVAL_SECONDS:
        await asyncio.sleep(JINA_MIN_REQUEST_INTERVAL_SECONDS - delta)

    url = "https://api.jina.ai/v1/embeddings"
    headers = {
        "Authorization": f"Bearer {JINA_API_KEY}",
        "Content-Type": "application/json"
    }
    data = {
        "model": "jina-embeddings-v2-base-en", 
        "input": [clean_text]
    }
    
    try:
        JINA_LAST_REQUEST_AT = time.time()
        response = await jina_async_client.post(url, headers=headers, json=data)
        response.raise_for_status()
        result = response.json()
        if result and "data" in result:
                 vec = result["data"][0]["embedding"]
                 JINA_EMBED_CACHE[clean_text] = (time.time(), vec)
                 return vec
    except httpx.HTTPStatusError as e:
        status = e.response.status_code if e.response is not None else None
        if status == 429:
            retry_after = 2.0
            if e.response is not None:
                ra = e.response.headers.get("Retry-After")
                if ra:
                    try:
                        retry_after = float(ra)
                    except Exception:
                        retry_after = 2.0
            retry_after = max(0.5, min(retry_after, 60.0))
            JINA_429_COOLDOWN_UNTIL = time.time() + retry_after
            print(f"Jina API 429 rate-limited. Backing off for {retry_after:.2f}s.")
            return [0.0] * 768
        print(f"Jina API Async HTTP Error: {e}")
    except Exception as e:
        print(f"Jina API Async Error: {e}")
    return [0.0] * 768
