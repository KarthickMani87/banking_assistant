import os
import jwt
import numpy as np
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydub import AudioSegment
from resemblyzer import VoiceEncoder, preprocess_wav
import uuid, tempfile

# ---------------- Config ----------------
SECRET = os.getenv("JWT_SECRET", "supersecret")
JWT_ALGO = "HS256"

# For demo: store enrolled voices in memory
# In production: use a DB
enrolled_voices = {}  # {username: embedding_vector}

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "http://localhost:5173").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

encoder = VoiceEncoder()

# ---------------- Helpers ----------------
def extract_embedding(audio_path: str):
    wav = preprocess_wav(audio_path)
    return encoder.embed_utterance(wav)

def cosine_similarity(v1, v2):
    return np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2))

def issue_jwt(username: str):
    payload = {"sub": username, "jti": str(uuid.uuid4())}
    return jwt.encode(payload, SECRET, algorithm=JWT_ALGO)

# ---------------- API ----------------
@app.post("/enroll/{username}")
async def enroll(username: str, file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
        audio = AudioSegment.from_file(file.file)
        audio.export(tmp.name, format="wav")
        emb = extract_embedding(tmp.name)
        enrolled_voices[username] = emb
    return {"message": f"Enrolled {username}"}

@app.get("/healthz")
async def healthz():
    return {"ok": True}

@app.post("/voice-login")
async def voice_login(file: UploadFile = File(...)):
    if not enrolled_voices:
        raise HTTPException(400, "No enrolled users yet")

    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
        audio = AudioSegment.from_file(file.file)
        audio.export(tmp.name, format="wav")
        emb = extract_embedding(tmp.name)

    # Find best match
    best_user, best_score = None, -1
    for username, enrolled_emb in enrolled_voices.items():
        sim = float(cosine_similarity(emb, enrolled_emb))   # ✅ cast here
        if sim > best_score:
            best_user, best_score = username, sim

    if best_score < 0.75:  # threshold
        raise HTTPException(401, f"Voice not recognized (score={best_score:.2f})")

    token = issue_jwt(best_user)
    return {
        "username": best_user,
        "score": float(best_score),   # ✅ cast here
        "token": token
    }

