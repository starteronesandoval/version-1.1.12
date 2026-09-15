FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
RUN addgroup --system balam && adduser --system --ingroup balam balam
COPY requirements.txt ./
RUN pip install -r requirements.txt
COPY alembic.ini ./
COPY migrations ./migrations
COPY app ./app
RUN mkdir -p /data/uploads && chown -R balam:balam /app /data/uploads

USER balam
EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips=${FORWARDED_ALLOW_IPS:-127.0.0.1}"]
