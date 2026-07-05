import os
import uuid
from fastapi import APIRouter, HTTPException, Request
from database import supabase
from utils import _admin_key_ok, _now_hk_iso
from memory_logic import (
    MEMORY_BACKFILL_JOBS, _run_memory_index_backfill, 
    get_latest_diary_entry, get_user_profile
)
from ai_logic import generate_comfort_message
import asyncio

router = APIRouter()

@router.post("/v1/memory/index/backfill")
async def start_memory_index_backfill(request: Request, user_id: str, days: int = 180, page_size: int = 80, max_pages: int = 25):
    if not os.getenv("MEMORY_ADMIN_KEY"):
        raise HTTPException(status_code=501, detail="Set MEMORY_ADMIN_KEY env to enable backfill.")
    if not _admin_key_ok(request):
        raise HTTPException(status_code=403, detail="Forbidden")
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase not configured")
    if days < 7 or days > 3650:
        raise HTTPException(status_code=400, detail="days must be between 7 and 3650")
    if page_size < 20 or page_size > 200:
        raise HTTPException(status_code=400, detail="page_size must be between 20 and 200")
    if max_pages < 1 or max_pages > 200:
        raise HTTPException(status_code=400, detail="max_pages must be between 1 and 200")

    job_id = str(uuid.uuid4())
    MEMORY_BACKFILL_JOBS[job_id] = {
        "job_id": job_id, "user_id": user_id, "days": days, "page_size": page_size, "max_pages": max_pages,
        "status": "queued", "pages_done": 0, "memories_processed": 0, "fact_batches_written": 0,
        "created_at": _now_hk_iso(), "updated_at": _now_hk_iso(),
    }
    asyncio.create_task(_run_memory_index_backfill(job_id, user_id, days, page_size, max_pages))
    return {"status": "ok", "job_id": job_id}

@router.get("/v1/memory/index/backfill/status")
async def get_memory_index_backfill_status(request: Request, job_id: str):
    if not os.getenv("MEMORY_ADMIN_KEY"):
        raise HTTPException(status_code=501, detail="Set MEMORY_ADMIN_KEY env to enable backfill.")
    if not _admin_key_ok(request):
        raise HTTPException(status_code=403, detail="Forbidden")
    job = MEMORY_BACKFILL_JOBS.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    return {"status": "ok", "job": job}

@router.get("/v1/check-comfort")
async def check_comfort(user_id: str):
    diary = await get_latest_diary_entry(user_id)
    if not diary:
        return {"should_comfort": False, "reason": "No diary found"}
    emotion = diary.get("emotion", "Neutral")
    negative_emotions = ["Sad", "Anxious", "Angry", "Depressed", "Lonely"]
    if emotion not in negative_emotions:
        return {"should_comfort": False, "reason": "Mood is not low"}
    profile = await get_user_profile(user_id)
    comfort_msg = await generate_comfort_message(diary, profile)
    return {
        "should_comfort": True, "message": comfort_msg,
        "diary_date": diary.get("date"), "emotion": emotion
    }
