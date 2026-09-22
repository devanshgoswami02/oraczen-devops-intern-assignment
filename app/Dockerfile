# ---- builder stage: install dependencies ----
FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ---- runtime stage: slim, non-root ----
FROM python:3.12-slim

# Create a non-root user to run the app
RUN useradd --create-home --uid 1000 appuser

WORKDIR /app

# Copy installed packages from the builder stage (pip --user installs to ~/.local)
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY main.py database.py models.py schemas.py ./

# Make sure the appuser owns everything and can find the installed packages
RUN chown -R appuser:appuser /app
ENV PATH=/home/appuser/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1

USER appuser

EXPOSE 8000

# Liveness check: /healthz does not touch the DB, so it's safe to use here too.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/healthz')" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
