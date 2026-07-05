---
title: Ai Companion
emoji: 🏆
colorFrom: pink
colorTo: red
sdk: docker
pinned: false
short_description: AI AR backend API
---

# AI Companion Backend (FastAPI)

This backend powers the AR AI companion app. It loads user profile and memory context from Supabase, builds a dynamic system prompt, streams real-time audio chat through Gemini Live, and exposes memory/persona APIs.

## What this service does

- Builds a context-rich prompt from profile, journals, memory facts, summaries, and recent conversation history.
- Runs low-latency live chat over WebSocket with speech in/out.
- Saves each turn as memory and periodically refreshes long-term facts/summaries.
- Supports persona analysis and comfort-message generation.
- Provides admin-protected memory backfill endpoints.

## Quick start

```bash
cd "AI companion Backend huggingface"
pip install -r requirements.txt
# set required env vars
uvicorn main:app --host 0.0.0.0 --port 8000
```

Health check: `GET /health`

## Environment variables

| Variable | Required | Used by | Purpose |
|---|---|---|---|
| `GEMINI_API_KEY` | Yes (for live chat) | `routes_chat.py`, `ai_logic.py` | Gemini Live connection |
| `SUPABASE_URL` | Yes (for data features) | `database.py` | Supabase connection |
| `SUPABASE_KEY` | Yes (for data features) | `database.py` | Supabase connection |
| `JINA_API_KEY` | Optional (recommended) | `embedding_logic.py` | Embeddings for semantic memory retrieval |
| `GROQ_API_KEY` | Optional | `ai_logic.py`, `memory_logic.py`, `routes_persona.py` | Persona analysis + memory/fact summarization + comfort text |
| `MEMORY_ADMIN_KEY` | Optional | `routes_memory.py`, `utils.py` | Protects admin memory backfill routes |

## API overview

### Core
- `GET /health`
- `GET /v1/chat/prepare?user_id=...&force_refresh=false`
- `WS /v1/chat/live?user_id=...`

### Memory/Admin
- `POST /v1/memory/index/backfill`
- `GET /v1/memory/index/backfill/status`
- `GET /v1/check-comfort?user_id=...`

### Persona
- `POST /v1/persona/analyze`

## Runtime flow (high level)

1. Client calls `GET /v1/chat/prepare` to warm caches.
2. Client opens `WS /v1/chat/live`.
3. Server loads cached profile + dynamic system prompt.
4. Server starts Gemini Live session and pushes a settings override message.
5. During chat, server forwards audio/text/image input to Gemini.
6. Server streams transcript/audio output back to client.
7. On turn completion, server saves memory and refreshes summaries/index as needed.

## File-by-file reference

### Entry, deployment, and dependencies

| File | Responsibility |
|---|---|
| `main.py` | Creates FastAPI app, registers routers (`chat`, `memory`, `persona`), defines `/health`. |
| `Dockerfile` | Container runtime for Hugging Face Spaces (installs deps, runs `uvicorn` on port `7860`). |
| `requirements.txt` | Python dependencies (FastAPI, Supabase, Groq, Google GenAI, HTTP/WebSocket stack). |
| `.gitattributes` | Git LFS patterns for large/binary files; not part of app runtime logic. |

### Configuration and shared constants

| File | Responsibility |
|---|---|
| `config.py` | Global constants: timezone, language rules, prompt/memory budgets, table names, persona allowed lists, cache TTL, fallback live prompt. |

### Database access

| File | Responsibility |
|---|---|
| `database.py` | Creates global Supabase client from env vars and provides `_supabase_execute_threadsafe()` for serialized, retryable DB calls. |

### Shared utility helpers

| File | Responsibility |
|---|---|
| `utils.py` | Text trimming/truncation, safe JSON parsing, HK timestamp helper, admin-key verification, trait normalization helpers. |

### Request models

| File | Responsibility |
|---|---|
| `models.py` | Pydantic models for API request bodies (currently `AnalysisRequest`). |

### AI and persona logic

| File | Responsibility |
|---|---|
| `ai_logic.py` | Initializes Gemini/Groq clients, applies trait behavior modifiers, sanitizes persona JSON, builds live settings update payload, resolves live voice, generates comfort messages. |

### Embedding + semantic retrieval support

| File | Responsibility |
|---|---|
| `embedding_logic.py` | Calls Jina embedding API with async HTTP client, in-memory cache, cooldown/rate-limit handling, and fallback zero vectors. |

### Memory, journal, and prompt assembly

| File | Responsibility |
|---|---|
| `memory_logic.py` | Core memory engine. Reads profile/journals/memories/facts/summaries from Supabase, builds dynamic system prompt, saves turn memories, extracts/refreshes memory facts, refreshes summaries, supports related-memory lookup via `match_memories` RPC, and runs background backfill jobs. |

### Runtime cache and live socket tracking

| File | Responsibility |
|---|---|
| `cache_logic.py` | In-memory caches for profile/system prompt, in-flight task deduplication, active live socket registry, cache invalidation, and prompt-history append helper. |

### API route modules

| File | Responsibility |
|---|---|
| `routes_chat.py` | Chat endpoints: cache warm-up (`/v1/chat/prepare`) and live WebSocket (`/v1/chat/live`). Handles Gemini session lifecycle, client message forwarding, transcript/audio streaming, low-latency RAG hint injection, memory writes, and periodic refresh triggers. |
| `routes_memory.py` | Memory/admin endpoints: start/check memory-index backfill jobs (admin key required) and `check-comfort` endpoint based on latest diary emotion. |
| `routes_persona.py` | Persona analysis endpoint using user Q&A input and Groq; returns sanitized structured persona output with fallback when Groq is unavailable. |

## Supabase dependencies

### Tables expected
- `profiles`
- `personas`
- `memories`
- `memory_facts`
- `memory_summaries`
- `daily_logs`

### RPC expected
- `match_memories` (used for semantic memory retrieval)

## Notes for Hugging Face Spaces

- `https://huggingface.co/spaces/samlam123/Ai_companion/tree/main`
- This repo is configured for Docker Spaces.
- `Dockerfile` runs `uvicorn main:app --host 0.0.0.0 --port 7860`.
- Add all environment variables in Space Settings.
- Reference: https://huggingface.co/docs/hub/spaces-config-reference
