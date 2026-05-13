FROM python:3.12-slim

LABEL maintainer="helep-team" \
      service="notification-service" \
      version="1.0.0"

RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

RUN mkdir -p /data && chown appuser:appgroup /data

USER appuser

ENV PYTHONUNBUFFERED=1 \
    SERVICE_PORT=8004

EXPOSE 8004

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8004/healthz')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8004"]
