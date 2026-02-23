FROM python:3.10-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH="/root/.local/bin:$PATH" \
    HOME="/root"

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    portaudio19-dev \
    libportaudio2 \
    ffmpeg \
    xdotool \
    x11-utils \
    pulseaudio-utils \
    curl \
    gcc \
    g++ \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN uv tool install faster-whisper-hotkey

COPY patch.sh /patch.sh
RUN chmod +x /patch.sh && bash /patch.sh


COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY web/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY web/ /app/

WORKDIR /app
EXPOSE 7860

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "app.py"]
