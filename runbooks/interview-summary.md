# Principal-Level Interview Summary
## AI-Driven SRE Automation Platform — Enterprise Portfolio

---

## The One-Line Pitch

> "I architected and delivered an AI-native SRE automation platform that embedded Claude-based agents into the incident lifecycle — from alert triage through root cause analysis, runbook generation, and ITSM ticket creation — reducing mean time to resolution by eliminating the manual steps between detection and action."

---

## What I Actually Built (and the Mental Model Behind It)

Most teams treat AI as a chat interface bolted onto their tools. What I built was the opposite:
**the AI is the orchestration layer, and the enterprise tools become its hands.**

The architecture centres on MCP (Model Context Protocol) — an open protocol that lets an AI agent
call external tools with structured inputs and outputs. The agent process can run anywhere:
as a sidecar in GKE, as a Lambda function, or as a local daemon during development. The protocol
is identical regardless of runtime. What matters is the **skill definitions** — declarative files
that describe what each tool does, what inputs it needs, and what it returns. Once the skills are
defined, the agent can reason across all of them simultaneously.

In production at THD this ran inside GKE. For development and iteration I ran the MCP server
as a local process — same skills, same behaviour, just a different deployment target.

---

## Platform Capabilities I Delivered

### 1. Intelligent Infrastructure Provisioning with Cost Governance

**What I built:**  
A Terraform-based multi-AZ infrastructure platform on AWS/EKS with an embedded cost governance
pipeline. Every pull request triggers a static analysis pass that parses the Terraform plan JSON,
identifies high-cost resource patterns (NAT Gateways, ALB, RDS Multi-AZ), and surfaces annotated
warnings directly in the PR — before any engineer can approve and merge.

**The engineering decisions that mattered:**
- `lab_running` boolean as a single-flag cost switch — all billable resources behind one variable,
  preserving the VPC/IAM skeleton (~$3/month) so the environment can be restored in minutes
- S3 native state locking (`use_lockfile = true`) removing the DynamoDB dependency
- Default tags propagated via the provider block so every resource is cost-attributed without
  per-resource tag blocks

**Interview framing:**
> "I introduced a cost governance gate into the IaC pipeline. The Terraform plan is converted to
> structured JSON and analysed by a Python scanner that emits GitHub Actions annotations.
> Engineering teams get cost impact visible at PR review time, not on the monthly bill.
> We caught a $960/year NAT Gateway misconfiguration before it ever touched production."

---

### 2. AI-Assisted Incident Response — The SRE Loop

**What I built at THD (and the pattern I replicated here):**

The core loop:

```
Alert fires (PagerDuty / CloudWatch)
        ↓
Agent receives alert context via MCP tool call
        ↓
Agent executes diagnostic sequence:
  - kubectl describe / logs / events
  - CloudWatch log query
  - Metrics correlation (CPU, memory, error rate)
        ↓
Agent determines root cause + confidence level
        ↓
Agent generates structured output:
  - Runbook in Markdown (committed to repo)
  - ServiceNow incident record (ITSM ticket)
  - PagerDuty note with RCA summary
  - Rundeck job trigger if remediation is safe to automate
        ↓
On-call engineer reviews — approves or overrides
```

**The specific incident pattern I documented here:**

Pod `memory-hog` entered `CrashLoopBackOff`. The agent:
1. Listed pods in the `webapp` namespace
2. Described the crashing pod — found `Last State: OOMKilled`, Exit Code 137
3. Read current and previous logs — confirmed `signal 9` (SIGKILL from kernel OOM killer)
4. Pulled the deployment manifest — confirmed `limits.memory: 10Mi` vs `--vm-bytes 128M` in the command
5. Generated a full runbook with diagnosis steps, root cause explanation, two fix options, and prevention guidance

**Interview framing:**
> "What changed for on-call engineers was that when they got paged at 2am, they opened the
> incident and the root cause analysis was already there — not a guess, a structured diagnosis
> with the exact kubectl commands that confirmed it, the specific line in the manifest that caused
> it, and two concrete fix options. The engineer's job became reviewing and approving, not
> investigating from scratch. We measured a 60–70% reduction in time-to-diagnosis on the
> categories of incidents we had skill coverage for."

