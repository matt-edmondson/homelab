# LocalAI Distributed Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the LocalAI deployment from the deprecated P2P/libp2p worker mode to upstream's distributed mode (PR mudler/LocalAI#9124, released in v4.1.0). Adds dedicated Postgres (pgvector) + NATS (JetStream), rewrites the frontend and worker pods to use the new register-to + registration-token contract, and adds an agent-worker for MCP/skills.

**Architecture:** Stateless LocalAI frontend (`--distributed`) ↔ Postgres (state/auth/agent-pool vectors) + NATS (real-time coordination) ↔ generic workers that self-register via `LOCALAI_REGISTER_TO`. Workers keep the existing per-GPU-tier DaemonSet shape with `hostPort` + `NODE_IP` advertise via downward API. NFS `/models`, `/backends`, `/configuration` stay shared across frontend and workers so SmartRouter file staging is a no-op.

**Tech Stack:** Terraform `kubernetes` + `helm` providers; LocalAI v4.2.1 (pinned, no more floating tags); `quay.io/mudler/localrecall:v0.5.5-postgresql` (pgvector); `nats:2-alpine`. All run from `terraform/` directory via Makefile per repo convention.

**Reference spec:** `docs/superpowers/specs/2026-05-12-localai-distributed-mode-design.md`

---

## Pre-flight context

Before starting, the engineer should know:

- **Working dir:** all `make` and `terraform` commands run from `terraform/` (per `CLAUDE.md`). The Bash `Edit`/`Write` tools use absolute Windows paths from repo root.
- **Current cluster state:** The LocalAI workers are in `CrashLoopBackOff` because the floating `latest-gpu-nvidia-cuda-13` image pulled in v4.2.x, which removed the `worker p2p-llama-cpp-rpc` subcommand. The unstaged diff in `terraform/localai.tf` is the user's earlier-but-incorrect fix attempt — it will be **subsumed and overwritten** by this plan. Do not try to preserve it.
- **Apply strategy:** Each phase applies a subset via `terraform apply -target=<resource>` and waits for runtime verification before the next phase. The Makefile targets are updated only at the very end.
- **Generated secret in tfvars:** the user's real `terraform/terraform.tfvars` is gitignored. They will need to add `localai_postgres_password = "..."` and rename `localai_p2p_token` → `localai_registration_token` there before any apply that needs them. Task 4 handles this.

---

## Task 1: Rewrite the variables block in `localai.tf`

Replace the variable declarations (currently lines ~14–67) to drop `localai_image_tag` and `localai_p2p_token`, add the new variables, and insert a `moved` block for the secret rename.

**Files:**
- Modify: `terraform/localai.tf` (variables section + add `moved` block at end of variables area)

- [ ] **Step 1: Replace the variables block via Edit**

Use the `Edit` tool to replace the entire variables block (everything from `variable "localai_enabled" {` through the closing `}` of `variable "localai_p2p_token"`) with:

```hcl
variable "localai_enabled" {
  description = "Enable LocalAI deployment"
  type        = bool
  default     = true
}

variable "localai_image_version" {
  description = "LocalAI version tag (e.g. v4.2.1). Suffix is appended per component: -aio-cpu for frontend/agent-worker, -gpu-nvidia-cuda-13 for workers."
  type        = string
  default     = "v4.2.1"
}

variable "localai_memory_request" {
  description = "Memory request for LocalAI container"
  type        = string
  default     = "4Gi"
}

variable "localai_memory_limit" {
  description = "Memory limit for LocalAI container"
  type        = string
  default     = "24Gi"
}

variable "localai_cpu_request" {
  description = "CPU request for LocalAI container"
  type        = string
  default     = "1000m"
}

variable "localai_cpu_limit" {
  description = "CPU limit for LocalAI container"
  type        = string
  default     = "4000m"
}

variable "localai_gpu_enabled" {
  description = "Request GPU resource for LocalAI worker DaemonSet (requires NVIDIA device plugin)"
  type        = bool
  default     = true
}

variable "localai_gpu_min_vram_gb" {
  description = "Minimum GPU VRAM in GB required for LocalAI workers (0 = no VRAM constraint)"
  type        = number
  default     = 12
}

variable "localai_registration_token" {
  description = "Shared registration token: workers and agent-worker present this to the frontend at startup. Generate with: openssl rand -hex 32"
  type        = string
  sensitive   = true
  default     = ""
}

variable "localai_postgres_password" {
  description = "Password for the bundled LocalAI Postgres (used by the frontend for auth + agent-pool vector tables)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "localai_postgres_storage_size" {
  description = "Longhorn PVC size for the bundled LocalAI Postgres"
  type        = string
  default     = "20Gi"
}

variable "localai_nats_storage_size" {
  description = "Longhorn PVC size for NATS JetStream data"
  type        = string
  default     = "5Gi"
}

variable "localai_agent_pool_embedding_model" {
  description = "Embedding model name advertised via LOCALAI_AGENT_POOL_EMBEDDING_MODEL"
  type        = string
  default     = "granite-embedding-107m-multilingual"
}

# Migration: rename of the registration secret resource.
# The Kubernetes object name itself also changes (localai-p2p -> localai-registration),
# which terraform handles as destroy/create. The token value (the string) is identical.
moved {
  from = kubernetes_secret.localai_p2p
  to   = kubernetes_secret.localai_registration
}
```

