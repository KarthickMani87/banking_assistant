FROM python:3.11-slim

# System deps (ffmpeg needed for audio conversion)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set workdir
WORKDIR /app

# Copy requirements first (for caching)
COPY requirements.txt .

# Install deps
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY voice_auth.py .

EXPOSE 8000

CMD ["uvicorn", "voice_auth:app", "--host", "0.0.0.0", "--port", "8000"]

