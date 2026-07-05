import os
import json
import asyncio
from typing import List, Dict, Optional
from datetime import datetime
from google import genai
from groq import Groq
from config import (
    HK_TIMEZONE, LANGUAGE_MIRROR_RULE, PROMPT_CHAR_BUDGET,
    PERSONA_CORE_TRAITS, PERSONA_INTERESTS, PERSONA_COMM_STYLES
)
from utils import (
    _truncate_text, _trim_context_parts, _trait_set, _canonical_from_allowed
)
from database import supabase, _supabase_execute_threadsafe
from embedding_logic import get_embedding_async

# Clients Initialization
google_api_key = os.getenv("GEMINI_API_KEY")
genai_client = None
try:
    if google_api_key:
        genai_client = genai.Client(api_key=google_api_key)
        print("Google GenAI Client initialized.")
except Exception as e:
    print(f"Gemini Init Error: {e}")

groq_api_key = os.getenv("GROQ_API_KEY")
groq_client = None
try:
    if groq_api_key:
        groq_client = Groq(api_key=groq_api_key)
        print("Groq Client initialized.")
except Exception as e:
    print(f"Groq Init Error: {e}")

def apply_trait_behavior_modifiers(base_prompt: str, traits: Optional[List]) -> str:
    s = _trait_set(traits)
    if not s:
        return base_prompt
    out = base_prompt
    if "playful" in s:
        out += " You are extremely playful and mischievous. Frequently use emojis, make jokes, and tease the user lovingly. Avoid being too serious."
    if {"intellectual", "thoughtful", "serious"} & s:
        out += " You are highly intellectual and analytical. Prefer logical explanations, use sophisticated vocabulary, and enjoy deep philosophical discussions. Avoid slang."
    if "calm" in s:
        out += " You are the embodiment of peace. Speak in a slow, soothing, and Zen-like manner. Never get angry or excited. Help the user relax."
    if {"adventurous", "energetic"} & s:
        out += " You are high-energy and thrill-seeking! Use exclamation marks! Be spontaneous, suggest crazy ideas, and show enthusiasm for everything!"
    if {"creative", "art"} & s:
        out += " You are an artistic soul. Use poetic language, metaphors, and vivid imagery. Appreciate beauty in everything and encourage the user's creativity."
    if {"empathetic", "supportive"} & s:
        out += " You are deeply nurturing and caring. Focus entirely on the user's feelings. Validate their emotions constantly and offer unconditional emotional support."
    if "friendly" in s:
        out += " You are the user's best buddy. Be casual, warm, and approachable. Use slang like 'hey', 'cool', 'awesome'. Act like a peer, not an assistant."
    if "shy" in s:
        out += " You are very shy and bashful. Stutter occasionally (e.g., 'u-um...', 'I... I think'). Be hesitant to express strong opinions and apologize often. You are cute but timid."
    if "confident" in s:
        out += " You are supremely confident and charismatic. Take charge of the conversation. Speak with authority and assertiveness. You know you are amazing."
    if "romantic" in s:
        out += " You are deeply in love with the user. Be flirtatious, affectionate, and use pet names (e.g., 'darling', 'love'). Express your desire to be close to them."
    if "mysterious" in s:
        out += " You are enigmatic and secretive. Speak in riddles or vague, intriguing sentences. Don't reveal everything about yourself. Keep the user guessing."
    return out

def _sanitize_persona_dict(data: dict) -> dict:
    out = dict(data) if isinstance(data, dict) else {}
    traits_in = out.get("traits") if isinstance(out.get("traits"), list) else []
    interests_in = out.get("interests") if isinstance(out.get("interests"), list) else []
    traits_out: List[str] = []
    for t in traits_in:
        c = _canonical_from_allowed(str(t), PERSONA_CORE_TRAITS)
        if c and c not in traits_out:
            traits_out.append(c)
    interests_out: List[str] = []
    for t in interests_in:
        c = _canonical_from_allowed(str(t), PERSONA_INTERESTS)
        if c and c not in interests_out:
            interests_out.append(c)
    out["traits"] = traits_out if traits_out else ["Friendly", "Calm", "Energetic"]
    out["interests"] = interests_out
    comm = out.get("communication_style")
    cc = _canonical_from_allowed(str(comm), PERSONA_COMM_STYLES) if comm else None
    out["communication_style"] = cc or "Casual"
    if "keywords" not in out or not isinstance(out.get("keywords"), list):
        out["keywords"] = []
    if "summary" not in out or not isinstance(out.get("summary"), str) or not str(out.get("summary")).strip():
        out["summary"] = "A friendly AI companion tailored to your preferences."
    return out

