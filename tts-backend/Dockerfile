FROM python:3.11-slim

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg espeak-ng libespeak-ng1 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY requirements.txt .
COPY server.py .

EXPOSE 8000
ENV OMP_NUM_THREADS=1

# At runtime: upgrade pip, install torch + deps, install requirements, pull model, then run server
ENTRYPOINT ["/bin/sh", "-c", "\
  python -m pip install -U pip wheel setuptools && \
  if [ \"$(uname -m)\" = \"x86_64\" ]; then \
    python -m pip install --index-url https://download.pytorch.org/whl/cpu torch==2.3.1 torchvision==0.18.1 torchaudio==2.3.1; \
  else \
    python -m pip install torch==2.3.1 torchvision==0.18.1 torchaudio==2.3.1; \
  fi && \
  python -m pip install -r requirements.txt && \
  python -c 'from TTS.api import TTS; TTS(model_name=\"tts_models/en/ljspeech/tacotron2-DDC_ph\")' && \
  uvicorn server:app --host 0.0.0.0 --port 8000"]
