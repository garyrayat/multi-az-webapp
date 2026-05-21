"""
Lambda API handler — AWS X-Ray active tracing + structured JSON logging
with W3C Trace Context (traceparent) propagation.

Trace flow:
  Client → Function URL → Lambda → X-Ray
                          ↓
                  structured log lines (CloudWatch) carry trace_id from traceparent

W3C traceparent header format: 00-{trace_id_32hex}-{parent_id_16hex}-{flags}
Lambda reads the header, extracts the trace_id, and stamps it on every log line.
This creates the log-to-trace correlation: CloudWatch Insights query on trace_id
→ click the trace_id → X-Ray console for the full distributed trace.

X-Ray SDK patches stdlib http clients so downstream calls are auto-traced.
"""

import json
import logging
import os
import re
import sys
from datetime import datetime, timezone

# X-Ray SDK — pre-installed in Lambda Python runtime
from aws_xray_sdk.core import xray_recorder, patch_all

patch_all()

# ── Structured JSON logger ─────────────────────────────────────────────────────
# Replaces Lambda's default plaintext logger. Every log line is a JSON object
# written to stdout → CloudWatch Logs. Fields are consistent across all services:
# trace_id, service, environment, log.level — queryable in CloudWatch Insights.
#
# Why not aws_lambda_powertools? Zero deps. This is 20 lines that does the same
# thing for the fields we actually use.
class _StructuredLogger:
    """Emits newline-delimited JSON to stdout. Lambda captures stdout → CloudWatch."""

    def __init__(self):
        self._service     = os.environ.get("POWERTOOLS_SERVICE_NAME", "lambda-api")
        self._environment = os.environ.get("ENVIRONMENT", "dev")
        self._trace_id    = None          # set per-invocation from traceparent
        self._request_id  = None          # set per-invocation from context

    def bind(self, trace_id: str, request_id: str):
        """Call at the top of lambda_handler to stamp every subsequent log line."""
        self._trace_id  = trace_id
        self._request_id = request_id

    def _emit(self, level: str, message: str, **extra):
        record = {
            "time":        datetime.now(timezone.utc).isoformat(),
            "log.level":   level,
            "message":     message,
            "service":     self._service,
            "environment": self._environment,
            "trace_id":    self._trace_id,    # links this line to X-Ray trace
            "request_id":  self._request_id,  # links this line to Lambda invocation
        }
        record.update(extra)
        # sys.stdout — Lambda captures it to CloudWatch without buffering issues
        print(json.dumps(record, default=str), file=sys.stdout)

    def info(self, msg, **kw):  self._emit("INFO",  msg, **kw)
    def warn(self, msg, **kw):  self._emit("WARN",  msg, **kw)
    def error(self, msg, **kw): self._emit("ERROR", msg, **kw)


log = _StructuredLogger()


# ── W3C traceparent parser ────────────────────────────────────────────────────
# traceparent: 00-{trace_id}-{parent_id}-{flags}
# trace_id is 32 hex chars — the single key that correlates nginx log → Lambda log
# → X-Ray trace span. Without extracting it here, you can't search CloudWatch for
# "all logs belonging to trace abc123".
_TRACEPARENT_RE = re.compile(
    r"^00-(?P<trace_id>[0-9a-f]{32})-(?P<parent_id>[0-9a-f]{16})-(?P<flags>[0-9a-f]{2})$"
)

def _parse_traceparent(headers: dict) -> tuple[str | None, str | None]:
    """
    Returns (trace_id, raw_traceparent) from the incoming headers dict.
    Header name lookup is case-insensitive (HTTP/2 lowercases all headers).
    Returns (None, None) if header is absent or malformed.
    """
    raw = (
        headers.get("traceparent")
        or headers.get("Traceparent")
        or headers.get("x-amzn-trace-id")  # X-Ray native header fallback
    )
    if not raw:
        return None, None

    m = _TRACEPARENT_RE.match(raw)
    if m:
        return m.group("trace_id"), raw

    # X-Ray native format: "Root=1-xxx-yyy;Parent=zzz;Sampled=1"
    # Extract Root ID and normalise to a 32-char hex trace_id
    root_match = re.search(r"Root=1-(?P<epoch>[0-9a-f]{8})-(?P<unique>[0-9a-f]{24})", raw or "")
    if root_match:
        trace_id = root_match.group("epoch") + root_match.group("unique")
        return trace_id, raw

    return None, raw


