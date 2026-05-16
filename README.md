# Multi-AZ Web Application on AWS

A production-grade, resilient web application deployed on AWS across two Availability Zones using Terraform. This project demonstrates enterprise-level infrastructure-as-code practices with a unique **cost control feature**: a `lab_running` boolean that toggles the entire billable stack on/off without destroying the VPC skeleton.

## 🎯 Key Features

- **Multi-AZ Deployment** — High availability across two AWS Availability Zones (us-east-1a, us-east-1b by default)
- **Cost Control Toggle** — `lab_running=false` reduces monthly cost to ~$2-5, `lab_running=true` scales to ~$50-80
- **Three-Tier Architecture** — ALB → EC2 Auto Scaling Group → PostgreSQL RDS
- **Infrastructure as Code** — 100% Terraform, with modular design
- **Security First** — No SSH access, SSM Session Manager only; encrypted RDS; VPC endpoints for private API calls
- **Observability** — CloudWatch dashboards, alarms, and SNS alerts
- **Cost Monitoring** — AWS Budget alerts + Python CI cost scanner

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Internet Traffic                      │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────▼────────────┐
         │   Application Load     │
         │     Balancer (ALB)     │ ← Public Subnets (us-east-1a, us-east-1b)
         │  Health Check: /health │
         └───────────┬────────────┘
                     │
         ┌───────────▼────────────┐
         │  Auto Scaling Group    │
         │  (t3.micro, nginx)     │ ← Private Subnets
         │  Desired: 2            │    (us-east-1a, us-east-1b)
         │  Min: 1, Max: 4        │
         └───────────┬────────────┘
                     │
         ┌───────────▼────────────┐
         │  PostgreSQL 16.3 RDS   │
         │   (db.t3.micro)        │ ← Database Subnets
         │  Multi-AZ capable      │    (us-east-1a, us-east-1b)
         └────────────────────────┘
                     │
         ┌───────────▼────────────┐
         │ AWS Secrets Manager    │
         │ (DB credentials)       │
         └────────────────────────┘
```

## 📁 Repository Structure

```
multi-az-webapp/
├── main.tf                          # Root module orchestration
├── variables.tf                     # Root-level input variables
├── outputs.tf                       # ALB DNS, RDS endpoint, SNS ARNs
├── provider.tf                      # AWS provider + default tags
├── backend.tf                       # Terraform remote state (S3)
├── terraform.tfvars                 # Default variable overrides
├── locals.tf                        # (empty placeholder)
│
├── modules/
│   ├── vpc/                         # VPC, subnets, gateways
│   ├── security_groups/             # Three-tier firewall rules
│   ├── iam/                         # EC2 instance role + profile
│   ├── alb/                         # Application Load Balancer
│   ├── asg/                         # Auto Scaling Group + launch template
│   ├── rds/                         # PostgreSQL RDS instance
│   ├── vpc_endpoints/               # S3 gateway + interface endpoints
│   ├── cloudwatch/                  # Logs, alarms, dashboard
│   ├── budget/                      # Monthly cost guardrail
│   └── secrets/                     # (stub for future credential management)
│
├── scripts/
│   ├── cost_warning.py              # CI cost scanner → GHA annotations
│   └── parser.py                    # Terraform plan → PR markdown comment
│
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml       # Triggered on PRs to main
│       └── terraform-destroy.yml    # Manual workflow_dispatch
│
├── .gitignore                       # Terraform state, vars files
├── CLAUDE.md                        # Detailed technical documentation
└── README.md                        # This file
```

## 🚀 Quick Start

### Prerequisites

- [Terraform >= 1.14](https://www.terraform.io/downloads)
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- AWS credentials configured (IAM user or temporary credentials)

### 1. Clone the Repository

```bash
git clone https://github.com/garyrayat/multi-az-webapp.git
cd multi-az-webapp
```

### 2. Initialize Terraform

```bash
terraform init
```

This connects to the S3 remote state backend. You may need to create the backend bucket first:

```bash
# Create S3 bucket for state (replace with your AWS account ID)
aws s3 mb s3://multi-az-webapp-tfstate-<YOUR_ACCOUNT_ID> \
  --region us-east-1 --create-bucket-configuration LocationConstraint=us-east-1
