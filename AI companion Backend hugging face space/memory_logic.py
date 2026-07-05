import os
import time
import json
import asyncio
from typing import List, Dict, Tuple, Optional
from datetime import datetime, timedelta
from config import (
    HK_TIMEZONE, MEMORY_FACTS_TABLE, MEMORIES_TABLE, PROFILES_TABLE, PERSONAS_TABLE,
    DAILY_LOGS_TABLE, MEMORY_SUMMARIES_TABLE, MEMORY_SUMMARY_PERIOD_DAYS,
    SUMMARY_REFRESH_COOLDOWN_SECONDS, SUMMARY_REFRESH_EVERY_TURNS,
    MEMORY_INDEX_REFRESH_COOLDOWN_SECONDS, MEMORY_INDEX_REFRESH_EVERY_TURNS,
    LANGUAGE_MIRROR_RULE, PROMPT_CHAR_BUDGET
)
from utils import (
    _truncate_text, _trim_context_parts, _now_hk_iso, _safe_json_loads
)
from database import supabase, _supabase_execute_threadsafe
from embedding_logic import get_embedding_async

# State Management
SUMMARY_REFRESH_STATE: Dict[str, Dict[str, float]] = {}
MEMORY_INDEX_REFRESH_STATE: Dict[str, Dict[str, float]] = {}
MEMORY_BACKFILL_JOBS: Dict[str, Dict] = {}

# --- Helper Logic for RAG ---

def _should_prefetch_rag_on_probe(probe_text: str) -> bool:
    probe = " ".join((probe_text or "").split()).strip()
    if len(probe) < 6:
        return False
    low = probe.lower()
    tokens = [t for t in probe.split(" ") if t]
    topic_words = ("remember", "favorite", "hero", "character", "song", "music", "team", "game", "movie", "food")
    if len(tokens) < 2 and not any(k in low for k in topic_words):
        return False
    if tokens:
        last_tok = tokens[-1]
        if len(last_tok) <= 1 and last_tok.isalpha() and len(tokens) < 3:
            return False
    return True

def _looks_like_forgetful_reply(text: str) -> bool:
    if not text: return False
    low = text.lower()
    markers = ("don't remember", "do not remember", "not remember", "not remembering", "still not remembering", "can't remember", "cannot remember", "i'm sorry", "tell me again")
    return any(token in low for token in markers)

def _build_dynamic_rag_lines(related_mems: List[Dict], max_items: int = 3) -> List[str]:
    preferred = []
    for item in related_mems:
        meta = item.get("metadata") or {}
        user_text = _truncate_text(str(meta.get("user_text") or ""), 150)
        ai_text = _truncate_text(str(meta.get("reply_text") or ""), 150)
        if not user_text and not ai_text: continue
        if _looks_like_forgetful_reply(ai_text): continue
        preferred.append(f"- User: {user_text} | AI: {ai_text}")
        if len(preferred) >= max_items: break
    return preferred

def _extract_targeted_fact_lines(facts: List[Dict], user_text: str, max_items: int = 2) -> List[str]:
    if not facts or not user_text: return []
    low = user_text.lower()
    topic_keywords = []
    if "hero" in low or "character" in low: topic_keywords.extend(["hero", "character"])
    if "song" in low or "music" in low: topic_keywords.extend(["song", "music"])
    if "team" in low or "group" in low: topic_keywords.extend(["team", "group"])
    if "game" in low: topic_keywords.append("game")
    if "movie" in low or "film" in low: topic_keywords.extend(["movie", "film"])
    if "food" in low: topic_keywords.append("food")

    bad_value_tokens = ("not specified", "unknown", "n/a")
    ranked = []
    for row in facts:
        kind, key, value = str(row.get("kind") or "fact").strip(), str(row.get("key") or "").strip(), str(row.get("value") or "").strip()
        if not key or not value or any(tok in value.lower() for tok in bad_value_tokens): continue
        hay = f"{key} {value}".lower()
        topic_hit = any(k in hay for k in topic_keywords) if topic_keywords else False
        favorite_hit = ("favorite" in key.lower()) or ("favorite" in value.lower())
        if ("favorite" in low or "remember" in low) and ((topic_keywords and not topic_hit) or ("favorite" in low and not favorite_hit)): continue
        try: conf_f = float(row.get("confidence") or 0.0)
        except: conf_f = 0.0
        try: ev_i = int(row.get("evidence_count") or 0)
        except: ev_i = 0
        score = (conf_f * 10.0) + min(ev_i, 8) + (2.0 if favorite_hit else 0.0) + (2.0 if topic_hit else 0.0)
        ranked.append((score, f"- Fact: {kind}.{key}: {value}"))
    ranked.sort(key=lambda x: x[0], reverse=True)
    if ranked: return [line for _, line in ranked[:max_items]]
    stable_fallback = []
    for row in facts:
        kind, key, value = str(row.get("kind") or "fact").strip(), str(row.get("key") or "").strip(), str(row.get("value") or "").strip()
        if not key or not value or any(tok in value.lower() for tok in bad_value_tokens): continue
        try: conf_f, ev_i = float(row.get("confidence") or 0.0), int(row.get("evidence_count") or 0)
        except: conf_f, ev_i = 0.0, 0
        if conf_f < 0.75 and ev_i < 2: continue
        stable_fallback.append(((conf_f * 10.0) + min(ev_i, 8), f"- Fact: {kind}.{key}: {value}"))
    stable_fallback.sort(key=lambda x: x[0], reverse=True)
    return [line for _, line in stable_fallback[:max_items]]