- [ ] **Step 2: Validate**

```bash
cd terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

If `terraform validate` reports `Reference to undeclared input variable` for `localai_image_tag` or `localai_p2p_token`, that means a downstream resource still references the old name — proceed to Task 5 / Task 7 which fix those references. The validate failure is expected at this checkpoint.

- [ ] **Step 3: Do NOT commit yet** — `localai.tf` is currently in an inconsistent state (variables renamed but resources below still reference old names). Continue to Task 2.

---

## Task 2: Rename the registration secret resource

**Files:**
- Modify: `terraform/localai.tf` lines ~82–96 (the existing `kubernetes_secret.localai_p2p` block)

- [ ] **Step 1: Replace the secret block**

Use `Edit` to replace the existing block:

```hcl
# P2P Swarm Secret
resource "kubernetes_secret" "localai_p2p" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-p2p"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    token = var.localai_p2p_token
  }

  type = "Opaque"
}
```

with:

```hcl
# Registration token: workers and agent-worker present this to the frontend at startup.
resource "kubernetes_secret" "localai_registration" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-registration"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    token = var.localai_registration_token
  }

  type = "Opaque"
}
```

- [ ] **Step 2: Validate**

```bash
cd terraform && terraform validate
```

Expected: validate now reports failures referencing `kubernetes_secret.localai_p2p` (from frontend and worker resources further down) and `var.localai_image_tag`. That is expected; later tasks fix them. Do not stop on these.

---

## Task 3: Update `terraform.tfvars.example`

**Files:**
- Modify: `terraform/terraform.tfvars.example` (around line 268)

- [ ] **Step 1: Replace the `localai_p2p_token` example line**

Use `Edit` to replace:

```
#localai_p2p_token         = "..."   # Base64-encoded edgevpn YAML token shared by controller + workers. Generate with: docker run --rm localai/localai:latest-gpu-nvidia-cuda-13 local-ai p2p token
```

with:

```
#localai_registration_token        = "..."  # Shared token workers present to the frontend. Generate with: openssl rand -hex 32
#localai_postgres_password         = "..."  # Bundled LocalAI Postgres password. Generate with: openssl rand -hex 32
#localai_postgres_storage_size     = "20Gi"
#localai_nats_storage_size         = "5Gi"
#localai_agent_pool_embedding_model = "granite-embedding-107m-multilingual"
#localai_image_version             = "v4.2.1"
```

Also remove the obsolete `#localai_image_tag = "latest-gpu-nvidia-cuda-13"` line if present in the file (search nearby for it).

- [ ] **Step 2: Verify the edit**

```bash
grep -n "localai_registration_token\|localai_postgres_password\|localai_image_version\|localai_p2p_token\|localai_image_tag" terraform/terraform.tfvars.example
```

Expected: shows the three new lines (registration_token, postgres_password, image_version) and **no** lines containing `localai_p2p_token` or `localai_image_tag`.

---

## Task 4: User updates `terraform.tfvars` (operational step)

`terraform/terraform.tfvars` is gitignored — the engineer cannot edit it programmatically. Surface this to the user.

- [ ] **Step 1: Print the instruction**

Tell the user, verbatim:

> Before the next apply, update your `terraform/terraform.tfvars`:
> 1. Rename the line `localai_p2p_token = "..."` to `localai_registration_token = "..."` (keep the same value)
> 2. Add a new line: `localai_postgres_password = "<paste output of `openssl rand -hex 32`>"`
>
> Reply when done.

- [ ] **Step 2: Wait for user confirmation before proceeding to Task 5**

---

## Task 5: Create `terraform/localai-postgres.tf`

**Files:**
- Create: `terraform/localai-postgres.tf`

- [ ] **Step 1: Write the file**

Full contents:

```hcl
# =============================================================================
# LocalAI Bundled Postgres (pgvector)
# =============================================================================
# Required by LocalAI distributed mode for: node registry, job store, auth,
# and agent-pool vector engine. The image is Mudler's pgvector-enabled build
# (pinned tag from upstream docker-compose.distributed.yaml).
# =============================================================================

resource "kubernetes_secret" "localai_postgres" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-postgres"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    POSTGRES_USER     = "localai"
    POSTGRES_DB       = "localai"
    POSTGRES_PASSWORD = var.localai_postgres_password
    DATABASE_URL      = "postgresql://localai:${var.localai_postgres_password}@localai-postgres:5432/localai?sslmode=disable"
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "localai_postgres" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn,
  ]

  metadata {
    name      = "localai-postgres-data"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.localai_postgres_storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "localai_postgres" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.localai_postgres,
    kubernetes_secret.localai_postgres,
    helm_release.longhorn,
  ]

  metadata {
    name      = "localai-postgres"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai-postgres"
    })
  }

  spec {
    replicas               = 1
    revision_history_limit = 0

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "localai-postgres" }
    }

    template {
      metadata {
        labels = merge(var.common_labels, { app = "localai-postgres" })
      }

      spec {
        container {
          name  = "postgres"
          image = "quay.io/mudler/localrecall:v0.5.5-postgresql"

          port {
            container_port = 5432
            name           = "postgres"
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.localai_postgres[0].metadata[0].name
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql"
            sub_path   = "pgdata"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "localai"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "localai"]
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_postgres[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "localai_postgres" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [kubernetes_deployment.localai_postgres]

  metadata {
    name      = "localai-postgres"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    type     = "ClusterIP"
    selector = { app = "localai-postgres" }

    port {
      protocol    = "TCP"
      port        = 5432
      target_port = 5432
    }
  }
}
```

