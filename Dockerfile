# =============================================================================
# Stage 1: Base image with system dependencies
# =============================================================================
FROM python:3.13-slim AS base

# Prevent Python from writing bytecode and ensure unbuffered output
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # pip configuration
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Install system dependencies required for PostgreSQL and building Python packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user for security
RUN groupadd --gid 1000 appgroup \
    && useradd --uid 1000 --gid appgroup --shell /bin/bash --create-home appuser

# =============================================================================
# Stage 2: Builder stage for installing dependencies
# =============================================================================
FROM base AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install uv for fast dependency installation
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy requirements first for better layer caching
COPY requirements/ /app/requirements/

# Create virtual environment and install base dependencies
RUN uv venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN uv pip install --no-cache -r requirements/base.txt

# =============================================================================
# Stage 3: Development image
# =============================================================================
FROM builder AS development

# Install development dependencies
RUN uv pip install --no-cache -r requirements/develop.txt

# Copy application code
COPY --chown=appuser:appgroup . /app/

# Set environment for development
ENV DJANGO_SETTINGS_MODULE=core.settings.develop \
    PATH="/opt/venv/bin:$PATH"

USER appuser

EXPOSE 8000

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

# =============================================================================
# Stage 4: Test image
# =============================================================================
FROM builder AS test

# Install test dependencies (includes dev dependencies for testing tools)
RUN uv pip install --no-cache -r requirements/develop.txt
# Install test-specific dependencies if any
RUN if [ -s requirements/test.txt ]; then uv pip install --no-cache -r requirements/test.txt; fi

# Copy application code
COPY --chown=appuser:appgroup . /app/

# Set environment for testing
ENV DJANGO_SETTINGS_MODULE=core.settings.test \
    PATH="/opt/venv/bin:$PATH"

USER appuser

CMD ["python", "manage.py", "test"]

# =============================================================================
# Stage 5: Production image
# =============================================================================
FROM base AS production

# Install production dependencies only
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
COPY requirements/ /app/requirements/

RUN uv venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN uv pip install --no-cache -r requirements/production.txt

# Copy application code
COPY --chown=appuser:appgroup . /app/

# Copy entrypoint script
COPY --chown=appuser:appgroup docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set production environment
ENV DJANGO_SETTINGS_MODULE=core.settings.production \
    PATH="/opt/venv/bin:$PATH"

# Collect static files
RUN python manage.py collectstatic --noinput --clear || true

# Switch to non-root user
USER appuser

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]

CMD ["gunicorn", "core.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "4", "--threads", "2", "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "--error-logfile", "-"]