#!/usr/bin/env python3
"""
Terraform Plan Parser
Reads terraform show -json output and formats it as clean markdown
for GitHub PR comments
"""

import json
import sys
from datetime import datetime

def parse_plan(plan_file):
    with open(plan_file) as f:
        plan = json.load(f)

    added = []
    changed = []
    destroyed = []

    for change in plan.get("resource_changes", []):
        actions = change["change"]["actions"]
        module = change.get("module_address", "root")
        resource = change["address"]
        resource_type = change["type"]

        if actions == ["create"]:
            added.append({"resource": resource, "type": resource_type, "module": module})
        elif actions == ["update"]:
            changed.append({"resource": resource, "type": resource_type, "module": module})
        elif actions == ["delete"]:
            destroyed.append({"resource": resource, "type": resource_type, "module": module})
        elif actions == ["delete", "create"]:
            destroyed.append({"resource": resource, "type": resource_type, "module": module})
            added.append({"resource": resource, "type": resource_type, "module": module})

    return added, changed, destroyed

def format_markdown(added, changed, destroyed):
    lines = []
    lines.append("## Terraform Plan Summary")
    lines.append(f"> Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}")
    lines.append("")

    # Summary badge line
    lines.append(
        f"| 🟢 Add | 🟡 Change | 🔴 Destroy |"
    )
    lines.append("|--------|----------|---------|")
    lines.append(f"| {len(added)} | {len(changed)} | {len(destroyed)} |")
    lines.append("")

    # Added resources
    if added:
        lines.append("### 🟢 Resources to Add")
        lines.append("| Resource | Type | Module |")
        lines.append("|----------|------|--------|")
        for r in added:
            lines.append(f"| `{r['resource']}` | `{r['type']}` | `{r['module']}` |")
        lines.append("")

    # Changed resources
    if changed:
        lines.append("### 🟡 Resources to Change")
        lines.append("| Resource | Type | Module |")
        lines.append("|----------|------|--------|")
        for r in changed:
            lines.append(f"| `{r['resource']}` | `{r['type']}` | `{r['module']}` |")
        lines.append("")

    # Destroyed resources
    if destroyed:
        lines.append("### 🔴 Resources to Destroy")
        lines.append("| Resource | Type | Module |")
        lines.append("|----------|------|--------|")
        for r in destroyed:
            lines.append(f"| `{r['resource']}` | `{r['type']}` | `{r['module']}` |")
        lines.append("")

    lines.append("---")
    lines.append(f"**Total: {len(added) + len(changed) + len(destroyed)} resources affected**")

    return "\n".join(lines)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 parser.py <plan.json>")
        sys.exit(1)

    plan_file = sys.argv[1]
    added, changed, destroyed = parse_plan(plan_file)
    markdown = format_markdown(added, changed, destroyed)
    print(markdown)

    # Also write to file for GitHub Actions to pick up
    with open("plan_summary.md", "w") as f:
        f.write(markdown)

    print("\n✅ plan_summary.md written")
