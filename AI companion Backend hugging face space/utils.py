import os
import json
import time
from datetime import datetime
from typing import List, Dict, Tuple, Optional
from fastapi import Request
from config import HK_TIMEZONE

def _truncate_text(value: str, max_chars: int) -> str:
    if not value:
        return ""
    if len(value) <= max_chars:
        return value
    return value[:max_chars] + "..."

def _trim_context_parts(parts: List[str], max_chars: int) -> List[str]:
    if max_chars <= 0:
        return []
    out: List[str] = []
    used = 0
    for part in parts:
        if not part:
            continue
        remaining = max_chars - used
        if remaining <= 0:
            break
        if len(part) <= remaining:
            out.append(part)
            used += len(part)
            continue
        out.append(_truncate_text(part, remaining))
        break
    return out

def _now_hk_iso() -> str:
    return datetime.now(HK_TIMEZONE).isoformat()

def _safe_json_loads(value: str) -> Dict:
    try:
        payload = json.loads(value or "{}")
        return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}

def _normalize_fact_key(kind: str, key: str) -> str:
    k = (kind or "").strip().lower()
    name = (key or "").strip().lower()
    if not k:
        k = "fact"
    if not name:
        name = "unknown"
    return f"{k}:{name}"

def _admin_key_ok(request: Request) -> bool:
    required = os.getenv("MEMORY_ADMIN_KEY")
    if not required:
        return False
    got = request.headers.get("x-admin-key") or request.headers.get("X-Admin-Key")
    return bool(got) and got == required

def _trait_set(traits: Optional[List]) -> set:
    """Normalize trait labels for case-insensitive matching."""
    if not traits:
        return set()
    out: set = set()
    for t in traits:
        if t is None:
            continue
        s = str(t).strip()
        if s:
            out.add(s.lower())
    return out

def _canonical_from_allowed(raw: str, allowed: List[str]) -> Optional[str]:
    if not raw or not isinstance(raw, str):
        return None
    key = raw.strip().lower()
    for a in allowed:
        if a.lower() == key:
            return a
    return None
