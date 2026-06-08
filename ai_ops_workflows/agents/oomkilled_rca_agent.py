"""
OOMKilled RCA Agent — Home Depot Platform SRE
=============================================
Triggered by PagerDuty webhook when an OOMKilled or CrashLoopBackOff alert fires.

Flow:
  PagerDuty alert → Lambda/Cloud Run → this agent → MCP tool calls
    → structured RCA → PagerDuty note + optional GitHub issue

The agent uses Claude with tool_use. Every tool call maps to one MCP server
skill defined in skills/oomkilled_rca_skills.yaml. The agent reasons across
all available signals — it is not a fixed pipeline.

Production deployment: Cloud Run job, triggered via PagerDuty webhook extension.
Claude model: claude-sonnet-4-6 (Sonnet 4.6 — best cost/performance for tool-heavy agents)
"""

import json
import os
import sys
from datetime import datetime, timezone
from typing import Any

import anthropic
import yaml
import httpx

# ── Config ────────────────────────────────────────────────────────────────────

MODEL          = "claude-sonnet-4-6"
MAX_TOKENS     = 8192
SKILLS_FILE    = os.path.join(os.path.dirname(__file__), "../skills/oomkilled_rca_skills.yaml")
MCP_CONFIG     = os.path.join(os.path.dirname(__file__), "../mcp/mcp-config.json")

client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])


# ── Load skills as Claude tool definitions ────────────────────────────────────

def load_tools() -> list[dict]:
    """
    Convert the YAML skills file to the Claude tool_use format.
    Each skill becomes one entry in the tools[] array sent to the API.
    The 'description' is what Claude reads to decide when to call the tool.
    """
    with open(SKILLS_FILE) as f:
        skills_config = yaml.safe_load(f)

    tools = []
    for skill in skills_config["skills"]:
        tools.append({
            "name": skill["name"],
            "description": skill["description"].strip(),
            "input_schema": skill["input_schema"],
        })
    return tools


# ── MCP tool dispatcher ───────────────────────────────────────────────────────

class MCPDispatcher:
    """
    Routes Claude's tool_use calls to the correct MCP server.
    In production this uses the MCP SDK client to communicate with each server
    over stdio or HTTP. Here we show the interface — swap in real MCP client calls.

    Each MCP server (kubernetes, google-cloud-monitoring, pagerduty, etc.) is a
    separate process started by the config in mcp-config.json. The dispatcher
    sends tool call JSON to the right server and returns the result.
    """

    def __init__(self):
        with open(MCP_CONFIG) as f:
            self.config = json.load(f)

        # Tool → MCP server mapping (derived from skills YAML 'server' field)
        with open(SKILLS_FILE) as f:
            skills = yaml.safe_load(f)
        self.tool_to_server = {s["name"]: s["server"] for s in skills["skills"]}

    def call(self, tool_name: str, tool_input: dict) -> str:
        """
        Dispatch a tool call to its MCP server.
        Returns JSON string of the result — Claude receives this as tool_result content.
        """
        server_name = self.tool_to_server.get(tool_name)
        if not server_name:
            return json.dumps({"error": f"No MCP server mapped for tool: {tool_name}"})

        server_cfg = self.config["mcpServers"].get(server_name)
        if not server_cfg:
            return json.dumps({"error": f"MCP server not configured: {server_name}"})

        # ── Real implementation would use the MCP SDK here ──
        # from mcp import ClientSession, StdioServerParameters
        # async with ClientSession(...) as session:
        #     result = await session.call_tool(tool_name, tool_input)
        #     return json.dumps(result)
        #
        # For the interview: explain the interface, not the stub.
        print(f"  [MCP] → {server_name}.{tool_name}({json.dumps(tool_input, indent=2)})")
        return json.dumps({"status": "mcp_call_dispatched", "server": server_name, "tool": tool_name, "input": tool_input})


# ── Agent agentic loop ────────────────────────────────────────────────────────

