import time
import asyncio
from typing import Dict, Tuple, Optional
from config import CACHE_TTL
from memory_logic import get_user_profile, build_dynamic_system_prompt

SYSTEM_PROMPT_CACHE: Dict[str, Tuple[float, str]] = {}
PROFILE_CACHE: Dict[str, Tuple[float, Optional[Dict]]] = {}
SYSTEM_PROMPT_INFLIGHT: Dict[str, asyncio.Task] = {}
PROFILE_INFLIGHT: Dict[str, asyncio.Task] = {}
ACTIVE_LIVE_SOCKETS: Dict[str, set] = {}

def invalidate_user_runtime_cache(user_id: str) -> None:
    profile_key = f"profile_{user_id}"
    PROFILE_CACHE.pop(profile_key, None)
    profile_task = PROFILE_INFLIGHT.pop(profile_key, None)
    if profile_task and not profile_task.done():
        profile_task.cancel()

    for is_live in (True, False):
        prompt_key = f"{user_id}_{is_live}"
        SYSTEM_PROMPT_CACHE.pop(prompt_key, None)
        prompt_task = SYSTEM_PROMPT_INFLIGHT.pop(prompt_key, None)
        if prompt_task and not prompt_task.done():
            prompt_task.cancel()

async def close_active_live_sessions(user_id: str, reason: str = "settings_changed") -> int:
    sockets = ACTIVE_LIVE_SOCKETS.get(user_id)
    if not sockets:
        return 0
    targets = list(sockets)
    closed = 0
    for ws in targets:
        try:
            await ws.close(code=1012, reason=reason)
            closed += 1
        except Exception:
            pass
    if not ACTIVE_LIVE_SOCKETS.get(user_id):
        ACTIVE_LIVE_SOCKETS.pop(user_id, None)
    return closed

async def get_cached_user_profile(user_id: str) -> Optional[Dict]:
    cache_key = f"profile_{user_id}"
    now = time.time()
    if cache_key in PROFILE_CACHE:
        cached_time, profile = PROFILE_CACHE[cache_key]
        if now - cached_time < CACHE_TTL:
            return profile

    existing_task = PROFILE_INFLIGHT.get(cache_key)
    if existing_task:
        return await asyncio.shield(existing_task)

    async def _fetch_profile():
        profile = await get_user_profile(user_id)
        PROFILE_CACHE[cache_key] = (time.time(), profile)
        return profile

    task = asyncio.create_task(_fetch_profile())
    PROFILE_INFLIGHT[cache_key] = task
    try:
        return await asyncio.shield(task)
    finally:
        if PROFILE_INFLIGHT.get(cache_key) is task:
            PROFILE_INFLIGHT.pop(cache_key, None)

async def get_cached_system_prompt(user_id: str, is_live_mode: bool = False) -> str:
    cache_key = f"{user_id}_{is_live_mode}"
    now = time.time()
    if cache_key in SYSTEM_PROMPT_CACHE:
        cached_time, prompt = SYSTEM_PROMPT_CACHE[cache_key]
        if now - cached_time < CACHE_TTL:
            return prompt

    existing_task = SYSTEM_PROMPT_INFLIGHT.get(cache_key)
    if existing_task:
        return await asyncio.shield(existing_task)

    async def _build_prompt():
        prompt = await build_dynamic_system_prompt(user_id, is_live_mode)
        SYSTEM_PROMPT_CACHE[cache_key] = (time.time(), prompt)
        return prompt

    task = asyncio.create_task(_build_prompt())
    SYSTEM_PROMPT_INFLIGHT[cache_key] = task
    try:
        return await asyncio.shield(task)
    finally:
        if SYSTEM_PROMPT_INFLIGHT.get(cache_key) is task:
            SYSTEM_PROMPT_INFLIGHT.pop(cache_key, None)

def append_to_cached_system_prompt(user_id: str, user_text: str, ai_text: str):
    for is_live in (True, False):
        cache_key = f"{user_id}_{is_live}"
        if cache_key in SYSTEM_PROMPT_CACHE:
            cached_time, prompt = SYSTEM_PROMPT_CACHE[cache_key]
            history_marker = "【Recent Conversation History】:\n"
            if history_marker in prompt:
                parts = prompt.split(history_marker)
                before_history = parts[0]
                after_history_parts = parts[1].split("\n\n【", 1)
                history_content = after_history_parts[0]
                rest_of_prompt = f"\n\n【{after_history_parts[1]}" if len(after_history_parts) > 1 else ""
                new_memory_line = f"- User: {user_text}\n  AI: {ai_text}"
                updated_history = history_content + f"\n{new_memory_line}"
                new_prompt = before_history + history_marker + updated_history + rest_of_prompt
                SYSTEM_PROMPT_CACHE[cache_key] = (time.time(), new_prompt)
