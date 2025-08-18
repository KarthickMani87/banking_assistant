import os
import re
import tempfile
import subprocess
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from fastapi.responses import FileResponse

# ---------- Config ----------
CORS_ORIGINS = os.getenv("CORS_ORIGINS", "http://localhost:5173,http://localhost:3000")
origins = [o.strip() for o in CORS_ORIGINS.split(",") if o.strip()]

MODEL_NAME = os.getenv("MODEL_NAME", "tts_models/en/ljspeech/tacotron2-DDC_ph")
AUDIO_FORMAT_DEFAULT = os.getenv("AUDIO_FORMAT", "mp3")  # "mp3" | "wav"
DEVICE = os.getenv("DEVICE", "cpu")

# Number-normalization knobs
ALWAYS_SAY_DIGITS = os.getenv("ALWAYS_SAY_DIGITS", "false").lower() in {"1", "true", "yes"}
DIGITS_AS_SEQUENCE_MINLEN = int(os.getenv("DIGITS_AS_SEQUENCE_MINLEN", "5"))
DECIMAL_WORD = os.getenv("DECIMAL_WORD", "point")

# ---------- App ----------
app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------- TTS engine (Coqui) ----------
_tts = None
_model_meta = {"speakers": None, "languages": None}


def _load_tts():
    global _tts, _model_meta
    if _tts is not None:
        return

    try:
        from TTS.api import TTS
    except Exception as e:
        raise RuntimeError(
            f"Coqui TTS not installed. Add `TTS` to requirements. Underlying error: {e}"
        )

    _tts = TTS(model_name=MODEL_NAME).to(DEVICE)
    speakers = getattr(_tts, "speakers", None)
    languages = getattr(_tts, "languages", None)
    if isinstance(speakers, (list, tuple)):
        _model_meta["speakers"] = list(speakers)
    if isinstance(languages, (list, tuple)):
        _model_meta["languages"] = list(languages)

# ---------- Text normalization (digit-by-digit) ----------
PHONE_RE = re.compile(r"""
    (?P<full>
        \+?\s*
        (?:\(\d+\)\s*|\d)
        [\d\-\s\(\)]{6,}
    )
""", re.VERBOSE)

NUMBER_RE = re.compile(r"""
    (?<![\w/])
    (?P<sign>[+\-]?)
    (?P<body>\d[\d,\s_]*(?:[.,]\d+)?)
    (?![\w/])
""", re.VERBOSE)

# Special: number followed by unit words like million/billion
SCALED_NUMBER_RE = re.compile(r"\b(?P<num>\d+)\s+(?P<unit>thousand|million|billion)\b", re.I)


def _speak_digits(d: str) -> str:
    # Use commas to force digit-by-digit reading
    return ", ".join(d)


def _speak_decimal(s: str) -> str:
    if "." in s:
        integer, frac = s.split(".", 1)
    elif "," in s:
        integer, frac = s.split(",", 1)
    else:
        integer, frac = s, ""

    integer_digits = re.sub(r"\D", "", integer)
    frac_digits = re.sub(r"\D", "", frac)

    left = _speak_digits(integer_digits) if integer_digits else "zero"
    right = _speak_digits(frac_digits) if frac_digits else ""
    return f"{left} {DECIMAL_WORD} {right}".strip()


def normalize_text(text: str) -> str:
    out = text.replace("for example:", "for example,").replace("e.g.:", "e.g.,")

    # 1) Phone numbers
    def phone_sub(m: re.Match) -> str:
        raw = m.group("full")
        plus = "plus " if raw.strip().startswith("+") else ""
        digits = re.sub(r"\D", "", raw)
        if not digits:
            return raw
        return plus + _speak_digits(digits) + ","

    out = PHONE_RE.sub(phone_sub, out)

    # 2) Scaled numbers (5 million → "5, million")
    def scaled_number_sub(m: re.Match) -> str:
        num = m.group("num")
        unit = m.group("unit")
        return f"{_speak_digits(num)} {unit},"

    out = SCALED_NUMBER_RE.sub(scaled_number_sub, out)

    # 3) Generic numbers
    def number_sub(m: re.Match) -> str:
        sign = m.group("sign") or ""
        body = m.group("body")
        digits_only = re.sub(r"\D", "", body)
        if not digits_only:
            return m.group(0)

        has_decimal = "." in body or (
            "," in body and body.count(",") == 1 and body.rsplit(",", 1)[-1].isdigit()
        )
        long_enough = len(digits_only) >= DIGITS_AS_SEQUENCE_MINLEN
        speak_as_digits = ALWAYS_SAY_DIGITS or has_decimal or long_enough

        if not speak_as_digits:
            return m.group(0)

        spoken_sign = "minus " if sign == "-" else ("plus " if sign == "+" else "")

        if has_decimal:
            spoken = spoken_sign + _speak_decimal(body.replace(" ", ""))
        else:
            spoken = spoken_sign + _speak_digits(digits_only)

        # 🔧 Add leading space (avoid “is1”) and trailing comma (prosody)
        return "  " + spoken + ","
        #return ". " + spoken + ","

    out = NUMBER_RE.sub(number_sub, out)
    return out


# ---------- I/O schemas ----------
class TTSIn(BaseModel):
    text: str
    audio_format: Optional[str] = None
    speaker: Optional[str] = None
    language: Optional[str] = None

# ---------- Routes ----------
@app.post("/tts")
def tts(body: TTSIn):
    _load_tts()

    text = (body.text or "").strip()
    if not text:
        raise HTTPException(400, "text is required")

    fmt = (body.audio_format or AUDIO_FORMAT_DEFAULT).lower()
    if fmt not in {"mp3", "wav"}:
        raise HTTPException(400, "audio_format must be mp3 or wav")

    norm_text = normalize_text(text)
    print("Normalized:", norm_text)

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as wav_f:
        wav_path = wav_f.name

    synth_kwargs = {"text": norm_text, "file_path": wav_path}
    if body.speaker:
        synth_kwargs["speaker"] = body.speaker
    if body.language:
        synth_kwargs["language"] = body.language

    try:
        _tts.tts_to_file(**synth_kwargs)

        if fmt == "wav":
            return FileResponse(wav_path, media_type="audio/wav", filename="speech.wav")

        mp3_path = wav_path.replace(".wav", ".mp3")
        q = subprocess.run(
            ["ffmpeg", "-y", "-i", wav_path, "-codec:a", "libmp3lame", "-q:a", "4", mp3_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        if q.returncode != 0 or not os.path.exists(mp3_path):
            err = q.stderr.decode("utf-8", "ignore")
            raise HTTPException(500, f"ffmpeg failed: {err}")

        return FileResponse(mp3_path, media_type="audio/mpeg", filename="speech.mp3")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Coqui TTS failed: {e}")

@app.get("/healthz")
def healthz():
    return {"ok": True, "model": MODEL_NAME}

@app.get("/voices")
def voices():
    _load_tts()
    return {
        "model": MODEL_NAME,
        "device": DEVICE,
        "speakers": _model_meta.get("speakers") or [],
        "languages": _model_meta.get("languages") or [],
        "normalize": {
            "ALWAYS_SAY_DIGITS": ALWAYS_SAY_DIGITS,
            "DIGITS_AS_SEQUENCE_MINLEN": DIGITS_AS_SEQUENCE_MINLEN,
            "DECIMAL_WORD": DECIMAL_WORD,
        },
    }
