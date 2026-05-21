"""
Lambda API handler — instrumented with AWS X-Ray active tracing.
X-Ray automatically captures: invocation metadata, cold starts,
downstream HTTP calls, and custom subsegments.

Satisfies the AWS credit activity: Lambda function with function URL.
"""

import json
import os
import urllib.request
import urllib.error
from datetime import datetime, timezone

# X-Ray SDK — pre-installed in Lambda Python runtime
# Patches stdlib http clients so downstream calls are auto-traced
from aws_xray_sdk.core import xray_recorder, patch_all

patch_all()


def lambda_handler(event, context):
    """
    Routes requests by path:
      GET /        → service info
      GET /health  → health check (ALB / load balancer target)
      GET /trace   → demo subsegment + downstream call (shows X-Ray graph)
    """
    path = event.get("rawPath", "/")
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if path == "/health":
        return _health()

    if path == "/trace":
        return _trace_demo(context)

    return _index(event, context)


# ── Route handlers ─────────────────────────────────────────────────────────────

def _health():
    return _response(200, {"status": "healthy", "service": "lambda-api"})


def _index(event, context):
    return _response(200, {
        "service":      "multi-az-webapp lambda-api",
        "version":      "1.0.0",
        "region":       os.environ.get("AWS_REGION", "unknown"),
        "function_name": context.function_name,
        "memory_mb":    context.memory_limit_in_mb,
        "request_id":   context.aws_request_id,
        "timestamp":    datetime.now(timezone.utc).isoformat(),
        "endpoints": {
            "health": "/health",
            "trace":  "/trace — triggers a custom X-Ray subsegment",
        }
    })


def _trace_demo(context):
    """
    Creates a custom X-Ray subsegment to demonstrate manual instrumentation.
    Shows up in the X-Ray service map as a named segment under this function.
    """
    with xray_recorder.in_subsegment("business-logic") as subsegment:
        # Annotate with indexable key/value pairs (searchable in X-Ray console)
        subsegment.put_annotation("function_name", context.function_name)
        subsegment.put_annotation("request_id", context.aws_request_id)

        # Metadata is not searchable but shows in trace detail view
        subsegment.put_metadata("runtime", {
            "python_version": "3.12",
            "memory_mb": context.memory_limit_in_mb,
        })

        result = _simulate_work()

    return _response(200, {
        "message":    "X-Ray trace captured — check the X-Ray console",
        "subsegment": "business-logic",
        "result":     result,
        "xray_console": (
            "https://console.aws.amazon.com/xray/home"
            "#/traces?filter=annotation.function_name%3D%22"
            f"{context.function_name}%22"
        ),
    })


def _simulate_work():
    """Fake some processing so the subsegment has measurable duration."""
    items = [i ** 2 for i in range(1000)]
    return {"computed_items": len(items), "sample": items[:5]}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":                "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