- [ ] **Step 2: Validate**

```bash
cd terraform && terraform validate
```

Expected: same errors as before (still referencing old `var.localai_image_tag` and `kubernetes_secret.localai_p2p` from the frontend/worker). Those get fixed in Task 8. The postgres file itself should not introduce new errors.

---

## Task 6: Create `terraform/localai-nats.tf`

**Files:**
- Create: `terraform/localai-nats.tf`

- [ ] **Step 1: Write the file**

Full contents:

```hcl
# =============================================================================
# LocalAI Bundled NATS (JetStream)
# =============================================================================
# Real-time coordination plane for LocalAI distributed mode: job queue,
# backend.install events, file-transfer signalling.
# =============================================================================

resource "kubernetes_persistent_volume_claim" "localai_nats" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn,
  ]

  metadata {
    name      = "localai-nats-data"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.localai_nats_storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "localai_nats" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.localai_nats,
    helm_release.longhorn,
  ]

  metadata {
    name      = "localai-nats"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai-nats"
    })
  }

  spec {
    replicas               = 1
    revision_history_limit = 0

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "localai-nats" }
    }

    template {
      metadata {
        labels = merge(var.common_labels, { app = "localai-nats" })
      }

      spec {
        container {
          name  = "nats"
          image = "nats:2-alpine"

          args = ["--js", "-m", "8222", "--store_dir", "/data/jetstream"]

          port {
            container_port = 4222
            name           = "client"
          }

          port {
            container_port = 8222
            name           = "monitor"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          readiness_probe {
            tcp_socket {
              port = 4222
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            tcp_socket {
              port = 4222
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_nats[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "localai_nats" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [kubernetes_deployment.localai_nats]

  metadata {
    name      = "localai-nats"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    type     = "ClusterIP"
    selector = { app = "localai-nats" }

    port {
      name        = "client"
      protocol    = "TCP"
      port        = 4222
      target_port = 4222
    }

    port {
      name        = "monitor"
      protocol    = "TCP"
      port        = 8222
      target_port = 8222
    }
  }
}
```

- [ ] **Step 2: Validate**

```bash
cd terraform && terraform validate
```

Expected: same residual errors from the frontend/worker still referencing the old variable and secret. The nats file itself adds no new errors.

---

## Task 7: Apply postgres + NATS (no impact on running frontend)

The frontend and workers still reference `var.localai_image_tag` and `kubernetes_secret.localai_p2p`, so we cannot apply the whole file yet. But the new infra has clean dependencies and can be applied in isolation with `-target`.

**Files:** none modified — apply-only task.

- [ ] **Step 1: Targeted plan**

```bash
cd terraform && terraform plan \
  -target=kubernetes_secret.localai_postgres \
  -target=kubernetes_persistent_volume_claim.localai_postgres \
  -target=kubernetes_deployment.localai_postgres \
  -target=kubernetes_service.localai_postgres \
  -target=kubernetes_persistent_volume_claim.localai_nats \
  -target=kubernetes_deployment.localai_nats \
  -target=kubernetes_service.localai_nats
```

Expected: `Plan: 7 to add, 0 to change, 0 to destroy.` (plus a `Resource targeting is in effect` warning, which is fine). Cancel if anything else shows up in the plan.

- [ ] **Step 2: Apply**

```bash
cd terraform && terraform apply -auto-approve \
  -target=kubernetes_secret.localai_postgres \
  -target=kubernetes_persistent_volume_claim.localai_postgres \
  -target=kubernetes_deployment.localai_postgres \
  -target=kubernetes_service.localai_postgres \
  -target=kubernetes_persistent_volume_claim.localai_nats \
  -target=kubernetes_deployment.localai_nats \
  -target=kubernetes_service.localai_nats
```

Expected: `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.`

- [ ] **Step 3: Verify both come up**

```bash
kubectl get pods -n localai -l app=localai-postgres -o wide
kubectl get pods -n localai -l app=localai-nats -o wide
```

Expected: both `1/1 Running`. If postgres is `Pending` more than 60s, run `kubectl describe pvc -n localai localai-postgres-data` and check that Longhorn provisioned a volume.

- [ ] **Step 4: Verify postgres accepts connections**

```bash
kubectl exec -n localai deploy/localai-postgres -- pg_isready -U localai
```

Expected: `/var/run/postgresql:5432 - accepting connections`

- [ ] **Step 5: Verify NATS JetStream**

