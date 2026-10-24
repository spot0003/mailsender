FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv
COPY quicklink/requirements.lock /srv/requirements.lock
RUN pip install --no-cache-dir -r requirements.lock && useradd --uid 10001 --create-home quickdrop
COPY quicklink /srv/quicklink
USER 10001
EXPOSE 8080
CMD ["uvicorn", "quicklink.service:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1", "--no-access-log", "--no-proxy-headers"]
