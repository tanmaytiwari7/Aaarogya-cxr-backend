FROM python:3.11-slim

WORKDIR /app

# libgl1/libglib2.0-0 are needed by scikit-image/torchxrayvision's image I/O.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

ENV CXR_DEFAULT_MODEL=all
# Set CXR_API_KEY at deploy time (docker run -e CXR_API_KEY=... / platform secret).

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