```

### 3. Plan the Deployment (Lab Mode — Cost: $2-5/month)

```bash
terraform plan \
  -var="lab_running=false" \
  -var='alert_emails=["you@example.com"]'
```

### 4. Apply (Deploy the VPC Skeleton)

```bash
terraform apply \
  -var="lab_running=false" \
  -var='alert_emails=["you@example.com"]'
```

At this point, you have a VPC, subnets, security groups, and IAM roles — all costing ~$2-5/month.

### 5. Bring Up the Full Stack (Cost: ~$50-80/month)

```bash
terraform apply \
  -var="lab_running=true" \
  -var='alert_emails=["you@example.com"]'
```

This deploys:
- NAT Gateways (×2)
- Application Load Balancer
- EC2 instances (via Auto Scaling Group)
- PostgreSQL RDS instance
- VPC Endpoints (SSM, CloudWatch, Secrets Manager)
- CloudWatch alarms and dashboard

### 6. Access the Application

```bash
# Get the ALB DNS name
terraform output alb_dns_name

# Paste the URL in your browser
curl http://<alb-dns-name>
```

You'll see a page showing which Availability Zone the instance is running in, confirming multi-AZ routing.

### 7. Connect to EC2 Instances

No SSH keys — use AWS Systems Manager Session Manager:

```bash
# List instances
aws ec2 describe-instances --filters "Name=tag:Environment,Values=dev"

# Start a shell session
aws ssm start-session --target <instance-id>
```

### 8. Query Database Credentials

```bash
aws secretsmanager get-secret-value \
  --secret-id multi-az-webapp/dev/db-credentials \
  --query SecretString --output text | jq .
