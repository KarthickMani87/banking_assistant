# Dockerfile.cpu
FROM python:3.11-slim

# System deps (ffmpeg is required for audio decoding)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Cache-friendly installs
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App code
COPY app.py .

# Environment (override via docker-compose or env)
ENV WHISPER_MODEL=tiny.en \
    WHISPER_COMPUTE_TYPE=float32 \
    HF_HOME=/models/hf \
    CTRANSLATE2_ROOT=/models/ct2

# Expose HTTP port
EXPOSE 8000

# Healthcheck (optional)
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -f http://localhost:8000/healthz || exit 1

# Start server
CMD ["uvicorn","app:app","--host","0.0.0.0","--port","8000"]