```bash
kubectl exec -n localai deploy/localai-nats -- wget -qO- http://localhost:8222/jsz | head -5
```

Expected: JSON output starting with `{"server_id":"..."`. If the binary doesn't have `wget`, use:
```bash
kubectl port-forward -n localai svc/localai-nats 8222:8222 &
curl -s http://localhost:8222/jsz | head -5
kill %1
```

- [ ] **Step 6: Commit progress**

```bash
git add terraform/localai-postgres.tf terraform/localai-nats.tf terraform/terraform.tfvars.example
git commit -m "feat(localai): add bundled Postgres (pgvector) + NATS for distributed mode"
```

Note: `terraform/localai.tf` is **not** committed yet — it is still in a half-edited state (variables renamed but frontend/worker still reference old vars). It gets committed in Task 12 once it's coherent.

---

## Task 8: Rewrite the frontend Deployment

The frontend container (currently lines ~349–440 of `terraform/localai.tf`) needs: new image tag, dropped `LOCALAI_P2P*` env, added distributed-mode env (NATS URL, agent-pool, auth, registration token), and `depends_on` updates.

**Files:**
- Modify: `terraform/localai.tf` — the `kubernetes_deployment.localai` resource

- [ ] **Step 1: Update `depends_on`**

In the `kubernetes_deployment.localai` resource (around line 311), replace:

```hcl
  depends_on = [
    kubernetes_persistent_volume_claim.localai_models,
    kubernetes_persistent_volume_claim.localai_backends,
    kubernetes_persistent_volume_claim.localai_configuration,
    kubernetes_persistent_volume_claim.localai_data,
    kubernetes_persistent_volume_claim.localai_output,
    helm_release.longhorn,
    kubernetes_secret.localai_p2p,
  ]
```

with:

```hcl
  depends_on = [
    kubernetes_persistent_volume_claim.localai_models,
    kubernetes_persistent_volume_claim.localai_backends,
    kubernetes_persistent_volume_claim.localai_configuration,
    kubernetes_persistent_volume_claim.localai_data,
    kubernetes_persistent_volume_claim.localai_output,
    helm_release.longhorn,
    kubernetes_secret.localai_registration,
    kubernetes_secret.localai_postgres,
    kubernetes_deployment.localai_postgres,
    kubernetes_deployment.localai_nats,
  ]
```

- [ ] **Step 2: Update the container image**

Replace:

```hcl
        container {
          name  = "localai"
          image = "localai/localai:${var.localai_image_tag}"
```

with:

```hcl
        container {
          name  = "localai"
          image = "localai/localai:${var.localai_image_version}-aio-cpu"
```

- [ ] **Step 3: Replace the env vars**

Replace the two existing `env { ... }` blocks (LOCALAI_P2P + LOCALAI_P2P_TOKEN) with this block:

```hcl
          env {
            name  = "LOCALAI_DISTRIBUTED"
            value = "true"
          }

          env {
            name  = "LOCALAI_NATS_URL"
            value = "nats://localai-nats.localai.svc:4222"
          }

          env {
            name = "LOCALAI_REGISTRATION_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_registration[0].metadata[0].name
                key  = "token"
              }
            }
          }

          env {
            name  = "LOCALAI_AGENT_POOL_EMBEDDING_MODEL"
            value = var.localai_agent_pool_embedding_model
          }

          env {
            name  = "LOCALAI_AGENT_POOL_VECTOR_ENGINE"
            value = "postgres"
          }

          env {
            name = "LOCALAI_AGENT_POOL_DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_postgres[0].metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }

          env {
            name  = "LOCALAI_AUTH"
            value = "true"
          }

          env {
            name = "LOCALAI_AUTH_DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_postgres[0].metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }

          env {
            name  = "GODEBUG"
            value = "netdns=go"
          }

          env {
            name  = "MODELS_PATH"
            value = "/models"
          }
```

- [ ] **Step 4: Validate**

```bash
cd terraform && terraform validate
```

Expected: errors now only reference `var.localai_image_tag` and `kubernetes_secret.localai_p2p` from the **worker DaemonSet** (frontend is now clean). If the validate shows the frontend is still referencing old names, re-check the Edit calls.

---

## Task 9: Rewrite the worker DaemonSet

The worker container (currently lines ~547–600 of `terraform/localai.tf`) needs the biggest rewrite: drop `args = ["worker", "p2p-llama-cpp-rpc"]`, switch to `["worker"]`, add downward API for NODE_IP/NODE_NAME, add registration env, add hostPort ports + readiness probe.

**Files:**
- Modify: `terraform/localai.tf` — the `kubernetes_daemonset.localai_worker` resource

- [ ] **Step 1: Update the worker container image**

Replace:

```hcl
        container {
          name  = "localai-worker"
          image = "localai/localai:${var.localai_image_tag}"
          args  = ["worker", "p2p-llama-cpp-rpc"]
```

with:

```hcl
        container {
          name  = "localai-worker"
          image = "localai/localai:${var.localai_image_version}-gpu-nvidia-cuda-13"
          args  = ["worker"]
```

