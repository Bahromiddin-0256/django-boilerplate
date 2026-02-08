"""
Logging middleware for Django with correlation ID support.
Integrates with Grafana Loki for centralized logging.
"""

import logging
import time
import uuid
from contextvars import ContextVar
from typing import Optional

from django.http import HttpRequest, HttpResponse

# Context variable for correlation ID that persists across async boundaries
correlation_id: ContextVar[Optional[str]] = ContextVar("correlation_id", default=None)

logger = logging.getLogger("apps.common.middleware")


class CeleryLoggingContext:
    """Context manager for propagating correlation ID to Celery tasks."""

    def __init__(self, corr_id: Optional[str] = None):
        self.corr_id = corr_id or str(uuid.uuid4())
        self.token = None

    def __enter__(self):
        self.token = correlation_id.set(self.corr_id)
        return self.corr_id

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.token:
            correlation_id.reset(self.token)


class LoggingMiddleware:
    """
    Middleware that adds correlation IDs to requests and logs request/response details.

    Features:
    - Generates unique correlation ID for each request
    - Logs request details (method, path, user, query params)
    - Logs response details (status, duration, body size)
    - Adds correlation ID to response headers for tracing
    - Compatible with Grafana Loki structured logging
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        # Generate or extract correlation ID
        corr_id = request.headers.get("X-Correlation-ID") or str(uuid.uuid4())
        token = correlation_id.set(corr_id)

        # Set correlation ID on request for access in views
        request.correlation_id = corr_id

        start_time = time.time()

        # Log request
        self._log_request(request, corr_id)

        try:
            response = self.get_response(request)
        except Exception as e:
            duration = time.time() - start_time
            self._log_exception(request, corr_id, duration, e)
            raise

        duration = time.time() - start_time

        # Log response
        self._log_response(request, response, corr_id, duration)

        # Add correlation ID to response headers
        response["X-Correlation-ID"] = corr_id

        # Clean up context
        correlation_id.reset(token)

        return response

    def _log_request(self, request: HttpRequest, corr_id: str) -> None:
        """Log incoming request details."""
        user = request.user if hasattr(request, "user") and request.user.is_authenticated else "anonymous"

        logger.info(
            "Request started",
            extra={
                "correlation_id": corr_id,
                "event": "request_started",
                "http_method": request.method,
                "http_path": request.path,
                "query_string": request.META.get("QUERY_STRING", ""),
                "remote_addr": self._get_client_ip(request),
                "user_agent": request.META.get("HTTP_USER_AGENT", ""),
                "user_id": str(user) if user != "anonymous" else None,
                "content_type": request.content_type if hasattr(request, "content_type") else None,
                "content_length": request.META.get("CONTENT_LENGTH", 0),
            }
        )

    def _log_response(self, request: HttpRequest, response: HttpResponse, corr_id: str, duration: float) -> None:
        """Log response details."""
        user = request.user if hasattr(request, "user") and request.user.is_authenticated else "anonymous"

        log_data = {
            "correlation_id": corr_id,
            "event": "request_completed",
            "http_method": request.method,
            "http_path": request.path,
            "status_code": response.status_code,
            "duration_ms": round(duration * 1000, 2),
            "user_id": str(user) if user != "anonymous" else None,
            "content_length": len(response.content) if hasattr(response, "content") else 0,
        }

        # Log at different levels based on status code
        if response.status_code >= 500:
            logger.error("Request failed with server error", extra=log_data)
        elif response.status_code >= 400:
            logger.warning("Request failed with client error", extra=log_data)
        else:
            logger.info("Request completed", extra=log_data)

    def _log_exception(self, request: HttpRequest, corr_id: str, duration: float, exception: Exception) -> None:
        """Log unhandled exception."""
        logger.exception(
            "Request failed with exception",
            extra={
                "correlation_id": corr_id,
                "event": "request_exception",
                "http_method": request.method,
                "http_path": request.path,
                "duration_ms": round(duration * 1000, 2),
                "exception_type": type(exception).__name__,
                "exception_message": str(exception),
            }
        )

    def _get_client_ip(self, request: HttpRequest) -> str:
        """Extract client IP address from request, considering proxies."""
        x_forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")
        if x_forwarded_for:
            ip = x_forwarded_for.split(",")[0].strip()
        else:
            ip = request.META.get("REMOTE_ADDR", "")
        return ip


def get_correlation_id() -> Optional[str]:
    """Get the current correlation ID from context."""
    return correlation_id.get()
