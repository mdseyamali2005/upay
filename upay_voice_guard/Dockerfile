FROM python:3.12-slim

WORKDIR /app

# Install dependencies first for better Docker layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Render/Railway set PORT env var; default to 8000
ENV PORT=8000
ENV PYTHONUNBUFFERED=1
EXPOSE ${PORT}

# Health check — cloud platforms hit /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import httpx; httpx.get(f'http://localhost:${PORT}/health').raise_for_status()" || exit 1

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