# ── Lambda handler ─────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    """
    Routes requests by path. Extracts traceparent on every request and stamps
    it on all log lines for the duration of this invocation.

    Routes:
      GET /        → service info
      GET /health  → 200 OK (health check)
      GET /trace   → custom X-Ray subsegment demo
    """
    headers   = event.get("headers") or {}
    path      = event.get("rawPath", "/")
    method    = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    # Extract trace_id from W3C traceparent (or X-Ray native header).
    # Bind to the logger so every log line carries it.
    trace_id, traceparent = _parse_traceparent(headers)
    log.bind(trace_id=trace_id, request_id=context.aws_request_id)

    log.info("request received",
             method=method,
             path=path,
             traceparent=traceparent,
             cold_start=_is_cold_start())

    if path == "/health":
        return _health()

    if path == "/trace":
        return _trace_demo(context, trace_id)

    return _index(event, context, trace_id)


# ── Route handlers ─────────────────────────────────────────────────────────────

def _health():
    log.info("health check")
    return _response(200, {"status": "healthy", "service": "lambda-api"})


def _index(event, context, trace_id: str | None):
    log.info("index request handled", trace_id=trace_id)
    return _response(200, {
        "service":       "multi-az-webapp lambda-api",
        "version":       "1.0.0",
        "region":        os.environ.get("AWS_REGION", "unknown"),
        "function_name": context.function_name,
        "memory_mb":     context.memory_limit_in_mb,
        "request_id":    context.aws_request_id,
        "trace_id":      trace_id,           # expose in response body for easy testing
        "timestamp":     datetime.now(timezone.utc).isoformat(),
        "endpoints": {
            "health": "/health",
            "trace":  "/trace — custom X-Ray subsegment + structured log demo",
        },
    })


def _trace_demo(context, trace_id: str | None):
    """
    Creates a named X-Ray subsegment so the trace appears in the service map
    with a child node labelled "business-logic". Annotations are indexed and
    searchable in X-Ray; metadata is visible in trace detail only.
    """
    log.info("trace demo starting", subsegment="business-logic")

    with xray_recorder.in_subsegment("business-logic") as subsegment:
        subsegment.put_annotation("function_name", context.function_name)
        subsegment.put_annotation("request_id",    context.aws_request_id)
        # trace_id from incoming traceparent — links X-Ray trace to nginx/CloudWatch logs
        if trace_id:
            subsegment.put_annotation("trace_id", trace_id)

        subsegment.put_metadata("runtime", {
            "python_version": "3.12",
            "memory_mb":      context.memory_limit_in_mb,
        })

        result = _simulate_work()

    log.info("trace demo complete",
             subsegment="business-logic",
             computed_items=result["computed_items"])

    return _response(200, {
        "message":    "X-Ray trace captured — check X-Ray console",
        "subsegment": "business-logic",
        "trace_id":   trace_id,
        "result":     result,
    })


def _simulate_work():
    items = [i ** 2 for i in range(1000)]
    return {"computed_items": len(items), "sample": items[:5]}


# ── Cold start detection ──────────────────────────────────────────────────────
# Module-level flag: False on cold start (first invocation after container init),
# True on all warm invocations. Logged so you can filter cold starts in CloudWatch
# Insights: `filter cold_start = false | stats count() by bin(5m)`.
_warm = False

def _is_cold_start() -> bool:
    global _warm
    if not _warm:
        _warm = True
        return True   # this was a cold start
    return False


# ── Helpers ───────────────────────────────────────────────────────────────────

def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":                "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
