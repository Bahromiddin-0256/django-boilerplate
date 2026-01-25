FROM python:3.13-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

COPY requirements/ /app/requirements/
RUN uv pip install --system --no-cache -r requirements/develop.txt

COPY . /app/

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