def run_rca_agent(incident_id: str, alert_payload: dict) -> dict:
    """
    Main agentic loop. Claude drives the investigation — it decides which tools
    to call, in what order, and when it has gathered enough evidence to write the RCA.

    The loop continues until Claude returns stop_reason='end_turn' (no more tools needed).
    Max iterations guard against runaway loops in edge cases.
    """
    tools      = load_tools()
    dispatcher = MCPDispatcher()

    with open(SKILLS_FILE) as f:
        skills_config = yaml.safe_load(f)
    system_prompt = skills_config["system_prompt"]

    # Initial user message — the alert payload is everything Claude starts with.
    # It knows the incident ID, namespace, pod name, and alert time from PagerDuty.
    initial_message = f"""
PagerDuty incident {incident_id} has fired for an OOMKilled event.

Alert payload:
{json.dumps(alert_payload, indent=2)}

Please investigate this incident. Start by getting the pod status in the affected namespace,
then gather all relevant signals (describe, logs, memory metrics, traces, log correlation).
Once you have determined the root cause with confidence, generate a structured RCA and
post it to the PagerDuty incident.
"""

    messages = [{"role": "user", "content": initial_message}]

    print(f"\n{'='*60}")
    print(f"RCA Agent started — incident: {incident_id}")
    print(f"Service: {alert_payload.get('service_name', 'unknown')}")
    print(f"Namespace: {alert_payload.get('namespace', 'unknown')}")
    print(f"{'='*60}\n")

    max_iterations = 20
    iteration      = 0

    while iteration < max_iterations:
        iteration += 1
        print(f"[Iteration {iteration}] Calling Claude...")

        response = client.messages.create(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            system=system_prompt,
            tools=tools,
            messages=messages,
        )

        print(f"  stop_reason: {response.stop_reason}")

        # Append assistant response to conversation history
        messages.append({"role": "assistant", "content": response.content})

        # ── Agent finished — no more tools to call ─────────────────────────────
        if response.stop_reason == "end_turn":
            final_text = next(
                (block.text for block in response.content if hasattr(block, "text")),
                "Agent completed with no final text output."
            )
            print(f"\n[Agent complete]\n{final_text}")
            return {
                "status":      "complete",
                "incident_id": incident_id,
                "rca_summary": final_text,
                "iterations":  iteration,
            }

        # ── Agent wants to call tools ──────────────────────────────────────────
        if response.stop_reason == "tool_use":
            tool_results = []

            for block in response.content:
                if block.type != "tool_use":
                    continue

                tool_name  = block.name
                tool_input = block.input
                tool_id    = block.id

                print(f"  [Tool call] {tool_name}")
                result_str = dispatcher.call(tool_name, tool_input)

                tool_results.append({
                    "type":        "tool_result",
                    "tool_use_id": tool_id,
                    "content":     result_str,
                })

            # Return all tool results to Claude in one message
            messages.append({"role": "user", "content": tool_results})
            continue

        # Unexpected stop reason
        print(f"  [Warning] Unexpected stop_reason: {response.stop_reason}")
        break

    return {
        "status":      "max_iterations_reached",
        "incident_id": incident_id,
        "iterations":  iteration,
    }


# ── PagerDuty webhook handler ─────────────────────────────────────────────────

def handle_pagerduty_webhook(event: dict) -> dict:
    """
    Entry point for Cloud Run / Lambda invocation.
    PagerDuty sends a webhook payload when an alert fires.
    We extract the incident ID and alert context, then run the agent.

    PagerDuty webhook v3 format:
      event.messages[].event == "incident.triggered"
      event.messages[].incident.id == "P1A2B3C"
      event.messages[].incident.title == "OOMKilled: cart-service (webapp)"
    """
    messages = event.get("messages", [])
    if not messages:
        return {"status": "no_messages", "skipped": True}

    for msg in messages:
        if msg.get("event") not in ("incident.triggered", "incident.reopened"):
            continue

        incident    = msg.get("incident", {})
        incident_id = incident.get("id")
        title       = incident.get("title", "")

        # Only handle OOMKilled / CrashLoopBackOff alerts
        if not any(kw in title for kw in ("OOMKilled", "CrashLoopBackOff", "OOM", "memory")):
            print(f"Skipping non-OOM incident: {title}")
            continue

        # Extract context from the alert payload (populated by our CloudWatch/Cloud Monitoring alert)
        alert_details = incident.get("body", {}).get("details", {})
        alert_payload = {
            "incident_id":   incident_id,
            "title":         title,
            "service_name":  alert_details.get("service_name", "unknown"),
            "namespace":     alert_details.get("namespace", "webapp"),
            "pod_name":      alert_details.get("pod_name", ""),
            "cluster":       alert_details.get("cluster", "prod-webapp-gke"),
            "node_name":     alert_details.get("node_name", ""),
            "event_time":    alert_details.get("event_time", datetime.now(timezone.utc).isoformat()),
            "exit_code":     alert_details.get("exit_code", "137"),
        }

        return run_rca_agent(incident_id, alert_payload)

    return {"status": "no_matching_incidents"}


# ── Local test harness ────────────────────────────────────────────────────────

if __name__ == "__main__":
    # Simulate a PagerDuty webhook for local testing / interview demo
    mock_webhook = {
        "messages": [{
            "event": "incident.triggered",
            "incident": {
                "id": "P1A2B3C",
                "title": "OOMKilled: cart-service (webapp) — exit code 137",
                "body": {
                    "details": {
                        "service_name": "cart-service",
                        "namespace":    "webapp",
                        "pod_name":     "cart-service-7d9f8b-xk2pq",
                        "cluster":      "prod-webapp-gke",
                        "node_name":    "gke-prod-pool-us-central1-a-abc123",
                        "event_time":   "2026-06-08T14:23:00Z",
                        "exit_code":    "137",
                    }
                }
            }
        }]
    }

    result = handle_pagerduty_webhook(mock_webhook)
    print("\nFinal result:")
    print(json.dumps(result, indent=2))
