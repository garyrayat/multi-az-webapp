# Runbook: OOMKilled → CrashLoopBackOff

**Namespace:** `webapp`  
**Affected workload:** `deployment/memory-hog`  
**Incident date:** 2026-04-15  
**Cluster:** EKS `multi-az-webapp` (us-east-1), nodes on `ip-10-0-10-31` / `ip-10-0-11-244`

---

## Summary

The `memory-hog` container entered `CrashLoopBackOff` because its memory **limit (10Mi) is 13× smaller
than the memory its workload actually requests (128Mi)**. Kubernetes OOM-kills the container
on every start (exit code 137, signal 9), and the kubelet backs off exponentially until the
pod is stuck indefinitely.

---

## Symptoms

```
NAME                         READY   STATUS             RESTARTS   AGE
memory-hog-884dc9595-sl9pk   0/1     CrashLoopBackOff   5          3m27s
```

- `READY` column shows `0/1` — pod never passes its readiness check
- `RESTARTS` count climbs: 1 → 2 → 5 → ... (exponential back-off: 10s, 20s, 40s, 80s, 160s, ...)
- `STATUS` cycles: `OOMKilled` → `Error` → `CrashLoopBackOff`

---

## Diagnosis

### Step 1 — identify the crashing pod

```bash
kubectl get pods -n webapp
```

Look for `CrashLoopBackOff` or `OOMKilled` in the STATUS column.

### Step 2 — describe the pod

```bash
kubectl describe pod -n webapp <pod-name>
```

Key fields to inspect:

| Field | What to look for |
|-------|-----------------|
| `Last State: Reason` | `OOMKilled` confirms memory kill |
| `Exit Code` | `137` = killed by signal 9 (SIGKILL from OOM killer); `1` = process error |
| `Limits.memory` | The ceiling the kernel enforces |
| `Requests.memory` | What the scheduler reserved |
| `Events` | `BackOff restarting failed container` |

**Actual output from this incident:**

```
Last State:  Terminated
  Reason:    OOMKilled
  Exit Code: 1

Limits:
  memory:  10Mi       ← kernel-enforced ceiling
Requests:
  memory:  5Mi

Command:
  stress --vm 1 --vm-bytes 128M   ← tries to allocate 128Mi
```

The command asks for **128Mi**. The limit allows **10Mi**. The kernel kills the process
the instant it crosses the limit.

### Step 3 — read the logs

```bash
# Most recent logs from the crashed container
kubectl logs -n webapp <pod-name>

# Logs from the previous crash cycle
kubectl logs -n webapp <pod-name> --previous
```

**Actual output:**

```
stress: info: [1] dispatching hogs: 0 cpu, 0 io, 1 vm, 0 hdd
stress: FAIL: [1] (415) <-- worker 7 got signal 9
stress: WARN: [1] (417) now reaping child worker processes
stress: FAIL: [1] (451) failed run completed in 0s
```

`signal 9` = SIGKILL. The kernel sent SIGKILL to the worker process because it exceeded the
cgroup memory limit. This is the OOM killer acting.

### Step 4 — confirm the deployment manifest

```bash
kubectl get deployment -n webapp memory-hog -o yaml
```

Confirm the mismatch between `--vm-bytes` in the command and `resources.limits.memory`.

---

## Root Cause

**Memory limit (10Mi) is far below the workload's actual memory need (128Mi).**

The `polinux/stress` container runs `stress --vm 1 --vm-bytes 128M`, which intentionally
allocates 128 MiB of virtual memory. The deployment was configured with:

```yaml
resources:
  requests:
    memory: "5Mi"
  limits:
    memory: "10Mi"   # ← wrong: 13× too small
```

Kubernetes enforces memory limits via Linux cgroups. When the process's RSS exceeds the
limit, the kernel OOM-kills it with SIGKILL (signal 9). Because `restartPolicy: Always` is
set (the default), the kubelet restarts it immediately — but it crashes again in milliseconds.
After repeated fast crashes, the kubelet imposes exponential back-off, producing
`CrashLoopBackOff`.

