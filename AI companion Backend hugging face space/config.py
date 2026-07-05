import os
from datetime import timezone, timedelta

# Define Hong Kong Timezone
HK_TIMEZONE = timezone(timedelta(hours=8))

# Language Rules
LANGUAGE_MIRROR_RULE = (
    "**Language:** Use **English** as the default for all user-visible text (including JSON key 'reply' and voice-style wording). "
    "Only switch to another language if the user's CURRENT message (or their last clear turn in 【Recent Conversation History】) "
    "is predominantly in that non-English language—then reply in that language for that turn. "
    "If input is mixed or ambiguous, use English. "
    "Structured schema values (e.g. emotion enums) stay in English when required."
)

# AI & Memory Budgets
PROMPT_CHAR_BUDGET = 500000 
MEMORY_SUMMARY_PERIOD_DAYS = {"recent_7d": 7, "recent_30d": 30}
SUMMARY_REFRESH_COOLDOWN_SECONDS = 15 * 60
SUMMARY_REFRESH_EVERY_TURNS = 10
MEMORY_INDEX_REFRESH_COOLDOWN_SECONDS = 20 * 60
MEMORY_INDEX_REFRESH_EVERY_TURNS = 12

# Database Tables
MEMORY_FACTS_TABLE = "memory_facts"
MEMORIES_TABLE = "memories"
PROFILES_TABLE = "profiles"
PERSONAS_TABLE = "personas"
DAILY_LOGS_TABLE = "daily_logs"
MEMORY_SUMMARIES_TABLE = "memory_summaries"

# Embedding Constants
JINA_EMBED_CACHE_TTL_SECONDS = 120.0
JINA_MIN_REQUEST_INTERVAL_SECONDS = 0.12

# Persona Traits (Must match Flutter PersonalityTrait lists)
PERSONA_CORE_TRAITS = [
    "Friendly", "Shy", "Confident", "Playful", "Serious", "Romantic",
    "Adventurous", "Calm", "Energetic", "Mysterious",
]
PERSONA_INTERESTS = [
    "Music", "Art", "Technology", "Nature", "Sports", "Reading",
    "Gaming", "Cooking", "Travel", "Fashion",
]
PERSONA_COMM_STYLES = [
    "Casual", "Formal", "Flirty", "Supportive", "Teasing", "Encouraging",
]

# Cache TTL
CACHE_TTL = 300

# Fallback Prompts
DEFAULT_LIVE_SYSTEM_PROMPT = (
    "You are a warm, emotionally supportive AI companion.\n"
    + LANGUAGE_MIRROR_RULE
    + " Keep responses natural, safe, and concise."
)

# Admin Configuration
def get_admin_key():
    return os.getenv("MEMORY_ADMIN_KEY")