```

### 9. Tear Down (Keep VPC, Destroy Billable Resources)

```bash
terraform apply -var="lab_running=false"
```

This keeps the VPC skeleton but destroys NAT Gateways, ALB, EC2, RDS, and endpoints.

### 10. Complete Cleanup

```bash
terraform destroy
```

---

## 🔧 The `lab_running` Flag

The master cost control switch. Default is `false` in `terraform.tfvars`.

| Resource | `lab_running=false` | `lab_running=true` |
|----------|---------------------|-------------------|
| VPC, subnets, IGW | ✅ Deployed | ✅ Deployed |
| Security groups | ✅ Deployed | ✅ Deployed |
| IAM role + profile | ✅ Deployed | ✅ Deployed |
| S3 gateway endpoint | ✅ Deployed | ✅ Deployed |
| Budget + SNS | ✅ Deployed | ✅ Deployed |
| CloudWatch log groups | ✅ Deployed | ✅ Deployed |
| **NAT Gateways (×2)** | ❌ Destroyed | ✅ Created |
| **ALB + target group** | ❌ Destroyed | ✅ Created |
| **EC2 ASG** | 0/0/0 (stopped) | 2/1/4 (running) |
| **RDS instance** | ❌ Destroyed | ✅ Created |
| **Secrets Manager secret** | ❌ Destroyed | ✅ Created |
| **Interface VPC Endpoints** | ❌ Destroyed | ✅ Created |
| **CloudWatch alarms** | ❌ Destroyed | ✅ Created |
| **CloudWatch dashboard** | ❌ Destroyed | ✅ Created |

**Estimated Monthly Costs:**
- `lab_running=false`: ~$2–5/month (VPC, log groups, budget alerts)
- `lab_running=true`: ~$50–80/month (NAT ×2, ALB, EC2, RDS, endpoints)

---

## 📚 Module Details

### VPC Module (`modules/vpc`)

Complete network foundation. Always deployed.

**Key Resources:**
- `aws_vpc` — 10.0.0.0/16, DNS hostnames enabled
- `aws_internet_gateway` — attached to VPC
- Public subnets (10.0.1.0/24, 10.0.2.0/24) — ALB lives here
- Private subnets (10.0.10.0/24, 10.0.11.0/24) — EC2 app tier
- Database subnets (10.0.20.0/24, 10.0.21.0/24) — RDS lives here
- NAT Gateways (×2, only when `lab_running=true`)
- Route tables (public, private per AZ, database)
- DB subnet group (required by RDS)

### Security Groups Module (`modules/security_groups`)

Three-tier firewall rules. Always deployed (SGs are free).

- **ALB SG**: inbound 80/443 from 0.0.0.0/0
- **App SG**: inbound 80 only from ALB SG
- **Database SG**: inbound 5432 only from App SG

No SSH (port 22) anywhere — access via SSM Session Manager only.

### IAM Module (`modules/iam`)

EC2 instance role and profile. Always deployed.

**Attached Policies:**
- `AmazonSSMManagedInstanceCore` — SSM Session Manager
- `CloudWatchAgentServerPolicy` — CloudWatch metrics/logs
- `SecretsManagerReadWrite` — read DB credentials at runtime

### ALB Module (`modules/alb`)

Application Load Balancer. Gated: `count = var.lab_running ? 1 : 0`.

**Resources:**
- `aws_lb` — internet-facing, spans all public subnets
- `aws_lb_target_group` — port 80 HTTP, `/health` health check
- `aws_lb_listener` — port 80 → forward to target group

### ASG Module (`modules/asg`)

Auto Scaling Group. Launch template always exists; capacity scales to 0 when `lab_running=false`.

**Key Features:**
- AMI: Amazon Linux 2023 (dynamic lookup)
- Instance type: t3.micro (configurable)
- Desired/Min/Max: 2/1/4 (when lab running) or 0/0/0 (when lab off)
- User data: bootstraps nginx, creates `/health` endpoint
- Health check type: ELB (30s interval)

### RDS Module (`modules/rds`)

PostgreSQL 16.3 with Secrets Manager credentials. Fully gated: `count = var.lab_running ? 1 : 0`.

**Key Features:**
- Engine: PostgreSQL 16.3
- Instance class: db.t3.micro
- Storage: gp3, 20 GB allocated, auto-scales to 100 GB
- Encrypted: always
- Publicly accessible: never
- Password: generated by `random_password`, stored in Secrets Manager (never in state/tfvars)
- Multi-AZ: configurable per environment

### VPC Endpoints Module (`modules/vpc_endpoints`)

Reduces NAT Gateway data transfer charges.

**S3 Gateway Endpoint** — always deployed, free:
- Injects routes into all private route tables
- S3 traffic from EC2 bypasses NAT entirely

**Interface Endpoints** — `for_each = var.lab_running ? {...} : {}`:
- `ssm`, `ec2messages`, `ssmmessages` — SSM Session Manager
- `logs` — CloudWatch Logs Agent
- `secretsmanager` — Secrets Manager reads
- All use `private_dns_enabled = true`

### CloudWatch Module (`modules/cloudwatch`)

Observability layer.

**Always Deployed:**
- Log groups: `/multi-az-webapp/dev/app`, `/multi-az-webapp/dev/nginx` (7-day retention)
- SNS topic for operational alarms

**When `lab_running=true`:**
- Alarm: `asg-cpu-high` — EC2 CPU > 80% for 2× 5-minute periods
- Alarm: `alb-unhealthy-hosts` — any unhealthy targets (threshold 0)
- Alarm: `rds-cpu-high` — RDS CPU > 80% for 2× 5-minute periods
- Dashboard: 4 widgets (EC2 CPU, ALB requests, ALB health, RDS CPU)

### Budget Module (`modules/budget`)

Monthly cost guardrail. Always deployed (budget + SNS are free).

- Monthly budget: $100 (default, configurable)
- Alerts: 50% ($50) and 80% ($80) thresholds
- Notifications: SNS email alerts (recipients must confirm subscription)

---

## 🔒 Security Highlights

1. **No SSH Access** — All instances access via SSM Session Manager only
2. **Secrets Management** — DB credentials stored in AWS Secrets Manager, not in Terraform state
3. **Encrypted Database** — RDS storage always encrypted with AWS KMS
4. **Private Database Tier** — RDS in private subnets, no internet access
5. **VPC Endpoints** — Private DNS for API calls (S3, SSM, CloudWatch, Secrets Manager)
6. **Default Tags** — All resources tagged for cost allocation and governance
7. **Three-Tier SGs** — ALB → App → Database, SG references (not CIDRs) for least privilege

---

## 📊 Observability

### CloudWatch Dashboard

View in AWS Console → CloudWatch → Dashboards:

```
Dashboard: multi-az-webapp-dev
├── EC2 CPU Usage (from ASG)
├── ALB Request Count
├── ALB Healthy/Unhealthy Hosts
└── RDS CPU Usage
```

### CloudWatch Alarms

All alarms publish to an SNS topic. Subscribe in AWS Console → SNS → Topics.

```
Alarms (when lab_running=true):
├── asg-cpu-high → SNS topic
├── alb-unhealthy-hosts → SNS topic
└── rds-cpu-high → SNS topic
```

### CloudWatch Logs

Log groups created automatically:

```
/multi-az-webapp/dev/app          ← Application logs (7-day retention)
/multi-az-webapp/dev/nginx        ← nginx access logs (7-day retention)
```

---

## 💰 Cost Management

### Budget Alerts

```
Budget: multi-az-webapp-dev
├── Limit: $100/month
├── Alert 1: $50 (50%)
└── Alert 2: $80 (80%)
```

Subscribers receive SNS email alerts before budget is exceeded.

### CI Cost Scanner

GitHub Actions runs `scripts/cost_warning.py` on every PR to `main`:

```bash
# Example output (in PR):
⚠️ WARNING: aws_nat_gateway will cost ~$32/month (×2)
⚠️ WARNING: aws_lb will cost ~$16/month
⚠️ WARNING: aws_db_instance will cost ~$15/month
```

---

## 🔄 GitHub Actions Workflows

### `terraform-plan.yml` — PR Check

Triggered on every PR to `main`. Steps:

1. ✅ Checkout code
2. ✅ Setup Terraform (v1.14.0)
3. ✅ Format check (`terraform fmt -check -recursive`)
4. ✅ Security scan (tfsec)
5. ✅ Syntax validation (`terraform validate`)
6. ✅ Plan with `lab_running=false` (safety default)
7. ✅ Cost warning analysis
8. ✅ Post markdown comment with plan summary

**Required Secrets:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### `terraform-destroy.yml` — Manual Destroy

Manual `workflow_dispatch` trigger from GitHub Actions tab.

**Safety Gate:** User must type `DESTROY` in confirmation input or job fails immediately.

Steps:
1. Validate confirmation string
2. Apply with `lab_running=false` (destroys NAT/ALB/EC2/RDS but keeps VPC skeleton)
3. List remaining resources
4. Post summary to GitHub Actions job summary

---

## 🐍 Python Scripts

### `scripts/cost_warning.py`

Reads `terraform plan -json` output and emits GitHub Actions annotations for expensive resources:

| Resource Type | Alert Level |
|---|---|
| `aws_nat_gateway` | ⚠️ WARNING |
| `aws_lb` | ⚠️ WARNING |
| `aws_db_instance` | ⚠️ WARNING |
| `aws_vpc_endpoint` | ℹ️ INFO |
| Large EC2 (m5, c5, r5, t3.large+) | ⚠️ WARNING |
| RDS Multi-AZ | ⚠️ WARNING |

### `scripts/parser.py`

Reads `terraform plan -json` and outputs a formatted markdown PR comment with:

- **Risk Badge**: LOW/MEDIUM/HIGH based on destroy/replace counts
- **Summary Table**: add/change/destroy/replace counts
- **Per-Module Sections**: grouped by Terraform module in collapsible `<details>` blocks
- **Resource Icons**: per-resource emoji (EC2 🖥️, RDS 🗄️, ALB ⚖️, etc.)

---

## 📋 Common Operations

### Plan Only (No Apply)

```bash
terraform plan -var="lab_running=true" -var='alert_emails=["you@example.com"]'
```

### Apply with Auto-Approval

```bash
terraform apply \
  -var="lab_running=true" \
  -var='alert_emails=["you@example.com"]' \
  -auto-approve