---

### 3. Automated Runbook Generation and ITSM Integration

**What I built:**

The runbook is not written after the incident — it is generated during the incident, from live
diagnostic data. Key design choices:

- Runbooks are committed to the infrastructure repo (GitOps) — they live next to the code that
  caused the incident
- Structured sections: Symptoms → Diagnosis commands → Root Cause → Fix options → Verification → Prevention
- The same agent that generates the runbook also creates the ServiceNow CMDB record and links
  it to the affected configuration item
- Rundeck integration: if the remediation is categorised as low-risk and deterministic
  (e.g. bump a memory limit, restart a deployment), the agent can trigger the Rundeck job directly
  after human approval via a Slack reaction

**At THD specifically:**
- ServiceNow ticket creation with auto-populated fields: affected CI, priority, category, short description, work notes pre-filled with the RCA
- PagerDuty incident notes pushed back to the responder so they have context without leaving their incident view
- BPMS (process management) integration for change records when the fix requires a prod change window

---

### 4. Production Readiness Reviews (PRR) — AI-Assisted Checklist Generation

**What I built:**

Before any service is promoted to production, it must pass a PRR. I automated the evidence
collection phase:

The agent reads the service's Kubernetes manifests, Terraform modules, and recent deployment
history and generates a pre-filled PRR document covering:

| PRR Category | What the agent checks |
|---|---|
| Resource management | requests/limits set on every container, HPA configured |
| Observability | log groups exist, key alarms defined, dashboard present |
| Resilience | multi-AZ deployment, PodDisruptionBudget, health checks configured |
| Security | no privileged containers, no NodePort services, IRSA instead of instance roles |
| Cost | cost tags present, budget alerts active, no oversized instances |
| Runbooks | runbooks exist in repo for top 5 failure modes |

What used to take a senior engineer half a day to compile now takes 3 minutes, and the agent
flags gaps rather than the PRR reviewer having to hunt for them.

---

## Translating This to Equinix / Data Centre / Network Engineering

The patterns are identical. The tools change, the agent skills change, the protocol does not.

### The Network Equivalent of OOMKilled → CrashLoopBackOff

| K8s / Cloud | Network / DC Equivalent |
|---|---|
| Pod OOMKilled | BGP session dropping due to hold-timer expiry or route table overflow |
| CrashLoopBackOff | BGP peer repeatedly re-establishing and flapping |
| Memory limit too low | TCAM table exhausted — hardware can't install more routes |
| `kubectl describe pod` | `show bgp neighbors <ip>`, `show ip ospf neighbor detail` |
| Container logs | Syslog stream from the router / switch |
| CloudWatch alarm | NetFlow anomaly or BGP notification trap via SNMP/streaming telemetry |
| Runbook committed to repo | SOP in Confluence / Rundeck runbook for BGP peer flap response |

### Use Cases I Would Implement at Equinix

**BGP Peer Flap RCA:**
- Agent receives SNMP trap or streaming telemetry event: BGP peer down on edge router
- Agent SSH/NETCONF to device, collects `show bgp neighbors`, `show log`, interface counters
- Agent correlates: is this a hold-timer issue (keepalive missed)? A physical layer event (interface errors)? A route policy change (prefix limit hit)?
- Agent generates RCA + ServiceNow ticket + notifies NOC via PagerDuty with structured note

**OSPF Adjacency Loss:**
- Agent detects OSPF adjacency drop event
- Collects: `show ip ospf neighbor`, `show ip ospf interface`, syslog for hello timer mismatches
- Determines if it's MTU mismatch, area type mismatch, auth failure, or physical
- Generates change record for the config fix if it's a policy drift

**IS-IS Overload Bit / Route Leak:**
- Agent monitors for unexpected route redistribution events
- Pulls route tables from affected devices via NETCONF/gNMI
- Compares against golden config in Git
- Flags deviation, creates ITSM ticket, optionally triggers Rundeck rollback job

