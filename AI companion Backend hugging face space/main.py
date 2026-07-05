import time
from fastapi import FastAPI
from routes_chat import router as chat_router
from routes_memory import router as memory_router
from routes_persona import router as persona_router

app = FastAPI(title="AI Companion Backend")

# Include Routers
app.include_router(chat_router, tags=["Chat"])
app.include_router(memory_router, tags=["Memory"])
app.include_router(persona_router, tags=["Persona"])

@app.get("/health")
async def health_check():
    return {"status": "ok", "timestamp": time.time()}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
