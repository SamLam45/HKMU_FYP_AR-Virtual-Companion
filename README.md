# AR Virtual Companion (FYP)

[![English](https://img.shields.io/badge/README-English-2563EB?style=for-the-badge)](README.md)
[![中文](https://img.shields.io/badge/README-%E4%B8%AD%E6%96%87-DC2626?style=for-the-badge)](README_zh.md)

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![Gemini](https://img.shields.io/badge/Gemini-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white)
![Groq](https://img.shields.io/badge/Groq-F55036?style=for-the-badge&logo=groq&logoColor=white)
![Jina AI](https://img.shields.io/badge/Jina_AI-009191?style=for-the-badge&logo=jina&logoColor=white)

A comprehensive mobile AI companion application featuring AR character interaction, real-time voice chat, persona onboarding, diary/journal tracking, and a memory-aware AI backend generation system. 

This project was developed as a Final Year Project (FYP) for COMP S456F.

---

<a id="english"></a>

## English

### Technical Highlights

- Real-time bidirectional audio streaming over WebSocket with Gemini Live.
- Low-latency RAG memory prefetch while partial speech transcription is received.
- Multi-source memory orchestration for dynamic system prompt construction.
- Background extraction of stable facts and rolling 7-day / 30-day summaries.
- Thread-safe Supabase access with transient connection retry handling.
- Runtime caching with in-flight request deduplication and cache invalidation.
- AR avatar placement, animation, object detection, and Supabase Storage loading.

## 🎥 Video Demo

[![Watch the video](https://img.youtube.com/vi/SFbLtfeLPjA/maxresdefault.jpg)](https://youtu.be/SFbLtfeLPjA)

[Watch on YouTube](https://youtu.be/SFbLtfeLPjA)

---

## 📸 App Screenshots

Here is a glimpse of the AR Virtual Companion's user interface and core features:

### 1. Onboarding & Personalization
<div align="center">
  <img src="assets/screenshots/FYPapp1.jpg" width="220" alt="Login Screen" />
  <img src="assets/screenshots/FYPapp2.jpg" width="220" alt="Profile Setup" />
  <img src="assets/screenshots/FYPapp10.jpg" width="220" alt="Persona Quiz" />
</div>
<div align="center">
  <img src="assets/screenshots/FYPapp12.jpg" width="220" alt="Select Female Avatar" />
  <img src="assets/screenshots/FYPapp13.jpg" width="220" alt="Select Male Avatar" />
  <img src="assets/screenshots/FYPapp20.jpg" width="220" alt="Personalization AI" />
</div>

### 2. Dashboard & User Profile
<div align="center">
  <img src="assets/screenshots/FYPapp3.jpg" width="220" alt="Home Screen" />
  <img src="assets/screenshots/FYPapp24.jpg" width="220" alt="User Profile" />
  <img src="assets/screenshots/FYPapp23.jpg" width="220" alt="Memory Page" />
</div>

### 3. AR Interaction
<div align="center">
  <img src="assets/screenshots/FYPapp5.jpg" width="220" alt="AR Screen" />
  <img src="assets/screenshots/FYPapp14.jpg" width="220" alt="AR Actions" />
  <img src="assets/screenshots/FYPapp16.jpg" width="220" alt="AR Settings" />
</div>

### 4. Journal & Insights
<div align="center">
  <img src="assets/screenshots/FYPapp8.jpg" width="220" alt="Insights" />
  <img src="assets/screenshots/FYPapp18.jpg" width="220" alt="write Journal" />
  <img src="assets/screenshots/FYPapp7.jpg" width="220" alt="Calendar Journal" />
</div>

---

## 🚀 Live Demo & Hosting

- **Backend API (Hosted on Hugging Face)**: [Hugging Face Space Repository](https://huggingface.co/spaces/samlam123/Ai_companion/tree/main)
- **Database & Auth**: Supabase

---

## 🏗️ System Architecture

This repository is structured as a **Monorepo** containing both the Flutter frontend application and the FastAPI Python backend.

```text
.
├── ar_virtual_companion/       # Mobile App (Flutter)
│   ├── lib/                    # Frontend source code
│   ├── assets/                 # App icons, local placeholder images
│   └── pubspec.yaml
└── AI companion Backend hugging face space/ # Backend API (FastAPI)
    ├── main.py                 # API entry point
    ├── routes_*.py             # Chat, Memory, and Persona routers
    ├── memory_logic.py         # Memory retrieval and prompt assembly
    ├── ai_logic.py             # Gemini, Groq, persona, and comfort logic
    ├── embedding_logic.py      # Jina embedding integration
    ├── cache_logic.py          # Runtime prompt/profile cache
    ├── database.py             # Supabase access and retries
    ├── config.py               # Runtime configuration and memory constants
    ├── Dockerfile              # Hugging Face deployment
    └── requirements.txt        # Python dependencies
```

### High-Level Data Flow
1. **App Initialization**: The Flutter app authenticates users via Supabase Auth and loads user profiles/3D avatars.
2. **Real-time Interaction**: The app establishes a WebSocket connection (`routes_chat.py`) to the FastAPI backend.
3. **AI Processing**: The backend forwards audio/text to **Gemini Live**, injecting dynamic system prompts based on the user's selected persona and recent memories.
4. **Memory Management**: Chat history and daily journal entries are processed by **Groq** to extract stable facts and semantic summaries, embedded using **Jina API**, and stored in Supabase for long-term recall.

### System Architecture Diagram

```mermaid
flowchart LR
    USER((User)) --> APP

    subgraph CLIENT["Client Application"]
        APP["Flutter Mobile App<br/><br/>AR interaction · Voice chat<br/>Journal · Persona settings"]
    end

    subgraph PLATFORM["Application Platform"]
        API["FastAPI Backend<br/><br/>REST APIs · WebSocket<br/>Prompt orchestration · Cache"]
        MEMORY["Memory Orchestration<br/><br/>Context assembly · RAG retrieval<br/>Fact and summary refresh"]
    end

    subgraph INTELLIGENCE["AI Intelligence Layer"]
        LIVE["Gemini Live<br/>Real-time voice and text"]
        ANALYSIS["Groq<br/>Persona analysis<br/>Fact extraction and summaries"]
        EMBEDDING["Jina AI<br/>Semantic embeddings"]
    end

    subgraph PERSISTENCE["Data and Storage"]
        SUPABASE["Supabase<br/><br/>Auth · PostgreSQL · Storage"]
        TABLES[("Memory Data<br/>Conversations · Journals<br/>Stable facts · 7d/30d summaries")]
    end

    APP <-->|"WebSocket / REST"| API
    API --> MEMORY
    MEMORY --> LIVE
    MEMORY --> ANALYSIS
    MEMORY --> EMBEDDING
    MEMORY <-->|"Read / write context"| TABLES
    TABLES --> SUPABASE
    API <-->|"Profile · Auth · Assets"| SUPABASE
    LIVE --> API

    classDef user fill:#111827,stroke:#64748b,color:#ffffff,stroke-width:2px;
    classDef client fill:#2563eb,stroke:#1d4ed8,color:#ffffff,stroke-width:2px;
    classDef platform fill:#4f46e5,stroke:#3730a3,color:#ffffff,stroke-width:2px;
    classDef intelligence fill:#c2410c,stroke:#9a3412,color:#ffffff,stroke-width:2px;
    classDef persistence fill:#047857,stroke:#065f46,color:#ffffff,stroke-width:2px;
    class USER user;
    class APP client;
    class API,MEMORY platform;
    class LIVE,ANALYSIS,EMBEDDING intelligence;
    class SUPABASE,TABLES persistence;
    style CLIENT fill:#eff6ff,stroke:#2563eb,stroke-width:2px
    style PLATFORM fill:#eef2ff,stroke:#4f46e5,stroke-width:2px
    style INTELLIGENCE fill:#fff7ed,stroke:#c2410c,stroke-width:2px
    style PERSISTENCE fill:#ecfdf5,stroke:#047857,stroke-width:2px
```

### Memory Layers

The backend has **6 contextual memory layers**. Runtime cache is a performance layer and is **not** counted as a memory layer.

| Layer | Storage / source | Purpose |
|---|---|---|
| 1. Profile & Persona | `profiles`, `personas` | User identity, preferences, selected persona, personality and communication style. |
| 2. Recent Conversation | `memories` | Keeps the latest conversation turns for immediate continuity. |
| 3. Semantic Memories (RAG) | `memories` + Jina embeddings + `match_memories` | Retrieves older conversations related to the current topic. |
| 4. Daily Journal Context | `daily_logs` | Supplies recent emotions, journal content and diary-related context. |
| 5. Rolling Summaries | `memory_summaries` | Compact `recent_7d` and `recent_30d` conversation summaries. |
| 6. Stable Facts | `memory_facts` | Long-term facts extracted from repeated evidence, with confidence and evidence counts. |

Memory is assembled into the dynamic system prompt for each chat session. The backend also maintains a short-lived in-memory cache for profiles and prompts to reduce latency; cache invalidation is triggered when relevant user settings change.

---

## 📱 Frontend (Flutter Mobile App)

Located in `ar_virtual_companion/`.

### Key Features
- **AR Interaction**: Render 3D `.glb` avatars in augmented reality using a customized `ar_flutter_plugin_2`.
- **Local Model Caching**: 3D models fetched from Supabase Storage are cached locally (10-year TTL) to minimize network egress and ensure instant AR loading times. Includes dynamic GLB height metrics estimation.
- **Real-time Voice Chat**: Low-latency PCM streaming playback (via SoLoud) connected to the backend's WebSocket.
- **Onboarding & Customization**: 3-step setup (Profile -> Persona Quiz -> Avatar Selection).
- **Journal & Analytics**: Daily mood tracking, journal entries (saved to Supabase), and weekly/monthly mood insights.
- **State Management & Services**: Built with `Riverpod` and `Provider`. Includes push notifications (scheduled daily/birthday/care messages), object detection (ML Kit), data export, and local caching services.

### Setup & Run
```bash
cd ar_virtual_companion
flutter pub get
flutter run
```
*Note: An AR-capable physical Android/iOS device is recommended for the full AR experience.*

---

## ⚙️ Backend (Python FastAPI)

Located in `AI companion Backend hugging face space/`.

### Key Features
- **Real-time Streaming**: `WS /v1/chat/live` endpoint for low-latency voice and text streaming via Gemini Live. Includes concurrent audio/text processing and client transcript relay.
- **Dynamic Persona & RAG**: Automatically constructs context-rich prompts (`ai_logic.py`) based on user profiles, recent conversations, and embedded memory facts. Features low-latency RAG injection while the user is still speaking.
- **Memory Engine**: Periodically summarizes and indexes long-term facts using Groq (Llama 3.1) and Jina Embeddings (`memory_logic.py`, `embedding_logic.py`).
- **Comfort System**: Analyzes journal entries to generate empathetic, persona-aligned comfort messages.
- **Caching & Pre-fetching**: Implements `cache_logic.py` to pre-load system prompts and user profiles to reduce latency during active sessions. Contains Thread-safe Database operations.

### Environment Variables
| Variable | Required | Purpose |
|---|---|---|
| `GEMINI_API_KEY` | Yes | Real-time voice and chat generation (Gemini Live) |
| `SUPABASE_URL` | Yes | Database connection |
| `SUPABASE_KEY` | Yes | Database connection |
| `GROQ_API_KEY` | Optional | Persona analysis, memory summarization, comfort texts |
| `JINA_API_KEY` | Optional | Embeddings for semantic memory retrieval |
| `MEMORY_ADMIN_KEY` | Optional | Protects admin-only memory backfill endpoints |

### Local Setup & Run
```bash
cd "AI companion Backend hugging face space"
python -m venv .venv
# Activate venv (Windows: .venv\Scripts\activate | Mac/Linux: source .venv/bin/activate)
pip install -r requirements.txt

# Set your .env variables here

uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

For production deployment, set the backend environment variables in the Hugging Face Space settings. Supabase Row Level Security should be configured to isolate each user's profile, journal, and memory records.

---



## 🛠️ Tech Stack

**Frontend**: Flutter, Dart, Riverpod, `ar_flutter_plugin_2`
**Backend**: Python 3.11, FastAPI, Uvicorn, WebSockets
**AI / ML**: Google GenAI SDK (Gemini Live), Groq SDK (LLaMA 3), Jina Embeddings
**Database / Storage**: Supabase (PostgreSQL, Auth, Storage)

---

## 📝 License
Developed for Academic Purposes (FYP).
