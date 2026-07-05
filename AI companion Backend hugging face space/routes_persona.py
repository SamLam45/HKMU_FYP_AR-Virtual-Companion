import json
from fastapi import APIRouter, HTTPException
from models import AnalysisRequest
from ai_logic import groq_client, _sanitize_persona_dict

router = APIRouter()

@router.post("/v1/persona/analyze")
async def analyze_persona(request: AnalysisRequest):
    if not groq_client:
        # Fallback to default/mock profile if Groq is not available
        print("Groq client not initialized. Using fallback profile.")
        return {
            "status": "success",
            "data": _sanitize_persona_dict({
                "summary": "A friendly and supportive AI companion tailored to your needs.",
                "traits": ["Friendly", "Calm", "Energetic"],
                "communication_style": "Supportive",
                "keywords": ["friendship", "chat"],
                "interests": [],
            }),
        }

    try:
        # Construct the prompt for analysis
        qa_text = "\n".join([f"Q: {item['question']}\nA: {item['answer']}" for item in request.qa_list])
        
        analysis_prompt = (
            "You are an expert psychological profiler and AI companion creator. "
            "Analyze the following user responses to create a detailed persona profile for their ideal AI companion.\n\n"
            f"User Responses:\n{qa_text}\n\n"
            "Based on these answers, generate a JSON profile with the following fields:\n"
            "Write the 'summary' field in clear English. "
            "Keep 'traits', 'interests', and 'communication_style' values exactly as the allowed English lists require.\n"
            "1. 'summary': A 2-3 sentence description of the AI's personality and how it complements the user.\n"
            "2. 'traits': A list of 3-5 personality traits chosen STRICTLY from this list: "
            "['Friendly', 'Shy', 'Confident', 'Playful', 'Serious', 'Romantic', 'Adventurous', 'Calm', 'Energetic', 'Mysterious']. "
            "Select the ones that best match the user's vibe.\n"
            "3. 'communication_style': You MUST choose EXACTLY ONE from this list: ['Casual', 'Formal', 'Flirty', 'Supportive', 'Teasing', 'Encouraging'].\n"
            "4. 'keywords': A list of keywords representing the user's interests and values.\n"
            "5. 'interests': A list of interests chosen from this list based on the user's answers: "
            "['Music', 'Art', 'Technology', 'Nature', 'Sports', 'Reading', 'Gaming', 'Cooking', 'Travel', 'Fashion']. "
            "Include all that apply.\n"
            "Output ONLY the JSON object."
        )

        chat_completion = groq_client.chat.completions.create(
            messages=[
                {"role": "system", "content": "You are a helpful assistant that outputs JSON only."},
                {"role": "user", "content": analysis_prompt}
            ],
            model="llama-3.1-8b-instant",
            response_format={"type": "json_object"},
            temperature=0.7,
        )
        ai_response_json = chat_completion.choices[0].message.content
        try:
            profile_data = json.loads(ai_response_json)
        except Exception:
            # Fallback if JSON parsing fails
            profile_data = {
                "summary": "A friendly and supportive AI companion tailored to your needs.",
                "traits": ["Friendly", "Calm", "Energetic"],
                "communication_style": "Supportive",
                "keywords": ["friendship", "chat"],
                "interests": [],
            }
        profile_data = _sanitize_persona_dict(profile_data)
        return {
            "status": "success",
            "data": profile_data
        }
    except Exception as e:
        print(f"Analysis Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