**This is a misconfiguration — not an application bug or infrastructure failure.**

---

## Fix

You have two options. Choose based on whether the workload's memory usage is correct or the limit is wrong.

### Option A — raise the memory limit to match the workload (recommended)

Edit the deployment to set limits that accommodate what the container actually uses:

```bash
kubectl set resources deployment/memory-hog \
  -n webapp \
  --limits=memory=256Mi \
  --requests=memory=128Mi
```

Or edit the manifest directly:

```bash
kubectl edit deployment/memory-hog -n webapp
```

Change:

```yaml
resources:
  requests:
    memory: "5Mi"
  limits:
    memory: "10Mi"
```

To:

```yaml
resources:
  requests:
    memory: "128Mi"   # matches what stress allocates
  limits:
    memory: "256Mi"   # headroom above the workload's peak
```

### Option B — reduce what the workload allocates (if the limit is intentional)

If the 10Mi limit is a deliberate policy constraint, reduce the stress command's allocation:

```bash
kubectl edit deployment/memory-hog -n webapp
```

Change the container command from:

```yaml
command: ["stress", "--vm", "1", "--vm-bytes", "128M"]
```

To something within the limit:

```yaml
command: ["stress", "--vm", "1", "--vm-bytes", "8M"]
```

### Verify the fix

```bash
# Watch the pod stabilise
kubectl get pods -n webapp -w

# Confirm no OOMKilled in describe output
kubectl describe pod -n webapp <new-pod-name>

# Confirm logs show successful run (no signal 9)
kubectl logs -n webapp <new-pod-name>
```

Expected healthy state:

```
NAME                        READY   STATUS    RESTARTS   AGE
memory-hog-<hash>           1/1     Running   0          60s
```

---

## Detection and prevention

### How to catch this before it reaches production

**1. Set requests and limits on every container — always.**  
Pods without limits are Kubernetes `BestEffort` QoS class. They are the first to be evicted
under node memory pressure and are harder to size correctly.

**2. Make requests ≥ the container's actual steady-state memory usage.**  
Use `kubectl top pod` (requires metrics-server) to measure real usage:

```bash
kubectl top pod -n webapp
```

**3. Enforce a LimitRange in the namespace** to prevent zero-limit deployments from being
admitted:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: webapp-limits
  namespace: webapp
spec:
  limits:
  - type: Container
    default:
      memory: "256Mi"
      cpu: "250m"
    defaultRequest:
      memory: "128Mi"
      cpu: "100m"
    max:
      memory: "2Gi"
```

**4. Add a CI check** (e.g. `kube-score`, `polaris`, or `conftest`) that fails if a container
manifest has `limits.memory` set below a reasonable threshold or missing entirely.

**5. Set up a CloudWatch alarm on OOMKilled events** (if using EKS with Container Insights):

```
Namespace:  ContainerInsights
MetricName: container_oom_events_total
Filter:     ClusterName=multi-az-webapp, Namespace=webapp
Threshold:  > 0
```

---

## Quick reference

| Signal | Exit code | Meaning |
|--------|-----------|---------|
| SIGKILL (9) | 137 | OOM killer or manual kill — check `Reason: OOMKilled` in describe |
| SIGSEGV (11) | 139 | Segmentation fault — application bug |
| Other non-zero | varies | Application exited with error — check logs |

| Status | Meaning |
|--------|---------|
| `OOMKilled` | Container exceeded memory limit; kernel killed it |
| `Error` | Container exited non-zero; may be immediately after OOMKill |
| `CrashLoopBackOff` | Container has crashed multiple times; kubelet is applying back-off |

**Back-off timing:** 10s → 20s → 40s → 80s → 160s → 300s (max). A pod stuck at 300s
back-off will appear unresponsive for 5 minutes between restart attempts.

---

## Related reading

- [Kubernetes: Out of Memory (OOMKilled)](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes: LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [EKS: Container Insights OOM metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-EKS.html)
