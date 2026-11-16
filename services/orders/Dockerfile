# Debian-based (glibc) image: OTel operator Python auto-instrumentation defaults to glibc wheels.
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
ENV PORT=8080 PYTHONUNBUFFERED=1
EXPOSE 8080
USER nobody
# Run via the Flask dev server (plain `python app.py`) so auto-instrumentation can wrap Flask directly.
CMD ["python", "app.py"]