- [ ] **Step 2: Replace the existing `env { name = "TOKEN" ... }` block**

The current single env block (TOKEN sourced from `kubernetes_secret.localai_p2p`) needs to be replaced by the full set of worker env vars. Replace this block:

```hcl
          env {
            name = "TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_p2p[0].metadata[0].name
                key  = "token"
              }
            }
          }
```

with:

```hcl
          # Downward API: node identity for advertise addrs
          env {
            name = "NODE_IP"
            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          # Registration with the LocalAI frontend
          env {
            name  = "LOCALAI_REGISTER_TO"
            value = "http://localai.localai.svc:8080"
          }

          env {
            name = "LOCALAI_REGISTRATION_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_registration[0].metadata[0].name
                key  = "token"
              }
            }
          }

          env {
            name  = "LOCALAI_NATS_URL"
            value = "nats://localai-nats.localai.svc:4222"
          }

          # Worker serves gRPC backend on 50051 and HTTP file-transfer on 50050.
          env {
            name  = "LOCALAI_SERVE_ADDR"
            value = "0.0.0.0:50051"
          }

          env {
            name  = "LOCALAI_ADVERTISE_ADDR"
            value = "$(NODE_IP):50051"
          }

          env {
            name  = "LOCALAI_ADVERTISE_HTTP_ADDR"
            value = "$(NODE_IP):50050"
          }

          env {
            name  = "LOCALAI_NODE_NAME"
            value = "$(NODE_NAME)-${each.key}gpu"
          }

          env {
            name  = "LOCALAI_HEARTBEAT_INTERVAL"
            value = "10s"
          }

          # Image-baked HEALTHCHECK targets :8080/readyz which the worker
          # doesn't serve. Override to the file-transfer endpoint on 50050.
          env {
            name  = "HEALTHCHECK_ENDPOINT"
            value = "http://localhost:50050/readyz"
          }

          env {
            name  = "GODEBUG"
            value = "netdns=go"
          }

          env {
            name  = "MODELS_PATH"
            value = "/models"
          }
```

- [ ] **Step 3: Update `depends_on` of the DaemonSet**

Find the worker DaemonSet's `depends_on` block (near the top of `kubernetes_daemonset.localai_worker`, around line 517):

```hcl
  depends_on = [
    kubernetes_secret.localai_p2p,
    kubernetes_persistent_volume_claim.localai_models,
    kubernetes_persistent_volume_claim.localai_backends,
    kubernetes_persistent_volume_claim.localai_configuration,
    helm_release.longhorn,
  ]
```

Replace with:

```hcl
  depends_on = [
    kubernetes_secret.localai_registration,
    kubernetes_persistent_volume_claim.localai_models,
    kubernetes_persistent_volume_claim.localai_backends,
    kubernetes_persistent_volume_claim.localai_configuration,
    helm_release.longhorn,
    kubernetes_deployment.localai,
    kubernetes_deployment.localai_nats,
  ]
```

- [ ] **Step 4: Add container ports + readiness probe**

Inside the worker `container { ... }` block, **after the `resources { ... }` block** and **before the first `volume_mount`**, insert:

```hcl
          port {
            container_port = 50050
            host_port      = 50050
            protocol       = "TCP"
            name           = "http"
          }

          port {
            container_port = 50051
            host_port      = 50051
            protocol       = "TCP"
            name           = "grpc"
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 50050
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 6
          }
```

- [ ] **Step 5: Validate**

```bash
cd terraform && terraform validate
```

Expected: `Success! The configuration is valid.` All references to `localai_image_tag` and `localai_p2p` are now gone.

If validate still fails:
- Search for stragglers: `grep -n 'localai_image_tag\|localai_p2p' terraform/localai.tf`
- Search for stale stuff in new files: `grep -n 'localai_image_tag\|localai_p2p' terraform/localai-postgres.tf terraform/localai-nats.tf`

---

## Task 10: Add the agent-worker Deployment

**Files:**
- Modify: `terraform/localai.tf` — append a new resource after the worker DaemonSet, before the `kubernetes_service.localai` block (around line 650)

- [ ] **Step 1: Insert the agent-worker resource**

Find this section header in `terraform/localai.tf`:

```hcl
# =============================================================================
# Service
# =============================================================================
```

Insert this block **immediately before** that header:

```hcl
# =============================================================================
# Agent Worker — NATS-driven agent chat / MCP / skills executor
# =============================================================================
# Stateless CPU worker that receives agent jobs from NATS, runs LLM calls
# back through the LocalAI API, and publishes results via NATS for SSE
# delivery. No HTTP server, no probes, no GPU, no Docker socket (HTTP/SSE
# MCPs only).

resource "kubernetes_deployment" "localai_agent_worker" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    kubernetes_secret.localai_registration,
    kubernetes_deployment.localai,
    kubernetes_deployment.localai_nats,
  ]

  metadata {
    name      = "localai-agent-worker"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai-agent-worker"
    })
  }

  spec {
    replicas               = 1
    revision_history_limit = 0

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "localai-agent-worker" }
    }

    template {
      metadata {
        labels = merge(var.common_labels, { app = "localai-agent-worker" })
      }

      spec {
        container {
          name    = "localai-agent-worker"
          image   = "localai/localai:${var.localai_image_version}-aio-cpu"
          args    = ["agent-worker"]

          env {
            name  = "LOCALAI_NATS_URL"
            value = "nats://localai-nats.localai.svc:4222"
          }

          env {
            name  = "LOCALAI_REGISTER_TO"
            value = "http://localai.localai.svc:8080"
          }

          env {
            name = "LOCALAI_REGISTRATION_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_registration[0].metadata[0].name
                key  = "token"
              }
            }
          }

          env {
            name  = "LOCALAI_NODE_NAME"
            value = "agent-worker"
          }

          env {
            name  = "GODEBUG"
            value = "netdns=go"
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }
        }
      }
    }
  }
}

```

