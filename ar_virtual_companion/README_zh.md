# AR Virtual Companion（Flutter + FastAPI）

[English](README.md) | [中文版](README_zh.md)

COMP S456F Final Year Project。

這是一個結合 AR 角色互動、即時語音聊天、Persona onboarding、日記及 AI memory system 的手機應用程式。

## 已實作功能

### Frontend（Flutter）

- 使用 Supabase 進行 authentication 及 profile persistence。
- 三步 onboarding：
  1. 個人資料及 username validation
  2. Persona quiz 及 backend persona analysis
  3. 從 Supabase Storage 選擇 avatar model
- Main tabs：
  - `Calendar`：日記、當日 memories、生日及 meeting day markers
  - `Recap`：weekly/monthly insights chart
  - `Home`
  - `Customize`
  - `Profile`
- AR mode：
  - 使用本地 fork `ar_flutter_plugin_2` 放置及渲染角色
  - 透過 object detection 觸發角色行為及 model switching
  - Camera switching 及 AR session controls
- Voice/chat：
  - 透過 WebSocket 連接 backend live endpoint
  - 使用 SoLoud 播放低延遲 PCM audio
  - 支援 transcript、user transcript、mute 及 barge-in controls
- Journal：
  - Mood tagging
  - Optional image upload 到 Supabase Storage
  - 儲存及刪除後自動 refresh backend cache
- Push notifications：
  - Birthday、mood 及 daily care notifications

### Backend

- `routes_chat.py`
  - `GET /v1/chat/prepare`
  - `WS /v1/chat/live`
- `routes_memory.py`
  - Memory index backfill
  - Comfort-check
- `routes_persona.py`
  - Groq persona analysis，無 Groq 時提供 fallback profile
- Supabase-backed memory：
  - Conversation memory read/write
  - Embedding-based retrieval
  - `recent_7d` 及 `recent_30d` summaries
  - Stable fact extraction 及 refresh
- Dynamic prompt：
  - Profile 及 Persona-aware
  - Journal-aware
  - Summary 及 relevant memory injection
  - Language mirror rule

## 技術棧

- **Mobile**：Flutter、Dart、Riverpod、Provider
- **AR / Media**：`ar_flutter_plugin_2`、`camera`、ML Kit、`model_viewer_plus`、`flutter_soloud`、`record`、`just_audio`
- **Backend**：FastAPI、Uvicorn、Google GenAI SDK、Groq SDK、Supabase Python client
- **Data / Infra**：Supabase Auth、Postgres、Storage

## Repository 結構

```text
lib/
├── main.dart
├── models/
├── providers/
├── screens/
│   ├── onboarding/
│   ├── ar_screen_flutter.dart
│   ├── main_screen.dart
│   ├── calendar_screen.dart
│   ├── insights_screen.dart
│   └── user_profile_screen.dart
├── services/
│   ├── supabase_service.dart
│   ├── ai_partner_service.dart
│   ├── websocket_service.dart
│   ├── ar_character_state_manager.dart
│   ├── character_animation_manager.dart
│   └── push_notification_service.dart
└── widgets/

AI companion Backend hugging face space/
├── main.py
├── routes_chat.py
├── routes_memory.py
├── routes_persona.py
├── ai_logic.py
├── memory_logic.py
├── embedding_logic.py
├── cache_logic.py
├── database.py
├── config.py
├── models.py
└── requirements.txt
```

## 安裝及執行

### Flutter app

需要 Flutter SDK `^3.9.2`。完整 AR 功能建議使用支援 AR 的實體 Android 或 iOS device。

```powershell
flutter pub get
flutter run

# Production build example
flutter build apk --release
```

### Backend

```powershell
cd "..\AI companion Backend hugging face space"
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Backend environment variables：

- `SUPABASE_URL`
- `SUPABASE_KEY`
- `GEMINI_API_KEY`
- `GROQ_API_KEY`（optional）
- `JINA_API_KEY`（optional，semantic memory）
- `MEMORY_ADMIN_KEY`（memory backfill）

### Launcher icons

如果修改 `assets/app_icon.svg`，可以執行：

```powershell
cd tools/icon-gen
npm install
node generate-icons.mjs
```

## Backend URL

Frontend service 預設使用：

- `https://samlam123-ai-companion.hf.space`
- `https://huggingface.co/spaces/samlam123/Ai_companion/tree/main`

本地開發 backend 時，請檢查：

- `lib/services/ai_partner_service.dart`
- `lib/services/websocket_service.dart`

目前支援的 live chat API 是 `GET /v1/chat/prepare` 及 `WS /v1/chat/live`。`ai_partner_service.dart` 內的 one-shot voice helper 需要另外的 backend route，並不是目前 live-chat API 的一部分。

## Product flow

1. 開啟 app，splash 檢查登入及 onboarding 狀態。
2. 新用戶完成 register、profile、persona 及 avatar onboarding。
3. 用戶使用 journal、recap、AR interaction、customization 及 profile。
4. AR live chat 透過 WebSocket 串流 voice、audio 及 transcript。
5. 新 journal 會觸發 backend refresh 及後續 comfort logic。

## 注意事項

- Auth、database 及 file storage 只使用 Supabase。
- AR tracking 及 performance 會因 device 能力而不同。
- Voice quality 及 latency 受 network、backend cold start 及 Gemini service 影響。
- Persona 及 memory 功能受 backend API keys 及 Supabase data configuration 影響。

## License

Academic use（FYP）project。
