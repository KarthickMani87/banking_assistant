FROM python:3.11-slim

# system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg espeak-ng libespeak-ng1 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY requirements.txt .

# Install a pinned CPU torch first (prevents resolver thrash)
# Use CPU index on amd64; on arm64 let PyPI provide the right wheel.
ARG TARGETARCH
RUN python -m pip install -U pip wheel setuptools && \
    if [ "$TARGETARCH" = "amd64" ]; then \
      python -m pip install --index-url https://download.pytorch.org/whl/cpu \
        torch==2.3.1 torchvision==0.18.1 torchaudio==2.3.1; \
    else \
      python -m pip install \
        torch==2.3.1 torchvision==0.18.1 torchaudio==2.3.1; \
    fi

# Now install Coqui TTS and friends (torch already satisfied)
RUN python -m pip install -r requirements.txt

RUN python -c "from TTS.api import TTS; TTS(model_name='tts_models/en/ljspeech/tacotron2-DDC_ph')"

COPY server.py .
EXPOSE 8000
# comment must be on its own line
ENV OMP_NUM_THREADS=1
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]

