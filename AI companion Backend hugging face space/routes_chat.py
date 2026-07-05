import os
import json
import asyncio
import time
import base64
import traceback
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from config import DEFAULT_LIVE_SYSTEM_PROMPT
from ai_logic import (
    genai_client, _resolve_live_voice_name, build_live_settings_update
)
from cache_logic import (
    get_cached_user_profile, get_cached_system_prompt, 
    invalidate_user_runtime_cache, close_active_live_sessions,
    append_to_cached_system_prompt, ACTIVE_LIVE_SOCKETS
)
from memory_logic import (
    get_memory_summaries, get_user_profile, get_related_memories,
    get_memory_facts, save_memory, refresh_memory_summaries,
    refresh_memory_index, should_refresh_memory_summaries,
    should_refresh_memory_index, _should_prefetch_rag_on_probe,
    _build_dynamic_rag_lines, _extract_targeted_fact_lines
)

router = APIRouter()

@router.get("/v1/chat/prepare")
async def prepare_chat(user_id: str, force_refresh: bool = False):
    try:
        if force_refresh:
            invalidate_user_runtime_cache(user_id)
            closed_count = await close_active_live_sessions(user_id, reason="settings_force_refresh")
            if closed_count > 0:
                print(f"Force refresh closed {closed_count} active live session(s) for {user_id}")
        profile_task = asyncio.create_task(get_cached_user_profile(user_id))
        system_prompt_task = asyncio.create_task(
            get_cached_system_prompt(user_id, is_live_mode=True)
        )
        summaries_task = asyncio.create_task(get_memory_summaries(user_id))
        await asyncio.wait_for(
            asyncio.shield(asyncio.gather(profile_task, system_prompt_task, summaries_task, return_exceptions=True)),
            timeout=5.0,
        )
        return {"status": "ok", "message": "Cache warmed"}
    except asyncio.TimeoutError:
        return {"status": "ok", "message": "Cache warming in progress"}
    except Exception as e:
        print(f"Error preparing chat for {user_id}: {e}")
        return {"status": "error", "message": str(e)}