```

### Validate Syntax

```bash
terraform validate
```

### Format Code

```bash
terraform fmt -recursive
```

### Show Current State

```bash
terraform state list
terraform state show aws_vpc.main  # or any resource
```

### Refresh State from AWS

```bash
terraform refresh
```

### Import Existing AWS Resources

```bash
terraform import aws_instance.example i-xxxxxxxxx
```

---

## 🏗️ Production Hardening Checklist

Before deploying to production, consider:

- [ ] Enable `deletion_protection = true` on RDS
- [ ] Set `skip_final_snapshot = false` on RDS
- [ ] Set `recovery_window_in_days = 30` on Secrets Manager secret
- [ ] Enable `multi_az = true` on RDS
- [ ] Add HTTPS listener (port 443) to ALB with ACM certificate
- [ ] Restrict ALB security group to specific CIDRs (not 0.0.0.0/0)
- [ ] Scope IAM `SecretsManagerReadWrite` policy to specific secret ARN
- [ ] Enable RDS automated minor version upgrades
- [ ] Enable RDS automated backups (retention > 1 day)
- [ ] Enable S3 versioning on Terraform state bucket
- [ ] Configure CloudTrail for audit logging
- [ ] Set up AWS Config for compliance monitoring
- [ ] Implement backup/recovery testing

---

## 🚨 Troubleshooting

### Terraform Init Fails — Backend Not Found

```bash
Error: Error reading remote state

