"""
Celery signal handlers for logging and context propagation.
"""

import logging

from celery.signals import before_task_publish, task_prerun, task_postrun, task_failure

from apps.common.middleware.logging_middleware import correlation_id, CeleryLoggingContext

logger = logging.getLogger("apps.common.celery")


@before_task_publish.connect
def on_before_task_publish(headers=None, body=None, **kwargs):
    """Propagate correlation ID to Celery task headers."""
    from apps.common.middleware.logging_middleware import get_correlation_id

    corr_id = get_correlation_id()
    if corr_id and headers is not None:
        headers["correlation_id"] = corr_id


@task_prerun.connect
def on_task_prerun(task=None, kwargs=None, **rest):
    """Set correlation ID from task headers when task starts."""
    if task and hasattr(task, "request"):
        corr_id = task.request.get("correlation_id") or task.request.headers.get("correlation_id") if task.request.headers else None
        if corr_id:
            # Store token to reset later
            task._corr_token = correlation_id.set(corr_id)
            logger.info(
                "Celery task started",
                extra={
                    "correlation_id": corr_id,
                    "event": "celery_task_started",
                    "task_id": task.request.id,
                    "task_name": task.name,
                }
            )


@task_postrun.connect
def on_task_postrun(task=None, retval=None, state=None, **kwargs):
    """Log task completion and clean up correlation ID."""
    from apps.common.middleware.logging_middleware import get_correlation_id

    corr_id = get_correlation_id()
    log_data = {
        "correlation_id": corr_id,
        "event": "celery_task_completed",
        "task_id": task.request.id if task and task.request else None,
        "task_name": task.name if task else None,
        "task_state": state,
    }

    if state == "SUCCESS":
        logger.info("Celery task completed", extra=log_data)
    else:
        logger.warning("Celery task completed with non-success state", extra=log_data)

    # Clean up correlation ID
    if hasattr(task, "_corr_token"):
        correlation_id.reset(task._corr_token)


@task_failure.connect
def on_task_failure(task=None, exc=None, task_id=None, args=None, kwargs=None, **rest):
    """Log task failure."""
    from apps.common.middleware.logging_middleware import get_correlation_id

    logger.exception(
        "Celery task failed",
        extra={
            "correlation_id": get_correlation_id(),
            "event": "celery_task_failed",
            "task_id": task_id,
            "task_name": task.name if task else None,
            "exception_type": type(exc).__name__ if exc else None,
            "exception_message": str(exc) if exc else None,
        }
    )