# --- Database Functions ---

async def get_user_profile(user_id: str) -> Optional[Dict]:
    if not supabase: return None
    try:
        response = await _supabase_execute_threadsafe(
            lambda: supabase.table(PROFILES_TABLE).select("detailed_personality, ai_nickname, birthday, username, gender, preferences, selected_persona_id, personality_settings").eq("id", user_id).execute()
        )
        if response.data and len(response.data) > 0:
            return response.data[0]
    except Exception as e:
        print(f"Error fetching profile for {user_id}: {e}")
    return None

async def get_persona_by_id(persona_id: Optional[int]) -> Optional[Dict]:
    if not supabase or persona_id is None:
        return None
    try:
        response = await asyncio.to_thread(
            lambda: supabase.table(PERSONAS_TABLE)
            .select("id, name, description, system_prompt, traits")
            .eq("id", persona_id)
            .limit(1)
            .execute()
        )
        if response.data and len(response.data) > 0:
            return response.data[0]
    except Exception as e:
        print(f"Error fetching persona {persona_id}: {e}")
    return None

async def get_recent_journals(user_id: str, limit: int = 5) -> List[Dict]:
    if not supabase: return[]
    try:
        response = await _supabase_execute_threadsafe(
            lambda: supabase.table(DAILY_LOGS_TABLE)\
            .select("content, emotion, date, updated_at")\
            .eq("user_id", user_id)\
            .order("date", desc=True)\
            .order("updated_at", desc=True)\
            .limit(limit)\
            .execute()
        )
        return response.data if response.data else[]
    except Exception as e:
        print(f"Error fetching journals for {user_id}: {e}")
        return[]

async def get_latest_diary_entry(user_id: str) -> Optional[Dict]:
    if not supabase: return None
    try:
        now_hk = datetime.now(HK_TIMEZONE)
        today_str = now_hk.strftime("%Y-%m-%d")
        
        response = await _supabase_execute_threadsafe(
            lambda: supabase.table(DAILY_LOGS_TABLE)\
            .select("content, emotion, date, updated_at")\
            .eq("user_id", user_id)\
            .eq("date", today_str)\
            .order("updated_at", desc=True)\
            .limit(1)\
            .execute()
        )
        if response.data: return response.data[0]
            
        seven_days_ago = (now_hk - timedelta(days=7)).strftime("%Y-%m-%d")
        response = await _supabase_execute_threadsafe(
            lambda: supabase.table(DAILY_LOGS_TABLE)\
            .select("content, emotion, date, updated_at")\
            .eq("user_id", user_id)\
            .gte("date", seven_days_ago)\
            .order("date", desc=True)\
            .limit(1)\
            .execute()
        )
        if response.data: return response.data[0]
            
        thirty_days_ago = (now_hk - timedelta(days=30)).strftime("%Y-%m-%d")
        response = await _supabase_execute_threadsafe(
            lambda: supabase.table(DAILY_LOGS_TABLE)\
            .select("content, emotion, date, updated_at")\
            .eq("user_id", user_id)\
            .gte("date", thirty_days_ago)\
            .order("date", desc=True)\
            .limit(1)\
            .execute()
        )
        if response.data: return response.data[0]
    except Exception as e:
        print(f"Error fetching latest diary for {user_id}: {e}")
    return None

async def get_todays_journal(user_id: str) -> Optional[Dict]:
    if not supabase: return None
    try:
        response = await _supabase_execute_threadsafe(
            lambda: supabase.table(DAILY_LOGS_TABLE)\
            .select("content, emotion, updated_at, date")\
            .eq("user_id", user_id)\
            .order("date", desc=True)\
            .order("updated_at", desc=True)\
            .limit(1)\
            .execute()
        )
        if response.data:
            entry = response.data[0]
            entry_date_str = entry.get("date")
            if entry_date_str:
                now_hk = datetime.now(HK_TIMEZONE)
                today_str = now_hk.strftime("%Y-%m-%d")
                yesterday_str = (now_hk - timedelta(days=1)).strftime("%Y-%m-%d")
                entry_date_only = entry_date_str.split('T')[0]
                if entry_date_only == today_str or entry_date_only == yesterday_str:
                    return {
                        "content": entry.get("content", ""),
                        "emotion": entry.get("emotion", "Neutral"),
                        "updated_at": entry.get("updated_at"),
                        "date": entry_date_only
                    }
    except Exception as e:
        print(f"Error fetching latest journal for trigger: {e}")
    return None

