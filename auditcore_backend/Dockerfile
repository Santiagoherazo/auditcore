FROM python:3.12.9-slim

# Dependencias del sistema para WeasyPrint, psycopg2 y compilación
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    libcairo2 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf2.0-0 \
    libffi-dev \
    shared-mime-info \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Actualizar pip para evitar bugs de verificación de hashes en versiones antiguas
RUN pip install --upgrade --no-cache-dir pip

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p media/evidencias media/certificados media/documentos media/reportes \
    # FIX: staticfiles dir must exist before collectstatic runs in entrypoint.sh
    && mkdir -p staticfiles

EXPOSE 8000