**Capacity / TCAM Planning:**
- Agent scheduled to run weekly: pulls route table sizes from all edge devices
- Compares against TCAM capacity thresholds
- Generates capacity report and creates proactive ServiceNow change ticket before the table fills

**The framing for Equinix interviews:**
> "The same MCP-based agent framework I used for Kubernetes incident automation maps directly
> to network operations. The skills change — instead of kubectl I'm calling NETCONF or gNMI,
> instead of Kubernetes events I'm consuming BGP notification traps — but the agent's reasoning
> loop is the same. Detect → collect evidence → correlate → diagnose → generate action.
> The value is the same: the NOC engineer gets a structured RCA instead of a blank screen at 3am."

---

## The Architecture That Makes This Reusable

```
┌─────────────────────────────────────────────────────────┐
│                   Claude Agent (AI Core)                 │
│  - Receives alert context or user query                  │
│  - Reasons across all available skills                   │
│  - Decides which tools to call and in what sequence      │
│  - Synthesises findings into structured output           │
└───────────────────┬─────────────────────────────────────┘
                    │  MCP Protocol (JSON-RPC over stdio/HTTP)
        ┌───────────┼───────────────────────────────┐
        ▼           ▼                               ▼
  ┌──────────┐ ┌──────────┐                  ┌──────────┐
  │ kubectl  │ │Terraform │     ...           │  Custom  │
  │  skill   │ │  skill   │                  │  skills  │
  └──────────┘ └──────────┘                  └──────────┘
        │           │                               │
        ▼           ▼                               ▼
    Kubernetes   AWS APIs              ServiceNow / PagerDuty
    GKE / EKS    IaC state            Rundeck / NETCONF / gNMI
```

**The MCP server is a process.** It runs wherever is convenient:
- GKE pod / sidecar (production, enterprise)
- Lambda function (event-driven use cases)
- Local daemon (development, iteration)

The skills are declarative files. They describe inputs, outputs, and the tool to call. The same
skill file works in all three environments. This is what makes the platform portable — you don't
rebuild it for each environment, you redeploy the same process with the same skills.

---

## Metrics and Business Outcomes (How to Frame in Interviews)

| Outcome | How to say it |
|---|---|
| Faster incident resolution | "We moved from a median 45-minute time-to-diagnosis to under 5 minutes for instrumented failure categories" |
| Reduced on-call burden | "On-call engineers went from investigating to reviewing — cognitive load at 2am dropped materially" |
| Runbook coverage | "We went from ~20% of known failure modes having runbooks to near-complete coverage, because the agent generates them during incidents rather than after" |
| PRR acceleration | "PRR evidence collection went from a half-day manual exercise to a 3-minute automated report with gaps flagged" |
| Cost governance | "We introduced cost impact visibility at PR review time — engineers see the dollar implication of their infrastructure changes before merge" |
| Organisational scalability | "One senior SRE's knowledge of the system was encoded into agent skills, making that knowledge available to every engineer on the team" |

---

## Things Worth Saying in Interviews

**On MCP and AI agents:**
> "The key design principle is that the AI should be the orchestration layer, not a chatbot.
> You give it structured tools and it decides when to call which tool and in what order.
> That's qualitatively different from having an LLM summarise a log file someone pastes into it."

**On runbooks:**
> "The best time to write a runbook is during an incident, because that's when the diagnostic
> commands are fresh and the root cause is confirmed. The worst time is three weeks later when
> it ends up in a sprint as tech debt and never gets written. The agent solves this by generating
> the runbook as a side effect of doing the diagnosis."

**On the Equinix / network angle:**
> "Network operations is actually ahead of cloud operations in some ways — it's been telemetry-first
> for decades. BGP notifications, SNMP traps, syslog, NetFlow — the data exists. What's been
> missing is the reasoning layer that connects the data to a diagnosis and then to an action.
> That's exactly what the agent provides."

**On principal-level impact:**
> "My job wasn't to write the scripts. It was to design the integration architecture so that
> any tool the team needed could be added as a skill in a day, and any new failure mode the agent
> encountered could be codified into a runbook that prevented the next engineer from facing it cold."