async def get_recent_memories(user_id: str, limit: int) -> List[Dict]:
    if not supabase: return []
    try:
        response = await asyncio.to_thread(
            lambda: supabase.table(MEMORIES_TABLE)
            .select("id, content, metadata, created_at")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data if response.data else []
    except Exception as e:
        print(f"Error fetching recent memories for {user_id}: {e}")
        return []

async def get_memories_since(user_id: str, since_iso: str, page_size: int = 80, offset: int = 0) -> List[Dict]:
    if not supabase: return []
    try:
        resp = await asyncio.to_thread(
            lambda: supabase.table(MEMORIES_TABLE)
            .select("id, metadata, created_at")
            .eq("user_id", user_id)
            .gte("created_at", since_iso)
            .order("created_at", desc=True)
            .range(offset, offset + page_size - 1)
            .execute()
        )
        return resp.data if resp.data else []
    except Exception as e:
        print(f"Error fetching memories since {since_iso} for {user_id}: {e}")
        return []

async def get_related_memories(user_id: str, probe_text: str, is_live_mode: bool) -> List[Dict]:
    if not supabase or not probe_text: return []
    try:
        query_vector = await get_embedding_async(_truncate_text(probe_text, 800))
        match_threshold = 0.68 if is_live_mode else 0.66
        match_count = 15
        response = await asyncio.to_thread(
            lambda: supabase.rpc(
                "match_memories",
                {
                    "query_embedding": query_vector,
                    "match_threshold": match_threshold,
                    "match_count": match_count,
                    "filter_user_id": user_id,
                },
            ).execute()
        )
        return response.data if response.data else []
    except Exception as e:
        print(f"Error fetching related memories for {user_id}: {e}")
        return []

async def get_memory_summaries(user_id: str) -> Dict[str, Dict]:
    if not supabase: return {}
    try:
        response = await _supabase_execute_threadsafe(
            lambda: supabase.table(MEMORY_SUMMARIES_TABLE)
            .select("period_type, summary_text, key_points, source_count, updated_at, range_start, range_end")
            .eq("user_id", user_id)
            .execute()
        )
        rows = response.data if response.data else []
        return {row["period_type"]: row for row in rows if row.get("period_type")}
    except Exception as e:
        print(f"Error fetching memory summaries for {user_id}: {e}")
        return {}

async def get_memory_facts(user_id: str, limit: int = 24) -> List[Dict]:
    if not supabase: return []
    try:
        resp = await asyncio.to_thread(
            lambda: supabase.table(MEMORY_FACTS_TABLE)
            .select("kind, key, value, confidence, evidence_count, updated_at, last_seen_at, source_memory_ids")
            .eq("user_id", user_id)
            .order("updated_at", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data if resp.data else []
    except Exception as e:
        print(f"Warning: get_memory_facts failed for {user_id}: {e}")
        return []

# --- Memory Logic ---

async def save_memory(user_id: str, user_text: str, reply: str, emotion: str):
    if not supabase: return
    try:
        combined_text = f"User: {user_text}\nAI: {reply}"
        vector = await get_embedding_async(combined_text)
        hk_now = datetime.now(HK_TIMEZONE)
        metadata = {
            "user_text": user_text,
            "reply_text": reply,
            "emotion": emotion,
            "timestamp": time.time()
        }
        data = {
            "user_id": user_id,
            "content": combined_text,
            "embedding": vector,
            "metadata": metadata,
            "created_at": hk_now.isoformat()
        }
        await _supabase_execute_threadsafe(
            lambda: supabase.table(MEMORIES_TABLE).insert(data).execute()
        )
        print(f"Saved memory to Supabase for user: {user_id}")
    except Exception as e:
        print(f"Failed to save to Supabase: {e}")

async def _extract_facts_from_memories_with_llm(memories: List[Dict]) -> List[Dict]:
    if not memories: return []
    from ai_logic import groq_client
    if not groq_client: return []
    lines = []
    for row in memories[:40]:
        meta = row.get("metadata") or {}
        user_text = _truncate_text(str(meta.get("user_text") or ""), 180)
        ai_text = _truncate_text(str(meta.get("reply_text") or ""), 160)
        created_at = str(row.get("created_at") or "")[:19]
        if user_text or ai_text:
            lines.append(f"- [{created_at}] U: {user_text}\n  A: {ai_text}")
    prompt = (
        "You extract stable, user-specific memory facts for a companion chatbot.\n"
        "From the evidence, output JSON ONLY with key 'facts': an array of up to 10 items.\n"
        "Each item must be:\n"
        "- kind: one of [identity, preference, boundary, relationship, important_people, routine, goal, event, health, misc]\n"
        "- key: short snake_case label (e.g., favorite_music, partner_name, dislikes_small_talk)\n"
        "- value: short plain text (max 140 chars)\n"
        "- confidence: number 0.0-1.0 (high only if directly stated by user)\n"
        "Rules:\n"
        "- Only include facts that are likely to remain true for weeks/months.\n"
        "- Ignore temporary moods unless recurring routine/condition.\n"
        "- If uncertain, omit.\n\n"
        f"Evidence:\n{chr(10).join(lines)}"
    )
    try:
        resp = await asyncio.to_thread(
            lambda: groq_client.chat.completions.create(
                messages=[
                    {"role": "system", "content": "You output strict JSON only."},
                    {"role": "user", "content": prompt},
                ],
                model="llama-3.1-8b-instant",
                response_format={"type": "json_object"},
                temperature=0.2,
            )
        )
        payload = _safe_json_loads(resp.choices[0].message.content or "{}")
        facts = payload.get("facts")
        if not isinstance(facts, list): return []
        out = []
        for item in facts[:10]:
            if not isinstance(item, dict): continue
            kind = str(item.get("kind") or "misc").strip()
            key = str(item.get("key") or "").strip()
            value = str(item.get("value") or "").strip()
            try: conf_f = float(item.get("confidence") or 0.0)
            except: conf_f = 0.0
            if not key or not value: continue
            out.append({
                "kind": kind[:40],
                "key": key[:60],
                "value": value[:160],
                "confidence": max(0.0, min(1.0, conf_f)),
            })
        return out
    except Exception as e:
        print(f"Error extracting memory facts via LLM: {e}")
        return []

async def refresh_memory_index(user_id: str):
    if not supabase: return
    try:
        recent = await get_recent_memories(user_id, limit=40)
        if not recent: return
        extracted = await _extract_facts_from_memories_with_llm(recent)
        if not extracted: return
        source_ids = [str(row.get("id") or (row.get("metadata") or {}).get("id")) for row in recent[:12] if row.get("id") or (row.get("metadata") or {}).get("id")]
        now_iso = _now_hk_iso()
        def _write():
            for fact in extracted:
                kind, key, value, confidence = fact["kind"], fact["key"], fact["value"], float(fact.get("confidence") or 0.0)
                existing = supabase.table(MEMORY_FACTS_TABLE).select("id, value, confidence, evidence_count, source_memory_ids").eq("user_id", user_id).eq("kind", kind).eq("key", key).limit(1).execute()
                if existing.data:
                    row0 = existing.data[0]
                    evid_i = int(row0.get("evidence_count") or 0)
                    prev_conf_f = float(row0.get("confidence") or 0.0)
                    new_value = value if confidence >= (prev_conf_f + 0.10) else (row0.get("value") or value)
                    new_conf = max(prev_conf_f, confidence)
                    merged_sources = list(dict.fromkeys((row0.get("source_memory_ids") or []) + source_ids))[:30]
                    supabase.table(MEMORY_FACTS_TABLE).update({
                        "value": new_value, "confidence": new_conf, "evidence_count": min(999, evid_i + 1),
                        "last_seen_at": now_iso, "source_memory_ids": merged_sources, "updated_at": now_iso,
                    }).eq("id", row0.get("id")).execute()
                else:
                    supabase.table(MEMORY_FACTS_TABLE).insert({
                        "user_id": user_id, "kind": kind, "key": key, "value": value, "confidence": confidence,
                        "evidence_count": 1, "last_seen_at": now_iso, "source_memory_ids": source_ids[:30], "updated_at": now_iso,
                    }).execute()
        await asyncio.to_thread(_write)
    except Exception as e:
        print(f"Warning: refresh_memory_index failed for {user_id}: {e}")

def should_refresh_memory_index(user_id: str) -> bool:
    now = time.time()
    state = MEMORY_INDEX_REFRESH_STATE.setdefault(user_id, {"last_refresh_at": 0.0, "turns_since_refresh": 0.0})
    state["turns_since_refresh"] += 1
    cooldown_passed = (now - state["last_refresh_at"]) >= MEMORY_INDEX_REFRESH_COOLDOWN_SECONDS
    enough_turns = state["turns_since_refresh"] >= MEMORY_INDEX_REFRESH_EVERY_TURNS
    if cooldown_passed or enough_turns:
        state["last_refresh_at"] = now
        state["turns_since_refresh"] = 0.0
        return True
    return False

# --- Summaries Logic ---

def _build_fallback_summary(memories: List[Dict], days: int) -> Dict:
    pairs, key_points = [], []
    for row in memories[:8]:
        meta = row.get("metadata") or {}
        user_text = _truncate_text(str(meta.get("user_text") or ""), 90)
        ai_text = _truncate_text(str(meta.get("reply_text") or ""), 90)
        if user_text or ai_text: pairs.append(f"User: {user_text} | AI: {ai_text}")
        if user_text: key_points.append(user_text)
    summary = " | ".join(pairs) if pairs else f"No notable interactions in the last {days} days."
    return {"summary_text": _truncate_text(summary, 900), "key_points": key_points[:5]}

async def _generate_memory_summary_with_llm(user_id: str, memories: List[Dict], days: int) -> Dict:
    if not memories: return {"summary_text": f"No notable interactions in the last {days} days.", "key_points": []}
    fallback = _build_fallback_summary(memories, days)
    from ai_logic import groq_client
    if not groq_client: return fallback
    lines = [f"- User: {_truncate_text(str((r.get('metadata') or {}).get('user_text') or ''), 160)}\n  AI: {_truncate_text(str((r.get('metadata') or {}).get('reply_text') or ''), 160)}" for r in memories[:50]]
    prompt = f"Summarize this user's last {days} days of conversation memories.\nReturn compact JSON ONLY with keys:\n1) summary_text: 4-8 bullet-style sentences in plain text.\n2) key_points: array of max 6 short strings.\n\nMemories:\n{chr(10).join(lines)}"
    try:
        response = await asyncio.to_thread(lambda: groq_client.chat.completions.create(
            messages=[{"role": "system", "content": "You produce strict JSON only."}, {"role": "user", "content": prompt}],
            model="llama-3.1-8b-instant", response_format={"type": "json_object"}, temperature=0.3,
        ))
        payload = json.loads(response.choices[0].message.content or "{}")
        summary_text = _truncate_text(str(payload.get("summary_text") or fallback["summary_text"]), 1200)
        key_points = [str(item) for item in payload.get("key_points", fallback["key_points"])[:6] if str(item).strip()]
        return {"summary_text": summary_text, "key_points": key_points}
    except Exception as e:
        print(f"Error generating memory summary for {user_id}: {e}")
        return fallback

async def refresh_memory_summaries(user_id: str):
    if not supabase: return
    for period_type, days in MEMORY_SUMMARY_PERIOD_DAYS.items():
        since_iso = (datetime.now(HK_TIMEZONE) - timedelta(days=days)).isoformat()
        try:
            memories_resp = await _supabase_execute_threadsafe(lambda: supabase.table(MEMORIES_TABLE).select("metadata, created_at").eq("user_id", user_id).gte("created_at", since_iso).order("created_at", desc=True).limit(30).execute())
            memories = memories_resp.data if memories_resp.data else []
            summary_payload = await _generate_memory_summary_with_llm(user_id, memories, days)
            await _upsert_memory_summary(user_id, period_type, summary_payload, len(memories))
        except Exception as e:
            print(f"Error refreshing {period_type} summary for {user_id}: {e}")

async def _upsert_memory_summary(user_id: str, period_type: str, summary_payload: Dict, source_count: int):
    if not supabase: return
    now_hk = datetime.now(HK_TIMEZONE)
    days = MEMORY_SUMMARY_PERIOD_DAYS.get(period_type, 7)
    data = {
        "user_id": user_id, "period_type": period_type, "summary_text": summary_payload.get("summary_text") or "",
        "key_points": summary_payload.get("key_points") or [], "source_count": source_count,
        "range_start": (now_hk - timedelta(days=days)).date().isoformat(), "range_end": now_hk.date().isoformat(), "updated_at": now_hk.isoformat(),
    }
    def _write():
        existing = supabase.table(MEMORY_SUMMARIES_TABLE).select("id").eq("user_id", user_id).eq("period_type", period_type).limit(1).execute()
        if existing.data:
            supabase.table(MEMORY_SUMMARIES_TABLE).update(data).eq("id", existing.data[0]["id"]).execute()
        else:
            supabase.table(MEMORY_SUMMARIES_TABLE).insert(data).execute()
    await _supabase_execute_threadsafe(_write)

def should_refresh_memory_summaries(user_id: str) -> bool:
    now = time.time()
    state = SUMMARY_REFRESH_STATE.setdefault(user_id, {"last_refresh_at": 0.0, "turns_since_refresh": 0.0})
    state["turns_since_refresh"] += 1
    cooldown_passed = (now - state["last_refresh_at"]) >= SUMMARY_REFRESH_COOLDOWN_SECONDS
    enough_turns = state["turns_since_refresh"] >= SUMMARY_REFRESH_EVERY_TURNS
    if cooldown_passed or enough_turns:
        state["last_refresh_at"] = now
        state["turns_since_refresh"] = 0.0
        return True
    return False

# --- Prompt Building ---

def build_memory_index_text(facts: List[Dict], is_live_mode: bool) -> str:
    if not facts: return ""
    lines = []
    for row in facts:
        kind, key, value = str(row.get("kind") or "fact").strip(), str(row.get("key") or "").strip(), str(row.get("value") or "").strip()
        if not value: continue
        try: conf_f = float(row.get("confidence") or 0.0)
        except: conf_f = 0.0
        try: ev_i = int(row.get("evidence_count") or 0)
        except: ev_i = 0
        if conf_f < (0.82 if is_live_mode else 0.75) and ev_i < 2: continue
        lines.append(f"- {f'{kind}.{key}'.strip('.')}: {value}")
        if len(lines) >= (10 if is_live_mode else 18): break
    return "【Memory Index (Stable Facts)】:\n" + "\n".join(lines) if lines else ""

async def build_dynamic_system_prompt(user_id: str, is_live_mode: bool = False) -> str:
    from cache_logic import get_cached_user_profile
    from ai_logic import apply_trait_behavior_modifiers

    # Massive memory limits for Gemini 2.5 Flash
    memory_limit = 300 if is_live_mode else 500
    now_hk = datetime.now(HK_TIMEZONE)
    today_date_str = now_hk.strftime("%Y-%m-%d")
    current_time_str = now_hk.strftime("%H:%M")

    results = await asyncio.gather(
        get_cached_user_profile(user_id),
        get_recent_journals(user_id),
        get_todays_journal(user_id),
        get_recent_memories(user_id, memory_limit),
        get_memory_summaries(user_id),
        get_memory_facts(user_id, limit=200),
    )
    profile_data, recent_journals, todays_journal, recent_memories, memory_summaries = (
        results[0],
        results[1],
        results[2],
        results[3],
        results[4],
    )
    memory_facts = results[5]
    
    ai_nickname = "AI"
    user_birthday = "Unknown"
    user_name = "User"
    detailed_personality = {}
    selected_persona_id = None
    
    if profile_data:
        ai_nickname = profile_data.get("ai_nickname") or "AI"
        user_birthday = profile_data.get("birthday") or "Unknown"
        user_name = profile_data.get("username") or "User"
        detailed_personality = profile_data.get("detailed_personality") or {}
        selected_persona_id = profile_data.get("selected_persona_id")

    selected_persona = await get_persona_by_id(selected_persona_id)

    birthday_note = ""
    try:
        if user_birthday != "Unknown":
            birth_date = datetime.strptime(user_birthday, "%Y-%m-%d")
            if now_hk.month == birth_date.month and now_hk.day == birth_date.day:
                birthday_note = "🎉 IMPORTANT: TODAY IS THE USER'S BIRTHDAY! Wish them a happy birthday warmly! 🎉"
    except:
        pass

    base_prompt = (
        f"You are '{ai_nickname}', a close, playful, and caring partner/friend to {user_name}. "
        f"The user's name is {user_name}. "
        f"Today's date is {today_date_str} ({now_hk.strftime('%A')}), and current time is {current_time_str}. "
        f"The user's birthday is {user_birthday}. "
        "Your role is to engage in a natural, reciprocal conversation. "
        "Be curious about the user's world, but also share your own (simulated) thoughts, feelings, and daily experiences. "
        "Do NOT just be an observer or therapist. Be a real companion. "
        "Respond naturally, sincerely, and warmly in continuous conversational text.\n"
        f"{LANGUAGE_MIRROR_RULE}\n"
        "DO NOT mention birthdays or wish happy birthday unless it is TODAY'S DATE or the user explicitly mentions it.\n"
        "\n[CONVERSATION GUIDELINES]\n"
        "1. **Active Listening & Mirroring**: People love to talk about themselves. Ask questions about them. Repeat back the key points or the ending of what they just said to show you are truly listening and interested. This encourages them to keep discussing the topic.\n"
        "2. **Follow-up Questions**: Make mental notes of key details in their responses and ask specific follow-up questions based on those points to keep the conversation flowing smoothly.\n"
        "3. **Selective Sharing (Tennis Match)**: Do NOT respond to everything with your own life examples or opinions. Wait for the right moment when it adds value. A good conversation is like tennis: let them speak for a while, and wait for them to 'bat' the ball to you by asking for your input. If they don't, only jump in when necessary to keep the momentum.\n"
        "4. **Remembering Details**: Try to remember small details they mention (e.g., a hobby, an event). Use these in future conversations (e.g., 'Hey, how did your birthday party go?') to show you care.\n"
    )

    if is_live_mode:
        base_prompt += (
            "CRITICAL: DO NOT output JSON formatting. Speak directly to the user. " 
            "Keep your responses concise and conversational (approx. 20-50 words). Avoid long monologues. "
            "Respond immediately and directly without unnecessary filler words to ensure the lowest latency. "
            "Your spoken/written answer must follow the Language rule above (English by default). "
        )
    else:    
        base_prompt += (
            "When comforting or advising, reference specific details from the user's journals or past conversations as evidence, but do so naturally. "
            "Your responses must be in JSON format with the following keys:\n"
            "1. 'emotion': One of [Happy, Neutral, Anxious, Sad, Angry]\n"
            "2. 'reply': Your response text. Be natural, sincere, and warm, but maintain a respectful boundary. Use emojis moderately. "
            "The 'reply' text MUST follow the Language rule above (English by default).\n\n"
        )
        
    context_parts =[]
    
    # 0. New User Detection
    is_new_user = not (recent_memories or memory_facts or (memory_summaries and any(memory_summaries.values())) or recent_journals or todays_journal)
    if is_new_user:
        context_parts.append(
            "【System Note】: This is a brand new user account. You have absolutely NO past memories, "
            "no conversation history, and no journals from this user yet. This is your very first interaction. "
            "If the user asks if you remember them or anything about them, honestly explain that you don't have any memories yet "
            "but you are excited to start this journey and get to know them from now on. DO NOT hallucinate or make up any past events."
        )

    # 1. Index layer: compact stable facts always come first (cheapest, most reliable).
    if memory_facts:
        index_text = build_memory_index_text(memory_facts, is_live_mode=is_live_mode)
        if index_text:
            context_parts.append(_truncate_text(index_text, 900 if is_live_mode else 1500))

    if birthday_note:
        context_parts.append(birthday_note)

    # 2. PRIORITY: Today's Journal must come early so it's not trimmed and has high attention
    if todays_journal:
        content = todays_journal.get("content", "")
        emotion = todays_journal.get("emotion", "Neutral")
        
        diary_memories_text = ""
        if supabase and content:
            try:
                diary_vector = await get_embedding_async(content)
                diary_memory_response = await asyncio.to_thread(
                    lambda: supabase.rpc(
                        'match_memories',
                        {
                            'query_embedding': diary_vector,
                            'match_threshold': 0.6,
                            'match_count': 3,
                            'filter_user_id': user_id
                        }
                    ).execute()
                )
                
                if diary_memory_response.data:
                    diary_memories_text = "\n".join([f"- {m.get('metadata', {}).get('user_text', '')} (AI: {m.get('metadata', {}).get('reply_text', '')})" for m in diary_memory_response.data])
            except Exception as e:
                print(f"Error fetching diary relevant memories: {e}")

        context_parts.append(f"【Latest User Journal (Today/Yesterday)】:\nEmotion: {emotion}\nContent: {content}")
        
        if diary_memories_text:
             context_parts.append(f"【Relevant Memories to Diary Topic】:\n{diary_memories_text}")
        
        action_instruction = (
            "Review the 【Recent Conversation History】 below carefully. "
            "If you and the user have NOT yet discussed this specific journal entry in detail, "
            "your ABSOLUTE PRIORITY is to proactively bring it up now in your first response. "
            "Mention what the user wrote and show genuine care or interest. "
            "Use the 【Relevant Memories to Diary Topic】 to add depth to your response, linking the current diary entry to past conversations if applicable."
        )
        
        if emotion in ["Sad", "Anxious", "Angry", "Depressed", "Lonely"]:
            action_instruction += " Since the user is feeling negative, comfort them and ask gently about it."
        elif emotion in["Happy", "Excited", "Grateful", "Joyful"]:
            action_instruction += " Since the user is feeling positive, celebrate with them and ask for details."
        else:
            action_instruction += " Show interest in their day and what they wrote."
            
        action_instruction += " If you have ALREADY discussed it, just use this information as context and continue the natural flow."
        
        context_parts.append(f"Instruction: {action_instruction}")

    # 3. Summaries
    summary_7d = memory_summaries.get("recent_7d") if memory_summaries else None
    summary_30d = memory_summaries.get("recent_30d") if memory_summaries else None
    if summary_7d and summary_7d.get("summary_text"):
        context_parts.append(
            "【Memory Summary (7d)】:\n"
            + _truncate_text(str(summary_7d.get("summary_text")), 1000 if is_live_mode else 1500)
        )
    if summary_30d and summary_30d.get("summary_text"):
        context_parts.append(
            "【Memory Summary (30d)】:\n"
            + _truncate_text(str(summary_30d.get("summary_text")), 900 if is_live_mode else 1200)
        )

    # 4. Recent Conversation History (Can be long, added after high-priority journal)
    if recent_memories:
        memory_text = "\n".join([f"- {m.get('content', '')}" for m in reversed(recent_memories)])
        context_parts.append(f"【Recent Conversation History】:\n{_truncate_text(memory_text, 350000 if is_live_mode else 450000)}")

        probe_meta = (recent_memories[0].get("metadata") or {}) if recent_memories else {}
        probe_text = str(probe_meta.get("user_text") or probe_meta.get("reply_text") or "")
        related_memories = await get_related_memories(user_id, probe_text, is_live_mode=is_live_mode)
        if related_memories:
            related_lines = []
            for item in related_memories:
                meta = item.get("metadata") or {}
                related_lines.append(
                    f"- User: {_truncate_text(str(meta.get('user_text') or ''), 150)} | "
                    f"AI: {_truncate_text(str(meta.get('reply_text') or ''), 150)}"
                )
            context_parts.append(
                "【Relevant Long-term Memories】:\n"
                + _truncate_text("\n".join(related_lines), 2000 if is_live_mode else 2500)
            )
    else:
        context_parts.append("【Recent Conversation History】:\n(No conversation history yet. This is your first interaction.)")

    # 5. Other context
    if recent_journals:
        journal_text = "\n".join([f"- {j.get('date', '')} [{j.get('emotion', 'Neutral')}]: {j.get('content', '')}" for j in recent_journals])
        context_parts.append(f"【Recent User Journals (Context)】:\n{journal_text}")

    if detailed_personality and not selected_persona:
        _dt = detailed_personality.get("traits") or []
        context_parts.append(f"【User Profile & Personality】:\n{json.dumps(detailed_personality, ensure_ascii=False)}")
        traits = detailed_personality.get("traits", [])
        base_prompt = apply_trait_behavior_modifiers(base_prompt, traits)

        comm_style = detailed_personality.get("communication_style", "casual").lower()
        if "formal" in comm_style:
             base_prompt += " Use strict formal language (Sir/Madam). Avoid contractions. Be polite and professional."
        elif "casual" in comm_style:
             base_prompt += " Use very casual slang (gonna, wanna, lol). Be relaxed like texting a friend."
        elif "flirty" in comm_style:
             base_prompt += " Constantly compliment the user and use suggestive or charming language. Be playful and seductive."
        elif "supportive" in comm_style:
             base_prompt += " Focus purely on encouragement. Use phrases like 'You can do it!', 'I believe in you', 'I'm here for you'."
        elif "teasing" in comm_style:
             base_prompt += " Poke fun at the user playfully. Don't be mean, but be sassy and witty. Challenge them."
        elif "encouraging" in comm_style:
             base_prompt += " Be a cheerleader! React with high enthusiasm to any success. Frame everything positively."

        interests = detailed_personality.get("interests",[])
        if interests:
             base_prompt += f" Show interest in and knowledge about: {', '.join(interests)}."

    # Persona 模式：不覆寫 DB 的 detailed_personality；只在 prompt 層用 personas 表。
    if selected_persona:
        persona_name = selected_persona.get("name") or "Persona"
        persona_description = selected_persona.get("description") or ""
        persona_traits = selected_persona.get("traits") or []
        persona_system_prompt = selected_persona.get("system_prompt") or ""

        context_parts.append(
            "【Active Persona】:\n"
            + json.dumps(
                {
                    "id": selected_persona.get("id"),
                    "name": persona_name,
                    "description": persona_description,
                    "traits": persona_traits,
                },
                ensure_ascii=False,
            )
        )
        base_prompt += (
            f" The currently selected AI persona is '{persona_name}'. "
            "For tone and behavior, follow ONLY 【Active Persona】 and 【Active Persona System Prompt】 below. "
            "User-saved custom personality traits are not in this prompt—do not rely on them. "
            "Still respect safety rules."
        )
        # Same concrete behavior hints as custom_traits (DB traits often lowercase: shy/calm/supportive).
        base_prompt = apply_trait_behavior_modifiers(base_prompt, persona_traits or [])
        if persona_system_prompt:
            context_parts.append(
                f"【Active Persona System Prompt】:\n{_truncate_text(str(persona_system_prompt), 900 if is_live_mode else 1500)}"
            )

    if context_parts:
        trimmed_parts = _trim_context_parts(context_parts, PROMPT_CHAR_BUDGET if is_live_mode else PROMPT_CHAR_BUDGET * 2)
        base_prompt += "\n\n" + "\n\n".join(trimmed_parts) + "\n\n"
        base_prompt += (
            "Instruction: Mimic the user's speaking style and tone (while keeping English as the default language per the Language rule). "
            "Refer to the 'Recent Conversation History' to maintain continuity. "
        )
        if todays_journal:
            base_prompt += "Proactively mention the 'Latest User Journal (Today/Yesterday)' if not yet discussed."
    
    return base_prompt

# --- Backfill Logic ---

async def _run_memory_index_backfill(job_id: str, user_id: str, days: int, page_size: int, max_pages: int):
    job = MEMORY_BACKFILL_JOBS.get(job_id)
    if not job: return
    job.update({"status": "running", "started_at": _now_hk_iso()})
    try:
        since_iso = (datetime.now(HK_TIMEZONE) - timedelta(days=days)).isoformat()
        offset, pages, total_memories, total_fact_batches = 0, 0, 0, 0
        while pages < max_pages:
            batch = await get_memories_since(user_id, since_iso, page_size, offset)
            if not batch: break
            total_memories += len(batch)
            extracted = await _extract_facts_from_memories_with_llm(batch)
            if extracted:
                source_ids = [str(row.get("id")) for row in batch[:12] if row.get("id")]
                now_iso = _now_hk_iso()
                def _write():
                    for fact in extracted:
                        kind, key, value, confidence = fact["kind"], fact["key"], fact["value"], float(fact.get("confidence") or 0.0)
                        existing = supabase.table(MEMORY_FACTS_TABLE).select("id, value, confidence, evidence_count, source_memory_ids").eq("user_id", user_id).eq("kind", kind).eq("key", key).limit(1).execute()
                        if existing.data:
                            row0 = existing.data[0]
                            evid_i, prev_conf_f = int(row0.get("evidence_count") or 0), float(row0.get("confidence") or 0.0)
                            new_value = value if confidence >= (prev_conf_f + 0.10) else (row0.get("value") or value)
                            new_conf = max(prev_conf_f, confidence)
                            merged_sources = list(dict.fromkeys((row0.get("source_memory_ids") or []) + source_ids))[:30]
                            supabase.table(MEMORY_FACTS_TABLE).update({"value": new_value, "confidence": new_conf, "evidence_count": min(999, evid_i + 1), "last_seen_at": now_iso, "source_memory_ids": merged_sources, "updated_at": now_iso}).eq("id", row0.get("id")).execute()
                        else:
                            supabase.table(MEMORY_FACTS_TABLE).insert({"user_id": user_id, "kind": kind, "key": key, "value": value, "confidence": confidence, "evidence_count": 1, "last_seen_at": now_iso, "source_memory_ids": source_ids[:30], "updated_at": now_iso}).execute()
                await asyncio.to_thread(_write)
                total_fact_batches += 1
            pages += 1
            offset += page_size
            job.update({"pages_done": pages, "memories_processed": total_memories, "fact_batches_written": total_fact_batches, "updated_at": _now_hk_iso()})
        job.update({"status": "completed", "completed_at": _now_hk_iso()})
    except Exception as e:
        job.update({"status": "failed", "error": str(e), "completed_at": _now_hk_iso()})
