---
title: AI Companion Backend
sdk: docker
---

# AI Companion Backend（FastAPI）

[English](README.md) | [中文版](README_zh.md)

這個 backend 為 AR AI companion app 提供服務，從 Supabase 讀取用戶 profile 及 memory，建立 dynamic system prompt，透過 Gemini Live 提供即時語音聊天，並提供 memory 及 persona API。

## 服務功能

- 從 profile、journal、memory facts、summaries 及最近對話建立 context-rich prompt。
- 透過 WebSocket 提供低延遲即時語音及文字聊天。
- 儲存每次對話，並定期更新長期 facts 及 summaries。
- 使用 Groq 進行 persona analysis、fact extraction、summary 及 comfort message generation。
- 提供 admin-protected memory index backfill endpoints。

## 快速開始

```powershell
cd "AI companion Backend hugging face space"
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

健康檢查：`GET /health`

## 環境變數

| 變數 | 必需 | 用途 |
|---|---|---|
| `GEMINI_API_KEY` | 是（live chat） | Gemini Live 即時語音及文字。 |
| `SUPABASE_URL` | 是（data features） | Supabase project URL。 |
| `SUPABASE_KEY` | 是（data features） | Supabase database access key。 |
| `JINA_API_KEY` | 否（建議） | Semantic memory embeddings。 |
| `GROQ_API_KEY` | 否 | Persona、facts、summaries 及 comfort message。 |
| `MEMORY_ADMIN_KEY` | 否 | 保護 memory backfill admin endpoints。 |

## API

### Core

- `GET /health`
- `GET /v1/chat/prepare?user_id=...&force_refresh=false`
- `WS /v1/chat/live?user_id=...`

Live WebSocket 接受 PCM audio、文字、system update 及 JPEG image，並返回 audio bytes、transcript、user transcript 及文字訊息。

### Memory / Admin

- `POST /v1/memory/index/backfill`
- `GET /v1/memory/index/backfill/status`
- `GET /v1/check-comfort?user_id=...`

### Persona

- `POST /v1/persona/analyze`

目前 backend 不提供 `/v1/chat/voice` 或 `/v1/chat/gemini_live_once`；這兩個是舊有 client helper，並不是目前支援的 API。

## Memory system

Backend 會組合以下 6 個 contextual memory sources：

1. Profile 及 Persona
2. Recent conversation
3. Semantic memories（RAG）
4. Daily journals
5. Recent 7-day / 30-day summaries
6. Stable facts

`cache_logic.py` 另外提供 runtime cache，用來暫存 profile 及 system prompt，改善回應速度；它不計入上述 6 個 memory sources。

## 主要檔案

| 檔案 | 用途 |
|---|---|
| `main.py` | 建立 FastAPI app 及註冊 routers。 |
| `routes_chat.py` | Chat prepare、live WebSocket、transcript、audio 及 RAG hints。 |
| `routes_memory.py` | Memory backfill 及 comfort-check endpoints。 |
| `routes_persona.py` | Persona analysis endpoint。 |
| `memory_logic.py` | Memory retrieval、prompt assembly、facts 及 summaries。 |
| `ai_logic.py` | Gemini、Groq、persona 及 comfort logic。 |
| `embedding_logic.py` | Jina embedding integration。 |
| `cache_logic.py` | Profile、prompt cache 及 in-flight request deduplication。 |
| `database.py` | Supabase access、locking 及 transient retry。 |
| `config.py` | Timezone、memory constants、prompt budgets 及 table names。 |

## Supabase 依賴

### Tables

- `profiles`
- `personas`
- `memories`
- `memory_facts`
- `memory_summaries`
- `daily_logs`

### RPC

- `match_memories`：按 semantic similarity 搜尋用戶相關的 conversation memories。

正式部署到 Hugging Face Spaces 時，請在 Space settings 設定環境變數，並使用 Supabase Row Level Security 隔離不同用戶的 profile、journal 及 memory records。
