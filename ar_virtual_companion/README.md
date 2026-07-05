# AR Virtual Companion (Flutter + FastAPI)

FYP for COMP S456F.

A mobile AI companion app with AR character interaction, realtime voice chat, persona onboarding, diary/journal tracking, and memory-aware backend generation.

## What Is Implemented

### Frontend (Flutter)
- Authentication and profile persistence with Supabase.
- 3-step onboarding flow:
  1) profile info and username validation  
  2) persona quiz + backend persona analysis  
  3) avatar model selection from Supabase Storage assets.
- Main app tabs:
  - `Calendar` (journal + day memories + birthday/meeting day markers),
  - `Recap` (weekly/monthly insights chart),
  - `Home`,
  - `Customize`,
  - `Profile`.
- AR mode with:
  - AR character placement/rendering (`ar_flutter_plugin_2` fork),
  - object-detection-driven behavior/model switching,
  - camera switching and AR session controls.
- Voice/chat experience:
  - realtime websocket chat to backend live endpoint,
  - low-latency PCM streaming playback (SoLoud),
  - transcript and user-transcript handling,
  - microphone mute/barge-in related controls.
- Journal workflow:
  - mood tagging,
  - optional image upload to Supabase Storage,
  - auto-refresh backend cache after save/delete.
- Push notifications:
  - birthday scheduling and mood-based notification triggers.

### Backend (`AI companion Backend huggingface`)
- FastAPI app with routers:
  - `routes_chat.py`:
    - `GET /v1/chat/prepare` (cache warmup),
    - `WS /v1/chat/live` (Gemini live audio session + transcript/audio relay).
  - `routes_memory.py`:
    - memory index backfill admin endpoints,
    - comfort-check endpoint from latest diary emotion.
  - `routes_persona.py`:
    - persona analysis endpoint using Groq (with fallback profile).
- Supabase-backed memory system:
  - conversation memory write/read,
  - embedding-based memory retrieval,
  - memory summaries (`recent_7d`, `recent_30d`),
  - stable fact index extraction and refresh.
- Dynamic prompt construction:
  - profile/persona-aware,
  - journal-aware,
  - memory summary + relevant memory injection,
  - language mirror rule (English default unless user turn is non-English dominant).

## Tech Stack

- **Mobile**: Flutter, Dart, Riverpod, Provider.
- **AR/Media**: `ar_flutter_plugin_2` (local fork), `camera`, `google_mlkit_object_detection`, `model_viewer_plus`, `flutter_soloud`, `record`, `just_audio`.
- **Backend**: FastAPI, Uvicorn, Google GenAI SDK, Groq SDK, Supabase Python client.
- **Data/Infra**: Supabase Auth, Postgres tables (`profiles`, `memories`, `daily_logs`, `personas`, `memory_facts`, `memory_summaries`), Supabase Storage.

## Repository Structure

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

AI companion Backend huggingface/
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

## Setup

## 1) Flutter App

### Prerequisites
- Flutter SDK `^3.9.2`
- Android device/emulator (AR-capable device required for full AR features)

### Install
```bash
flutter pub get
```

### Run
```bash
flutter run/flutter --release
```

### Optional: regenerate launcher icons
If you edit `assets/app_icon.svg`, install Node dependencies and run the script:

```bash
cd tools/icon-gen
npm install
node generate-icons.mjs
```

(`node_modules` under `tools/icon-gen` is not committed—see `.gitignore`.)

## 2) Python Backend (FastAPI)

### Create environment and install
```bash
cd "AI companion Backend huggingface"
python -m venv .venv
# Windows PowerShell
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### Required environment variables
Set these before running backend:
- `SUPABASE_URL`
- `SUPABASE_KEY`
- `GEMINI_API_KEY`
- `GROQ_API_KEY` (optional but recommended)
- `MEMORY_ADMIN_KEY` (required only for backfill admin endpoints)

### Start server
```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Health check
```bash
GET /health
```

## Notes on Deployment URLs

Current frontend service layer points to hosted backend URLs under:
- `https://samlam123-ai-companion.hf.space`
- `https://huggingface.co/spaces/samlam123/Ai_companion/tree/main`

If you run backend locally, update the relevant base URL usage in:
- `lib/services/ai_partner_service.dart`
- `lib/services/websocket_service.dart`

## Current Product Flow

1. Open app -> splash checks auth + onboarding completion.
2. New user -> login/register -> onboarding (profile/persona/avatar).
3. Main tabs for daily journaling, recap analytics, AR interaction, customization, and profile.
4. AR live chat can stream voice and receive AI audio/transcripts in realtime.
5. New journal entries can trigger backend refresh and downstream comfort logic.

## Known Considerations

- Auth, database, and file storage use **Supabase** only.
- AR performance and tracking quality vary by device capability.
- Realtime voice quality/latency depends on network and backend cold-start state.
- Persona/traits behavior depends on backend model availability and API keys.

## License

Academic use (FYP) project.
