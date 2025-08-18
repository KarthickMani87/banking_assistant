# app.py
import os, tempfile
from typing import Optional, List

from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from faster_whisper import WhisperModel

# ---------- Config ----------
MODEL_NAME = os.getenv("WHISPER_MODEL", "tiny.en")
COMPUTE_TYPE = os.getenv("WHISPER_COMPUTE_TYPE", "float32")
VAD_ENABLE_DEFAULT = True
VAD_MIN_SILENCE_MS = 200
BEAM_SIZE = 5
TEMPERATURE = 0.0
NO_SPEECH_THRESHOLD = 0.8
LOG_PROB_THRESHOLD = -0.3
# ----------------------------

app = FastAPI(title="STT Backend", version="1.0.0")

# CORS (adjust to your frontend origins in prod)
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ALLOW_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load model once at startup
model = WhisperModel(MODEL_NAME, compute_type=COMPUTE_TYPE)

class Segment(BaseModel):
    start: float
    end: float
    text: str

class TranscriptionResponse(BaseModel):
    text: str
    segments: List[Segment]
    language: Optional[str] = None
    duration: Optional[float] = None
    model_name: str

@app.post("/transcribe", response_model=TranscriptionResponse)
def transcribe_file(
    file: UploadFile = File(..., description="Audio file (wav, mp3, m4a, webm/ogg/opus, etc.)"),
    language: Optional[str] = Form(default="en"),
    vad: bool = Form(default=VAD_ENABLE_DEFAULT),
    beam_size: int = Form(default=BEAM_SIZE),
    temperature: float = Form(default=TEMPERATURE),
    no_speech_threshold: float = Form(default=NO_SPEECH_THRESHOLD),
    log_prob_threshold: float = Form(default=LOG_PROB_THRESHOLD),
    condition_on_previous_text: bool = Form(default=False),
):
    if file.size is not None and file.size == 0:
        raise HTTPException(status_code=400, detail="Empty file.")

    suffix = os.path.splitext(file.filename or "")[1] or ".audio"
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp_path = tmp.name
            tmp.write(file.file.read())
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save upload: {e}")

    try:
        segments, info = model.transcribe(
            tmp_path,
            language=language,
            vad_filter=vad,
            vad_parameters=dict(min_silence_duration_ms=VAD_MIN_SILENCE_MS),
            beam_size=beam_size,
            temperature=temperature,
            no_speech_threshold=no_speech_threshold,
            log_prob_threshold=log_prob_threshold,
            condition_on_previous_text=condition_on_previous_text,
        )

        segs = []
        text_parts = []
        for s in segments:
            segs.append(Segment(start=s.start, end=s.end, text=s.text))
            text_parts.append(s.text)

        full_text = "".join(text_parts).strip()

        return TranscriptionResponse(
            text=full_text,
            segments=segs,
            language=getattr(info, "language", language),
            duration=getattr(info, "duration", None),
            model_name=MODEL_NAME,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transcription error: {e}")
    finally:
        try:
            os.remove(tmp_path)
        except Exception:
            pass

@app.get("/healthz")
def health_check():
    return JSONResponse({"ok": True, "model": MODEL_NAME, "compute_type": COMPUTE_TYPE})