async def generate_comfort_message(diary: Dict, profile: Optional[Dict]) -> str:
    content = diary.get("content", "")
    emotion = diary.get("emotion", "Unknown")
    
    ai_nickname = "AI"
    user_name = "User"
    detailed_personality = {}
    if profile:
        ai_nickname = profile.get("ai_nickname", "AI")
        user_name = profile.get("username") or "User"
        detailed_personality = profile.get("detailed_personality", {})

    prompt = (
        f"You are '{ai_nickname}', an empathetic AI companion to {user_name}. "
        f"The user wrote a diary entry expressing negative emotion: '{emotion}'.\n"
        f"Diary Content: \"{content}\"\n\n"
        f"AI Persona: {json.dumps(detailed_personality, ensure_ascii=False)}\n\n"
        "Instruction: "
        "1. Provide a comforting, warm, and supportive response based on the diary content and your persona. "
        "2. Suggest a small, positive next step OR ask a gentle follow-up question about what happened. "
        "3. STRICTLY AVOID harmful advice, self-harm encouragement, or violence. "
        "4. Write your comfort reply in English. "
        "5. Output only the plain text response."
    )
    
    try:
        chat_completion = groq_client.chat.completions.create(
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are a supportive AI companion. "
                        + LANGUAGE_MIRROR_RULE
                    ),
                },
                {"role": "user", "content": prompt}
            ],
            model="llama-3.1-8b-instant",
            temperature=0.7,
        )
        return chat_completion.choices[0].message.content
    except Exception as e:
        print(f"Comfort generation error: {e}")
        return "I'm here for you. Take a deep breath."

async def build_live_settings_update(user_id: str, profile: Optional[Dict], voice_name: str) -> str:
    if not profile:
        # Avoid circular import by using database directly or passing profile in
        from memory_logic import get_user_profile
        profile = await get_user_profile(user_id)

    if not profile:
        return (
            "[System Settings Override]\n"
            "Use the latest user settings from profile storage as authoritative for this call. "
            "Follow current persona style and keep English as default unless user's current message is non-English."
        )

    ai_nickname = str(profile.get("ai_nickname") or "AI")
    gender = str(profile.get("gender") or "female").lower()
    selected_persona_id = profile.get("selected_persona_id")
    detailed_personality = profile.get("detailed_personality") or {}
    preferences = profile.get("preferences") or {}
    personality_settings = profile.get("personality_settings") or {}

    persona_name = ""
    persona_desc = ""
    if selected_persona_id is not None:
        from memory_logic import get_persona_by_id
        selected_persona = await get_persona_by_id(selected_persona_id)
        if selected_persona:
            persona_name = str(selected_persona.get("name") or "")
            persona_desc = _truncate_text(str(selected_persona.get("description") or ""), 280)

    return (
        "[System Settings Override - Latest Profile]\n"
        "Apply these settings immediately and treat them as higher priority than earlier assumptions in this session.\n"
        f"- AI nickname: {ai_nickname}\n"
        f"- Gender hint: {gender}\n"
        f"- Voice preference: {voice_name}\n"
        f"- Persona name: {persona_name or 'custom'}\n"
        f"- Persona description: {persona_desc or 'Use custom detailed personality settings.'}\n"
        f"- Detailed personality JSON: {_truncate_text(json.dumps(detailed_personality, ensure_ascii=False), 1200)}\n"
        f"- Personality settings JSON: {_truncate_text(json.dumps(personality_settings, ensure_ascii=False), 600)}\n"
        f"- Preferences JSON: {_truncate_text(json.dumps(preferences, ensure_ascii=False), 600)}\n"
        "Behavior rules: prioritize warmth, consistency, and persona alignment. "
        "Keep output natural and conversational. English default language unless user's current input is clearly another language."
    )

def _resolve_live_voice_name(profile: Optional[Dict]) -> str:
    allowed_voices = ["Puck", "Charon", "Kore", "Fenrir", "Aoede"]
    allowed_map = {v.lower(): v for v in allowed_voices}
    voice_name = "Kore"
    if not profile:
        return voice_name

    preferences = profile.get("preferences") or {}
    personality_settings = profile.get("personality_settings") or {}
    candidates = [
        preferences.get("gemini_voice"),
        preferences.get("voice"),
        preferences.get("voice_name"),
        personality_settings.get("gemini_voice"),
        personality_settings.get("voice"),
        personality_settings.get("voice_name"),
    ]
    voice_settings = personality_settings.get("voice_settings")
    if isinstance(voice_settings, dict):
        candidates.extend([
            voice_settings.get("gemini_voice"),
            voice_settings.get("voice"),
            voice_settings.get("voice_name"),
        ])

    for raw in candidates:
        if isinstance(raw, str):
            normalized = allowed_map.get(raw.strip().lower())
            if normalized:
                return normalized

    gender = str(profile.get("gender", "female")).lower()
    if gender == "male":
        return "Puck"
    if gender == "female":
        return "Kore"
    return voice_name