- [ ] **Step 2: Validate**

```bash
cd terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Format**

```bash
cd terraform && terraform fmt
```

Expected: lists any files that were reformatted (likely `localai.tf`, `localai-postgres.tf`, `localai-nats.tf`). Re-run `terraform validate` after to confirm still clean.

---

## Task 11: Apply the rest of the LocalAI stack

This applies the frontend, workers, agent-worker, and the secret rename in one pass. Terraform will order them by `depends_on`.

**Files:** none modified — apply-only task.

- [ ] **Step 1: Targeted plan**

```bash
cd terraform && terraform plan \
  -target=kubernetes_secret.localai_registration \
  -target=kubernetes_deployment.localai \
  -target=kubernetes_daemonset.localai_worker \
  -target=kubernetes_deployment.localai_agent_worker \
  -target=kubernetes_service.localai 2>&1 | tail -40
```

Expected (rough): plan shows the secret moved (no-op state move), the frontend deployment update-in-place or replace, the worker DaemonSet update-in-place, the new agent-worker create, and the destroy of the old `localai-p2p` Kubernetes secret object. Roughly `Plan: 1-2 to add, 2-3 to change, 1 to destroy.`

Sanity check before applying — if the plan tries to destroy any of `localai-models`, `localai-backends`, `localai-configuration`, `localai-data`, or `localai-output` PVCs, **stop** and investigate. Those should not be touched.

- [ ] **Step 2: Apply**

```bash
cd terraform && terraform apply -auto-approve \
  -target=kubernetes_secret.localai_registration \
  -target=kubernetes_deployment.localai \
  -target=kubernetes_daemonset.localai_worker \
  -target=kubernetes_deployment.localai_agent_worker \
  -target=kubernetes_service.localai
```

Expected: `Apply complete!` with the resource counts from the plan.

- [ ] **Step 3: Verify frontend comes up cleanly**

```bash
kubectl rollout status -n localai deployment/localai --timeout=180s
kubectl logs -n localai deploy/localai --tail=30
```

Expected:
- `deployment "localai" successfully rolled out`
- Logs show no `parsing yaml` errors; should see "distributed mode" or NATS connection messages

- [ ] **Step 4: Verify workers register**

```bash
kubectl get pods -n localai -l role=localai-worker -o wide
kubectl logs -n localai -l role=localai-worker --tail=20 --prefix
```

Expected:
- Workers `1/1 Running` on each `gpu-count-exact-1` node (currently `rainbow` and `celery`)
- Logs show registration with the frontend (look for `register` / `registered` / the frontend URL `localai.localai.svc:8080`)
- No `unexpected argument` or `parsing yaml` errors

- [ ] **Step 5: Verify agent-worker**

```bash
kubectl rollout status -n localai deployment/localai-agent-worker --timeout=60s
kubectl logs -n localai deploy/localai-agent-worker --tail=20
```

Expected: rolled out; logs show connection to NATS and registration with the frontend.

- [ ] **Step 6: Verify frontend sees registered nodes**

```bash
kubectl exec -n localai deploy/localai -- curl -s http://localhost:8080/v1/models | head -20
```

Expected: JSON response with `"data":[...]` listing models. Empty list is OK at this stage; what matters is that the API responds.

If feasible, hit the Nodes UI to confirm registrations are showing up:

```bash
kubectl port-forward -n localai svc/localai 8080:80 &
# Browse http://localhost:8080/nodes (or whatever path the v4.2.1 UI uses)
# Or curl an API endpoint that lists nodes if one exists
kill %1
```

---

## Task 12: Commit the new LocalAI configuration

**Files:** none modified — commit-only task.

- [ ] **Step 1: Review the diff**

```bash
git diff terraform/localai.tf | head -80
git status --short
```

Expected staged/unstaged: `M terraform/localai.tf`, `M terraform/terraform.tfvars.example` (already committed in Task 7 commit? — only if it changed again, otherwise just localai.tf).

- [ ] **Step 2: Stage and commit**

```bash
git add terraform/localai.tf
git commit -m "feat(localai): migrate to distributed mode (v4.2.1)

