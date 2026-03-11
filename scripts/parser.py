#!/usr/bin/env python3
"""
Terraform Plan Parser — Enhanced GitHub PR Formatter
Parses terraform show -json output into a rich markdown PR comment
"""

import json
import sys
from datetime import datetime
from collections import defaultdict

# Emoji map for resource types
RESOURCE_ICONS = {
    "aws_vpc":                       "🌐",
    "aws_subnet":                    "🔲",
    "aws_internet_gateway":          "🚪",
    "aws_nat_gateway":               "🔀",
    "aws_eip":                       "📍",
    "aws_route_table":               "🗺️",
    "aws_route_table_association":   "🔗",
    "aws_db_subnet_group":           "🗄️",
    "aws_security_group":            "🛡️",
    "aws_security_group_rule":       "📋",
    "aws_lb":                        "⚖️",
    "aws_lb_listener":               "👂",
    "aws_lb_target_group":           "🎯",
    "aws_autoscaling_group":         "📈",
    "aws_launch_template":           "📄",
    "aws_iam_role":                  "🔑",
    "aws_iam_instance_profile":      "👤",
    "aws_iam_role_policy_attachment":"📎",
    "aws_db_instance":               "🗃️",
    "aws_cloudwatch_metric_alarm":   "🔔",
    "aws_secretsmanager_secret":     "🔒",
}

ACTION_CONFIG = {
    "create":  {"emoji": "🟢", "label": "Add",     "color": "green"},
    "update":  {"emoji": "🟡", "label": "Change",  "color": "yellow"},
    "delete":  {"emoji": "🔴", "label": "Destroy", "color": "red"},
    "replace": {"emoji": "🟠", "label": "Replace", "color": "orange"},
}

def get_icon(resource_type):
    return RESOURCE_ICONS.get(resource_type, "📦")

def get_action(actions):
    if actions == ["create"]:             return "create"
    if actions == ["update"]:             return "update"
    if actions == ["delete"]:             return "delete"
    if actions == ["delete", "create"]:   return "replace"
    return "update"

def parse_plan(plan_file):
    with open(plan_file) as f:
        plan = json.load(f)

    changes = defaultdict(list)

    for change in plan.get("resource_changes", []):
        actions = change["change"]["actions"]
        if actions == ["no-op"]:
            continue

        module = change.get("module_address", "root") or "root"
        action = get_action(actions)

        changes[action].append({
            "resource":  change["address"],
            "type":      change["type"],
            "module":    module,
            "icon":      get_icon(change["type"]),
            "name":      change["name"],
        })

    return changes

def group_by_module(resources):
    grouped = defaultdict(list)
    for r in resources:
        grouped[r["module"]].append(r)
    return grouped

def format_module_table(resources):
    lines = []
    lines.append("| Icon | Resource | Type |")
    lines.append("|------|----------|------|")
    for r in resources:
        lines.append(f"| {r['icon']} | `{r['resource']}` | `{r['type']}` |")
    return "\n".join(lines)

def risk_level(changes):
    destroys = len(changes.get("delete", []))
    replaces = len(changes.get("replace", []))
    if destroys > 5 or replaces > 3:   return "🔴 HIGH"
    if destroys > 0 or replaces > 0:   return "🟡 MEDIUM"
    return "🟢 LOW"

def format_markdown(changes, plan_file):
    adds     = changes.get("create",  [])
    updates  = changes.get("update",  [])
    destroys = changes.get("delete",  [])
    replaces = changes.get("replace", [])
    total    = len(adds) + len(updates) + len(destroys) + len(replaces)
    risk     = risk_level(changes)
    now      = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

    lines = []

    # ── Header ──────────────────────────────────────────
    lines.append("# 🏗️ Terraform Plan Summary")
    lines.append("")
    lines.append(f"| 🕐 Generated | ⚠️ Risk Level | 📦 Total Changes |")
    lines.append("|-------------|--------------|-----------------|")
    lines.append(f"| `{now}` | {risk} | `{total} resources` |")
    lines.append("")

    # ── Summary Counts ───────────────────────────────────
    lines.append("## 📊 Change Overview")
    lines.append("")
    lines.append("| | Action | Count |")
    lines.append("|--|--------|-------|")
    lines.append(f"| 🟢 | **Add** | `{len(adds)}` |")
    lines.append(f"| 🟡 | **Change** | `{len(updates)}` |")
    lines.append(f"| 🔴 | **Destroy** | `{len(destroys)}` |")
    lines.append(f"| 🟠 | **Replace** | `{len(replaces)}` |")
    lines.append("")

    # ── Resources by Action ──────────────────────────────
    sections = [
        ("create",  "🟢 Resources to Add",     adds),
        ("update",  "🟡 Resources to Change",   updates),
        ("delete",  "🔴 Resources to Destroy",  destroys),
        ("replace", "🟠 Resources to Replace",  replaces),
    ]

    for action, title, resources in sections:
        if not resources:
            continue

        lines.append(f"## {title}")
        lines.append("")

        # Group by module with collapsible sections
        grouped = group_by_module(resources)
        for module, items in sorted(grouped.items()):
            lines.append(f"<details>")
            lines.append(f"<summary><b>📁 {module}</b> — {len(items)} resource(s)</summary>")
            lines.append("")
            lines.append(format_module_table(items))
            lines.append("")
            lines.append("</details>")
            lines.append("")

    # ── Footer ───────────────────────────────────────────
    lines.append("---")
    lines.append("")
    lines.append("> ⚡ **Auto-generated by Terraform Plan Parser**")
    lines.append("> Review all changes carefully before merging.")
    lines.append("> 🔴 Destroy actions are irreversible.")

    return "\n".join(lines)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 parser.py <plan.json>")
        sys.exit(1)

    plan_file = sys.argv[1]
    changes   = parse_plan(plan_file)
    markdown  = format_markdown(changes, plan_file)

    with open("plan_summary.md", "w") as f:
        f.write(markdown)

    print(markdown)
    print("\n✅ plan_summary.md written")