@router.websocket("/v1/chat/live")
async def chat_live(websocket: WebSocket, user_id: str):
    await websocket.accept()
    print(f"WebSocket connected for user: {user_id}")
    ACTIVE_LIVE_SOCKETS.setdefault(user_id, set()).add(websocket)
    # Using pre-warmed cache if available to reduce latency
    if not os.getenv("GEMINI_API_KEY"):
        print("Error: GEMINI_API_KEY not found")
        await websocket.close(code=1008, reason="Google GenAI not configured")
        return

    client = genai_client
    if not client:
        try:
            from google import genai
            client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
        except Exception as e:
            print(f"Failed to initialize Gemini Client: {e}")
            await websocket.close(code=1011, reason="Internal Server Error")
            return

    try:
        system_prompt_task = asyncio.create_task(
            get_cached_system_prompt(user_id, is_live_mode=True)
        )
        profile_task = asyncio.create_task(get_cached_user_profile(user_id))

        try:
            system_instruction = await asyncio.wait_for(
                asyncio.shield(system_prompt_task), timeout=5.0
            )
        except asyncio.TimeoutError:
            system_instruction = DEFAULT_LIVE_SYSTEM_PROMPT
            print(f"System prompt warmup timeout for {user_id}, using fallback")

        print(f"Loaded dynamic system prompt for {user_id}")
        
        voice_name = "Kore"
        profile = None
        try:
            try:
                profile = await asyncio.wait_for(
                    asyncio.shield(profile_task), timeout=3.0
                )
            except asyncio.TimeoutError:
                profile = None

            if not profile:
                profile = await get_user_profile(user_id)
            voice_name = _resolve_live_voice_name(profile)
            selected_persona_id = profile.get("selected_persona_id") if isinstance(profile, dict) else None
            print(
                f"Live settings resolved for {user_id}: "
                f"voice={voice_name}, selected_persona_id={selected_persona_id}"
            )
        except Exception as e:
            print(f"Error fetching voice preference: {e}")

        model = "gemini-2.5-flash-native-audio-preview-12-2025" 
        config = {
            "response_modalities": ["AUDIO"],
            "system_instruction": system_instruction,
            "speech_config": {
                "voice_config": {
                    "prebuilt_voice_config": {
                        "voice_name": voice_name 
                    }
                }
            },
            "thinking_config": {
                "include_thoughts": False 
            },
            "output_audio_transcription": {},
            "input_audio_transcription": {}
        }

        async with client.aio.live.connect(model=model, config=config) as session:
            print(f"Gemini Live Session started for {user_id}")
            try:
                initial_settings_update = await build_live_settings_update(user_id, profile, voice_name)
                await session.send(input=initial_settings_update, end_of_turn=False)
                print(f"Pushed initial system_update for {user_id}")
            except Exception as e:
                print(f"Failed to push initial settings update for {user_id}: {e}")
            
            ai_text_buffer = []
            user_text_buffer =[]
            
            # 低延遲 RAG：在使用者說話途中就預取記憶，不等完整停頓。
            rag_prefetch_timer = None
            last_rag_probe_text = ""
            last_rag_injected_at = 0.0

            async def receive_from_client():
                try:
                    while True:
                        message = await websocket.receive()
                        
                        if "bytes" in message:
                            await session.send(
                                 input={"data": message["bytes"], "mime_type": "audio/pcm"},
                                 end_of_turn=False 
                             )
                        elif "text" in message:
                            try:
                                payload = json.loads(message["text"])
                                if payload.get("type") == "text_input":
                                    user_input_text = payload["text"]
                                    user_text_buffer.append(user_input_text)
                                    await session.send(input=user_input_text, end_of_turn=True)
                                    print(f"Sent text input to Gemini: {user_input_text}")
                                elif payload.get("type") == "system_update":
                                    system_update_text = payload["text"]
                                    # Send to Gemini but do NOT add to user_text_buffer to avoid saving in memory DB
                                    await session.send(input=system_update_text, end_of_turn=True)
                                    print(f"Sent system update to Gemini: {system_update_text}")
                                elif payload.get("type") == "image":
                                    image_b64 = payload.get("data")
                                    if image_b64:
                                        image_bytes = base64.b64decode(image_b64)
                                        await session.send(
                                            input={"data": image_bytes, "mime_type": "image/jpeg"},
                                            end_of_turn=False
                                        )
                                        print(f"Sent image to Gemini for {user_id}")
                            except json.JSONDecodeError:
                                pass
                            except Exception as e:
                                print(f"Error processing text message: {e}")

                except WebSocketDisconnect:
                    print(f"Client disconnected: {user_id}")
                except RuntimeError as e:
                    # Starlette may raise this after a disconnect frame has been received.
                    if "disconnect message has been received" in str(e).lower():
                        print(f"Client disconnected: {user_id}")
                    else:
                        print(f"Error receiving from client: {e}")
                except Exception as e:
                    print(f"Error receiving from client: {e}")

            async def receive_from_gemini():
                async def inject_live_memory_hints(user_probe_text: str):
                    nonlocal last_rag_probe_text, last_rag_injected_at
                    probe = " ".join((user_probe_text or "").split()).strip()
                    if not probe or probe == "[Voice Audio]":
                        return
                    if not _should_prefetch_rag_on_probe(probe):
                        return
                    now_ts = time.time()
                    grew_chars = len(probe) - len(last_rag_probe_text)
                    if probe == last_rag_probe_text:
                        return
                    # throttle: keep latency low while preventing spam injections.
                    if (now_ts - last_rag_injected_at) < 0.20 and grew_chars < 4:
                        return

                    related_mems = await get_related_memories(user_id, probe, is_live_mode=True)
                    related_lines = _build_dynamic_rag_lines(related_mems or [], max_items=20)
                    facts = await get_memory_facts(user_id, limit=200)
                    fact_lines = _extract_targeted_fact_lines(facts, probe, max_items=20)
                    merged_lines = fact_lines + related_lines
                    if merged_lines:
                        system_update_msg = (
                            "[System Note: Here are memory hints related to what the user just said. "
                            "Prioritize concrete stable facts in your next response. "
                            "Do not claim forgetting if a clear fact is provided below. "
                            "Keep your reply primarily in English.]\n"
                            + "\n".join(merged_lines[:15])
                        )
                        await session.send(input=system_update_msg, end_of_turn=False)
                        last_rag_injected_at = time.time()
                        last_rag_probe_text = probe
                        print(f"Dynamic RAG injected for {user_id}")

                try:
                    while True:
                         async for response in session.receive():
                            server_content = getattr(response, "server_content", None)
                            if server_content:
                                output_transcription = getattr(server_content, "output_transcription", None)
                                if output_transcription and getattr(output_transcription, "text", None):
                                    transcript_text = output_transcription.text
                                    ai_text_buffer.append(transcript_text)
                                    await websocket.send_json({
                                        "type": "transcript",
                                        "text": transcript_text
                                    })

                                input_transcription = getattr(server_content, "input_transcription", None)
                                if input_transcription:
                                    user_transcript_text = getattr(input_transcription, "text", None)
                                    if user_transcript_text:
                                        print(f"User Transcript received: {user_transcript_text}")
                                        user_text_buffer.append(user_transcript_text)
                                        await websocket.send_json({
                                            "type": "user_transcript",
                                            "text": user_transcript_text
                                        })
                                        nonlocal rag_prefetch_timer
                                        if rag_prefetch_timer:
                                            rag_prefetch_timer.cancel()

                                        async def prefetch_rag():
                                            await asyncio.sleep(0.03)  # 縮短至 30ms，更快響應
                                            current_probe = "".join(user_text_buffer).strip()
                                            if current_probe:
                                                print(f"User speaking (partial): {current_probe}")
                                                await inject_live_memory_hints(current_probe)

                                        rag_prefetch_timer = asyncio.create_task(prefetch_rag())

                                model_turn = getattr(server_content, "model_turn", None)
                                if model_turn:
                                    parts = getattr(model_turn, "parts", None)
                                    if parts:
                                        for part in parts:
                                            inline_data = getattr(part, "inline_data", None)
                                            if inline_data and inline_data.data:
                                                try:
                                                    await websocket.send_bytes(inline_data.data)
                                                except Exception as e:
                                                    print(f"Error sending audio bytes: {e}")

                                            text_content = getattr(part, "text", None)
                                            if text_content:
                                                ai_text_buffer.append(text_content)
                                                await websocket.send_json({
                                                    "type": "text",
                                                    "text": text_content
                                                })
                                                
                                turn_complete = getattr(server_content, "turn_complete", None)
                                if turn_complete:
                                    # 當 Gemini 完成回覆 (AI turn complete)
                                    ai_full_text = "".join(ai_text_buffer).strip()
                                    user_full_text = "".join(user_text_buffer).strip()
                                    
                                    if not user_full_text:
                                        user_full_text = "[Voice Audio]" 
                                        
                                    if ai_full_text:
                                        print(f"Saving Live Memory: User='{user_full_text}' AI='{ai_full_text[:50]}...'")
                                        asyncio.create_task(
                                            save_memory(
                                                user_id, 
                                                user_full_text, 
                                                ai_full_text, 
                                                "Neutral" 
                                            )
                                        )
                                        # 每次對話完成後，動態追加到 System Prompt 快取
                                        append_to_cached_system_prompt(user_id, user_full_text, ai_full_text)
                                        
                                        if should_refresh_memory_summaries(user_id):
                                            asyncio.create_task(refresh_memory_summaries(user_id))
                                        if should_refresh_memory_index(user_id):
                                            asyncio.create_task(refresh_memory_index(user_id))
                                    
                                    # 清空緩衝區，準備下一回合
                                    ai_text_buffer.clear()
                                    user_text_buffer.clear()
                                    last_rag_probe_text = ""
                                    if rag_prefetch_timer:
                                        rag_prefetch_timer.cancel()
                                        rag_prefetch_timer = None

                                    await websocket.send_json({
                                        "type": "control",
                                        "event": "turn_complete"
                                    })
                except Exception as e:
                    print(f"Error receiving from Gemini: {e}")
                    traceback.print_exc()
            
            tasks =[asyncio.create_task(receive_from_client()), asyncio.create_task(receive_from_gemini())]
            done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in pending:
                task.cancel()

    except WebSocketDisconnect:
        print(f"WebSocket disconnected for {user_id}")
    except Exception as e:
        print(f"WebSocket Error: {e}")
        traceback.print_exc()
        try:
            await websocket.close(code=1011, reason=str(e))
        except:
            pass
    finally:
        sockets = ACTIVE_LIVE_SOCKETS.get(user_id)
        if sockets and websocket in sockets:
            sockets.discard(websocket)
            if not sockets:
                ACTIVE_LIVE_SOCKETS.pop(user_id, None)
        print(f"WebSocket session ended for {user_id}")