The remote state is missing or malformed.
```

**Solution:** Create the S3 backend bucket:

```bash
aws s3 mb s3://multi-az-webapp-tfstate-<ACCOUNT_ID> --region us-east-1
aws s3api put-bucket-versioning \
  --bucket multi-az-webapp-tfstate-<ACCOUNT_ID> \
  --versioning-configuration Status=Enabled
```

### EC2 Instances Can't Reach Secrets Manager

```bash
Error: RequestError: Unable to locate credentials
```

**Solution:** Verify the EC2 instance profile has `SecretsManagerReadWrite` policy and VPC endpoints are deployed:

```bash
terraform apply -var="lab_running=true"
```

### ALB Targets Unhealthy

```
Target: unhealthy
```

**Solution:** Check security groups and user_data.sh:

```bash
# List EC2 instances
aws ec2 describe-instances --filters "Name=tag:Environment,Values=dev"

# Connect to instance and check nginx
aws ssm start-session --target <instance-id>
# Then: sudo systemctl status nginx
```

### Database Password Not in Secrets Manager

```bash
Error: secret does not exist
```

**Solution:** Ensure `lab_running=true` and RDS is deployed:

```bash
terraform apply -var="lab_running=true"
aws secretsmanager list-secrets --filters Key=name,Values=multi-az-webapp
```

---

## 📖 Documentation

For deeper technical details, see **[CLAUDE.md](./CLAUDE.md)**, which covers:

- Detailed module architecture
- Remote state configuration
- Default tagging strategy
- Implementation patterns (count, for_each, try, coalesce)
- Cost estimation breakdown

---

## 🤝 Contributing

1. Create a feature branch: `git checkout -b feature/my-feature`
2. Make your changes and test: `terraform plan`
3. Format code: `terraform fmt -recursive`
4. Commit: `git commit -am "Add feature X"`
5. Push: `git push origin feature/my-feature`
6. Open a Pull Request to `main`

GitHub Actions will automatically run `terraform-plan.yml`:
- Format check
- Security scan (tfsec)
- Cost analysis
- Markdown comment on PR

---

## 📝 License

This project is provided as-is. See the repository for license details.

---

## 👤 Author

Created by **garyrayat**. For questions or issues, open a GitHub issue.

---

## 🎓 Learning Resources

- [Terraform Best Practices](https://www.terraform.io/cloud-docs/recommended-practices)
- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-best-practices.html)
- [AWS RDS Security](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.html)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)

---

**Last Updated:** May 16, 2026