- Pin image to v4.2.1 with per-component suffixes (-aio-cpu / -gpu-nvidia-cuda-13)
- Drop deprecated p2p/libp2p worker mode (removed upstream in PR #9124)
- Rename kubernetes_secret.localai_p2p -> .localai_registration (moved block)
- Frontend now runs --distributed with Postgres-backed auth + agent pool
- Workers register via LOCALAI_REGISTER_TO + LOCALAI_REGISTRATION_TOKEN,
  advertise NODE_IP via downward API, expose 50050/50051 with hostPort
- New agent-worker Deployment for NATS-driven agent/MCP/skills jobs

Spec: docs/superpowers/specs/2026-05-12-localai-distributed-mode-design.md"
```

---

## Task 13: Update Makefile `plan-localai` / `apply-localai` targets

The existing Makefile targets miss `kubernetes_daemonset.localai_worker` (which is why the prior debug needed a manual `-target`). Fix that and add the new resources so `make plan-localai` / `make apply-localai` cover everything.

**Files:**
- Modify: `terraform/Makefile` lines ~686–701 (the `plan-localai` block) and the matching `apply-localai` block (use `grep -n 'apply-localai:' terraform/Makefile` to find it).

- [ ] **Step 1: Update `plan-localai`**

Use `Edit` to replace the `plan-localai` block:

```makefile
plan-localai: check-vars check-init ## Plan LocalAI full-stack inference
	@echo "Planning LocalAI components..."
	terraform plan \
		-target=kubernetes_namespace.localai \
		-target=kubernetes_persistent_volume.localai_models \
		-target=kubernetes_persistent_volume_claim.localai_models \
		-target=kubernetes_persistent_volume.localai_backends \
		-target=kubernetes_persistent_volume_claim.localai_backends \
		-target=kubernetes_persistent_volume.localai_configuration \
		-target=kubernetes_persistent_volume_claim.localai_configuration \
		-target=kubernetes_persistent_volume.localai_data \
		-target=kubernetes_persistent_volume_claim.localai_data \
		-target=kubernetes_persistent_volume.localai_output \
		-target=kubernetes_persistent_volume_claim.localai_output \
		-target=kubernetes_deployment.localai \
		-target=kubernetes_service.localai
```

with:

```makefile
plan-localai: check-vars check-init ## Plan LocalAI full-stack inference (distributed mode)
	@echo "Planning LocalAI components..."
	terraform plan \
		-target=kubernetes_namespace.localai \
		-target=kubernetes_secret.localai_registration \
		-target=kubernetes_secret.localai_postgres \
		-target=kubernetes_persistent_volume_claim.localai_postgres \
		-target=kubernetes_deployment.localai_postgres \
		-target=kubernetes_service.localai_postgres \
		-target=kubernetes_persistent_volume_claim.localai_nats \
		-target=kubernetes_deployment.localai_nats \
		-target=kubernetes_service.localai_nats \
		-target=kubernetes_persistent_volume.localai_models \
		-target=kubernetes_persistent_volume_claim.localai_models \
		-target=kubernetes_persistent_volume.localai_backends \
		-target=kubernetes_persistent_volume_claim.localai_backends \
		-target=kubernetes_persistent_volume.localai_configuration \
		-target=kubernetes_persistent_volume_claim.localai_configuration \
		-target=kubernetes_persistent_volume.localai_data \
		-target=kubernetes_persistent_volume_claim.localai_data \
		-target=kubernetes_persistent_volume.localai_output \
		-target=kubernetes_persistent_volume_claim.localai_output \
		-target=kubernetes_deployment.localai \
		-target=kubernetes_daemonset.localai_worker \
		-target=kubernetes_deployment.localai_agent_worker \
		-target=kubernetes_service.localai
```

- [ ] **Step 2: Update `apply-localai`**

Find the `apply-localai:` block (search the file for `apply-localai:`). Replace its body with the same list of `-target` flags as in Step 1, but using `terraform apply -auto-approve` instead of `terraform plan`:

```makefile
apply-localai: check-vars check-init ## Deploy LocalAI full-stack inference (distributed mode)
	@echo "Deploying LocalAI..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.localai \
		-target=kubernetes_secret.localai_registration \
		-target=kubernetes_secret.localai_postgres \
		-target=kubernetes_persistent_volume_claim.localai_postgres \
		-target=kubernetes_deployment.localai_postgres \
		-target=kubernetes_service.localai_postgres \
		-target=kubernetes_persistent_volume_claim.localai_nats \
		-target=kubernetes_deployment.localai_nats \
		-target=kubernetes_service.localai_nats \
		-target=kubernetes_persistent_volume.localai_models \
		-target=kubernetes_persistent_volume_claim.localai_models \
		-target=kubernetes_persistent_volume.localai_backends \
		-target=kubernetes_persistent_volume_claim.localai_backends \
		-target=kubernetes_persistent_volume.localai_configuration \
		-target=kubernetes_persistent_volume_claim.localai_configuration \
		-target=kubernetes_persistent_volume.localai_data \
		-target=kubernetes_persistent_volume_claim.localai_data \
		-target=kubernetes_persistent_volume.localai_output \
		-target=kubernetes_persistent_volume_claim.localai_output \
		-target=kubernetes_deployment.localai \
		-target=kubernetes_daemonset.localai_worker \
		-target=kubernetes_deployment.localai_agent_worker \
		-target=kubernetes_service.localai
```

- [ ] **Step 3: Update `generate-secrets` to emit the new secrets**

Find the `generate-secrets:` target (around line 395 of `terraform/Makefile`). It currently emits suggestions for `baget_api_key`, `grafana_admin_password`, and `traefik_basic_auth_users`.

Use `Edit` to replace:

```makefile
	@echo "# Generated credentials - add to your terraform.tfvars file:"
	@echo "baget_api_key = \"$$(openssl rand -base64 32)\""
	@echo "grafana_admin_password = \"$$(openssl rand -base64 16)\""
	@echo "traefik_basic_auth_users = \"$$(htpasswd -nb admin $$(openssl rand -base64 16))\"" 2>/dev/null || echo "# traefik_basic_auth_users requires htpasswd tool (apache2-utils)"
```

with:

```makefile
	@echo "# Generated credentials - add to your terraform.tfvars file:"
	@echo "baget_api_key = \"$$(openssl rand -base64 32)\""
	@echo "grafana_admin_password = \"$$(openssl rand -base64 16)\""
	@echo "traefik_basic_auth_users = \"$$(htpasswd -nb admin $$(openssl rand -base64 16))\"" 2>/dev/null || echo "# traefik_basic_auth_users requires htpasswd tool (apache2-utils)"
	@echo "localai_registration_token = \"$$(openssl rand -hex 32)\""
	@echo "localai_postgres_password = \"$$(openssl rand -hex 32)\""
```

- [ ] **Step 4: Verify `make plan-localai` is a clean no-op**

```bash
cd terraform && make plan-localai 2>&1 | tail -10
```

Expected: `No changes. Your infrastructure matches the configuration.` (everything is already applied as of Task 11). If there are pending changes, that means a resource was missed in Tasks 8–10 — re-run validate and inspect.

- [ ] **Step 5: Commit**

```bash
git add terraform/Makefile
git commit -m "build(make): cover LocalAI workers + distributed-mode resources in plan/apply targets

- Add missing kubernetes_daemonset.localai_worker to plan-localai/apply-localai
- Add new distributed-mode resources (postgres, NATS, agent-worker, registration secret)
- generate-secrets now emits localai_registration_token + localai_postgres_password"
```

---

## Task 14: End-to-end verification

**Files:** none — verification-only task.

- [ ] **Step 1: List models via the frontend API**

```bash
kubectl exec -n localai deploy/localai -- curl -s http://localhost:8080/v1/models | head -40
```

Expected: JSON with `"data":[ ... ]`.

- [ ] **Step 2: Confirm at least one worker is registered**

If the frontend exposes a `/api/nodes` or equivalent endpoint:

```bash
kubectl exec -n localai deploy/localai -- curl -s http://localhost:8080/api/nodes 2>&1 | head -30
```

If that path doesn't exist in this version, check the Nodes UI by port-forward + browser, or grep frontend logs:

```bash
kubectl logs -n localai deploy/localai --tail=200 | grep -iE "register|node"
```

Expected: log lines showing worker registration from `rainbow` and `celery` (both have 1-GPU labelling currently).

- [ ] **Step 3: Trigger a small inference if a model is loaded**

```bash
kubectl exec -n localai deploy/localai -- curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"<one model name from step 1>","messages":[{"role":"user","content":"reply with the single word OK"}],"max_tokens":4}'
```

Expected: a chat completion response. If no model is loaded yet, this step is skipped — the cluster is healthy as long as steps 1 and 2 pass.

- [ ] **Step 4: Confirm crashloops are gone**

```bash
kubectl get pods -n localai --field-selector=status.phase!=Running,status.phase!=Succeeded
```

Expected: `No resources found in localai namespace.`

- [ ] **Step 5: Confirm ingress still works**

```bash
curl -sk https://localai.ktsu.dev/readyz
```

Expected: `OK` or empty 200. The Traefik IngressRoute and DNS continue to point at the `kubernetes_service.localai` ClusterIP, which is unchanged.

---

## Task 15: Final cleanup

**Files:** none — wrap-up.

- [ ] **Step 1: Confirm the in-cluster state is fully reconciled**

```bash
cd terraform && terraform plan 2>&1 | tail -3
```

Expected: `No changes. Your infrastructure matches the configuration.` If anything pending, fix in place rather than leaving drift.

- [ ] **Step 2: Confirm `git status` is clean (or only contains untracked files outside terraform/)**

```bash
git status --short
```

Expected: empty or only files outside `terraform/`. If `terraform/localai.tf` is still modified, it means a Step from earlier wasn't committed.

- [ ] **Step 3: Summarize for the user**

Report:
- Image pinned at `v4.2.1` (no more floating tag breakage)
- Distributed-mode stack live: Postgres + NATS + frontend (`--distributed`) + workers + agent-worker
- `make plan-localai` / `apply-localai` now cover every resource (worker DaemonSet was previously missed)
- Spec: `docs/superpowers/specs/2026-05-12-localai-distributed-mode-design.md`
- Plan: `docs/superpowers/plans/2026-05-12-localai-distributed-mode.md`
