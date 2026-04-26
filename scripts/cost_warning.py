#!/usr/bin/env python3
"""
Cost Warning Scanner — reads terraform plan JSON, flags expensive resource changes.
Outputs GitHub Actions warning/error annotations for visibility in PR checks.
Called by terraform-plan.yml CI workflow after terraform show -json.
"""

import json
import sys

# Resources that signal significant cost impact
EXPENSIVE_RESOURCE_TYPES = {
    "aws_nat_gateway": {
        "level": "WARNING",
        "message": "NAT Gateway = $0.045/hr (~$32/month) + $0.045/GB data. Verify lab_running intent.",
        "monthly_estimate": "$32+/month per gateway",
    },
    "aws_lb": {
        "level": "WARNING",
        "message": "Application Load Balancer = $0.008/hr (~$5.76/month) + LCU charges.",
        "monthly_estimate": "$5.76+/month",
    },
    "aws_db_instance": {
        "level": "WARNING",
        "message": "RDS instance created/modified — check instance class and multi_az setting.",
        "monthly_estimate": "Varies by class",
    },
    "aws_vpc_endpoint": {
        "level": "INFO",
        "message": "VPC Interface Endpoint = $0.01/hr/AZ. Gateway endpoints (S3) are FREE.",
        "monthly_estimate": "$7.30/month per endpoint per AZ",
    },
}

# EC2 instance sizes that are significantly more expensive than t3.micro
EXPENSIVE_INSTANCE_TYPES = {
    "m5.large", "m5.xlarge", "m5.2xlarge",
    "c5.large", "c5.xlarge", "c5.2xlarge",
    "r5.large", "r5.xlarge",
    "t3.large", "t3.xlarge", "t3.2xlarge",
}


def gha_annotation(level: str, message: str):
    """Emit a GitHub Actions workflow annotation."""
    # GitHub Actions picks up these prefixed lines and renders them in the UI
    prefix = f"::{level.lower()} title=Cost Warning::"
    print(f"{prefix}{message}")


def check_plan(plan_path: str) -> int:
    """
    Parse terraform plan JSON and emit cost warnings.
    Returns exit code: 0 = no issues, 1 = warnings found (doesn't fail CI).
    """
    try:
        with open(plan_path) as f:
            plan = json.load(f)
    except FileNotFoundError:
        print(f"::error::Plan file not found: {plan_path}")
        return 1
    except json.JSONDecodeError as e:
        print(f"::error::Failed to parse plan JSON: {e}")
        return 1

    resource_changes = plan.get("resource_changes", [])
    warnings_found = 0
    rds_multi_az_found = False

    print("\n" + "="*60)
    print("💰 COST GOVERNANCE SCAN")
    print("="*60)

    for change in resource_changes:
        action = change.get("change", {}).get("actions", [])
        resource_type = change.get("type", "")
        resource_name = change.get("address", "")

        # Only care about creates and updates — deletes reduce cost
        if "create" not in action and "update" not in action:
            continue

        # --- Check expensive resource types ---
        if resource_type in EXPENSIVE_RESOURCE_TYPES:
            info = EXPENSIVE_RESOURCE_TYPES[resource_type]
            level = info["level"]
            msg = f"{resource_name} — {info['message']} Est: {info['monthly_estimate']}"
            print(f"\n  [{level}] {msg}")
            gha_annotation(level, msg)
            warnings_found += 1

        # --- Check EC2 launch templates for large instance types ---
        if resource_type == "aws_launch_template":
            after = change.get("change", {}).get("after", {}) or {}
            instance_type = after.get("instance_type", "")
            if instance_type in EXPENSIVE_INSTANCE_TYPES:
                msg = (
                    f"{resource_name} uses {instance_type}. "
                    f"Large instances are expensive. t3.micro = free tier eligible."
                )
                print(f"\n  [WARNING] {msg}")
                gha_annotation("warning", msg)
                warnings_found += 1

        # --- Check RDS for Multi-AZ being enabled ---
        if resource_type == "aws_db_instance":
            after = change.get("change", {}).get("after", {}) or {}
            if after.get("multi_az") is True:
                rds_multi_az_found = True
                msg = (
                    f"{resource_name} has multi_az=true — "
                    f"this doubles RDS cost (standby replica in second AZ)."
                )
                print(f"\n  [WARNING] {msg}")
                gha_annotation("warning", msg)
                warnings_found += 1

    # Summary
    print("\n" + "="*60)
    if warnings_found == 0:
        print("✅ No cost concerns found in this plan.")
    else:
        print(f"⚠️  {warnings_found} cost concern(s) found. Review before merging.")
        if rds_multi_az_found:
            print("   💡 RDS multi_az doubles your DB cost — only enable in production.")
    print("="*60 + "\n")

    # Exit 0 so CI doesn't fail — warnings are advisory, not blocking
    # Change to exit(1) if you want to block PRs with cost concerns
    return 0


if __name__ == "__main__":
    plan_file = sys.argv[1] if len(sys.argv) > 1 else "plan.json"
    sys.exit(check_plan(plan_file))
