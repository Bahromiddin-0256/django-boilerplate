# Centralized Logging with Grafana Loki

This project uses **Grafana Loki** for centralized log aggregation, with **Promtail** as the log shipper and **Grafana** for visualization.

## Architecture

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│ Django  │────▶│Promtail │────▶│  Loki   │◄────│ Grafana │
│ Celery  │     │(shipper)│     │(storage)│     │   (UI)  │
│ Nginx   │     └─────────┘     └─────────┘     └─────────┘
└─────────┘         ▲
                    │ reads Docker logs
            /var/lib/docker/containers
```

## Quick Start

### Development

```bash
# Start all services including Loki, Promtail, and Grafana
make dev

# Or manually:
docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# Access Grafana at http://localhost:3000
# Default credentials: admin / admin (or as set in .env)
```

### Production

```bash
# Start production stack with logging
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Access Grafana at http://localhost:3000
```

## Configuration

### Environment Variables

Add these to your `.env` file:

```env
# Logging level: DEBUG, INFO, WARNING, ERROR
LOG_LEVEL=INFO

# Enable JSON logging for Loki (1 = enabled)
JSON_LOGGING=1

# Grafana credentials
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=change-me-in-production
GRAFANA_ROOT_URL=http://localhost:3000
```

### Services

| Service  | Port | Purpose                    |
|----------|------|---------------------------|
| Grafana  | 3000 | Log visualization UI      |
| Loki     | 3100 | Log aggregation (internal)|
| Promtail | 9080 | Log collection (internal) |

## Using Correlation IDs

Correlation IDs allow you to trace requests across services (Django → Celery).

### In Views

```python
import logging
from apps.common.middleware.logging_middleware import get_correlation_id

logger = logging.getLogger("apps.myapp")

def my_view(request):
    # Correlation ID is automatically added to all logs
    logger.info("Processing request")

    # Get the current correlation ID
    corr_id = get_correlation_id()
    logger.info(f"Current correlation ID: {corr_id}")

    # Pass to Celery task - correlation ID is automatically propagated!
    my_task.delay(data="example")
```

### In Celery Tasks

```python
from celery import shared_task
import logging

logger = logging.getLogger("apps.myapp")

@shared_task
def my_task(data):
    # Correlation ID from the request that triggered this task
    # is automatically available
    logger.info("Processing task", extra={"data": data})
```

### Manual Context (for background jobs)

```python
from apps.common.middleware.logging_middleware import CeleryLoggingContext

with CeleryLoggingContext() as corr_id:
    # All logs in this block will have the same correlation ID
    logger.info("Starting background job")
    process_data()
    logger.info("Background job completed")
```

## Querying Logs in Grafana

### Basic Queries

```logql
# All logs from web containers
{job="containerlogs", container_name=~".*web.*"}

# All logs from Celery workers
{job="containerlogs", container_name=~".*celery.*"}

# Logs with specific correlation ID
{job="containerlogs"} | json | correlation_id="abc-123"
```

### Parsed JSON Queries

```logql
# Parse JSON and filter by level
{job="containerlogs"} | json | level="ERROR"

# Filter by event type
{job="containerlogs"} | json | event="request_completed"

# Find slow requests (duration > 1000ms)
{job="containerlogs"} | json | event="request_completed" | duration_ms > 1000
```

### Line Formatting

```logql
# Pretty print with correlation ID
{job="containerlogs"} | json | line_format "[{{.level}}] [{{.correlation_id}}] {{.message}}"
```

## Log Structure

All logs are output as JSON with these fields:

```json
{
  "asctime": "2024-01-15T10:30:00.123Z",
  "levelname": "INFO",
  "name": "apps.common.middleware",
  "message": "Request completed",
  "pathname": "/app/apps/common/middleware/logging_middleware.py",
  "lineno": 95,
  "funcName": "_log_response",
  "threadName": "MainThread",
  "service": "django-api",
  "environment": "development",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

## Request/Response Logging

The `LoggingMiddleware` automatically logs:

- **Request started**: HTTP method, path, query params, client IP, user agent
- **Request completed**: Status code, duration, response size
- **Errors**: Exception details with stack traces

Add `X-Correlation-ID` header to requests to trace them:

```bash
curl -H "X-Correlation-ID: my-trace-id" http://localhost:8000/api/endpoint/
```

## Troubleshooting

### No logs in Grafana

1. Check Loki is running: `docker compose ps loki`
2. Check Promtail is shipping logs: `docker logs <promtail-container>`
3. Verify Promtail can read Docker logs: `docker exec <promtail-container> ls /var/lib/docker/containers`

### Logs not in JSON format

Ensure `JSON_LOGGING=1` in your `.env` file.

### High memory usage

Loki memory can grow with log volume. In `docker/loki/loki-config.yml`:
- Adjust `limits_config.ingestion_rate_mb`
- Set retention with `table_manager.retention_period`

## Resources

- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/query/)
- [Promtail Configuration](https://grafana.com/docs/loki/latest/clients/promtail/configuration/)
