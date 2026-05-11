# LocalAI Swarm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the existing single-pod LocalAI deployment into a swarm: a GPU-free controller pod routes requests, and a DaemonSet deploys one GPU worker pod per GPU node.

**Architecture:** The existing `kubernetes_deployment.localai` becomes the controller (no GPU, `LOCALAI_P2P=true`). A new `kubernetes_daemonset.localai_worker` targets every node labelled `nvidia.com/gpu.present=true` and runs with `LOCALAI_WORKER=true`. Both share a token via a Kubernetes Secret for P2P worker discovery.

**Tech Stack:** Terraform (Kubernetes provider ~> 2.38), LocalAI (`localai/localai` image), Kubernetes DaemonSet, Kubernetes Secret.

---

### Task 1: Add P2P token variable, Secret, and tfvars.example entry

**Files:**
- Modify: `terraform/localai.tf` (add variable + Secret resource near top of file, after existing variables ~line 61)
- Modify: `terraform/terraform.tfvars.example` (add placeholder after line 261)

- [ ] **Step 1: Add the variable to `terraform/localai.tf`**

Insert after the existing `variable "localai_gpu_min_vram_gb"` block (after line 61):

```hcl
variable "localai_p2p_token" {
  description = "Shared P2P token for LocalAI swarm (controller + workers)"
  type        = string
  sensitive   = true
}
```

- [ ] **Step 2: Add the Secret resource to `terraform/localai.tf`**

Insert after the `kubernetes_namespace.localai` resource block (after the closing `}` of that resource, around line 72):

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
}
```

- [ ] **Step 3: Add placeholder to `terraform/terraform.tfvars.example`**

Insert after line 261 (`#localai_gpu_min_vram_gb   = 12      # Minimum GPU VRAM in GB (0 = no constraint)`):

```hcl
#localai_p2p_token         = "change-me"  # Shared P2P swarm token — set in terraform.tfvars (gitignored)
```

- [ ] **Step 4: Add token to your local `terraform/terraform.tfvars`**

Generate a random token and add it (this file is gitignored):

```
localai_p2p_token = "your-random-token-here"
```

Use `openssl rand -hex 32` or any random string generator.

- [ ] **Step 5: Validate**

```bash
cd terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add terraform/localai.tf terraform/terraform.tfvars.example
git commit -m "feat(localai): add P2P swarm token variable and Secret"
```

---

### Task 2: Convert controller Deployment to GPU-free P2P mode

**Files:**
- Modify: `terraform/localai.tf` — controller Deployment only (lines ~287–435)

- [ ] **Step 1: Remove GPU from controller resource limits**

In the `kubernetes_deployment.localai` container's `resources` block, replace the `limits` section that conditionally adds GPU:

```hcl
# BEFORE (lines ~339–346):
limits = merge(
  {
    memory = var.localai_memory_limit
    cpu    = var.localai_cpu_limit
  },
  var.localai_gpu_enabled ? { "nvidia.com/gpu" = "1" } : {}
)

# AFTER:
limits = {
  memory = var.localai_memory_limit
  cpu    = var.localai_cpu_limit
}
```

- [ ] **Step 2: Remove GPU nodeSelector from controller**

In the same Deployment's `spec.template.spec`, replace the `node_selector` line:

```hcl
# BEFORE (lines ~393–396):
node_selector = var.localai_gpu_enabled ? merge(
  { "nvidia.com/gpu.present" = "true" },
  var.localai_gpu_min_vram_gb > 0 ? { "gpu-vram-${var.localai_gpu_min_vram_gb}gb" = "true" } : {}
) : {}

# AFTER:
node_selector = {}
```

- [ ] **Step 3: Add P2P env vars to the controller container**

In the `container` block of the Deployment, add after the `port` block and before the `resources` block:

```hcl
env {
  name  = "LOCALAI_P2P"
  value = "true"
}

env {
  name = "LOCALAI_P2P_TOKEN"
  value_from {
    secret_key_ref {
      name = kubernetes_secret.localai_p2p[0].metadata[0].name
      key  = "token"
    }
  }
}
```

- [ ] **Step 4: Add Secret to controller `depends_on`**

In the `kubernetes_deployment.localai` resource, add to the `depends_on` list:

```hcl
kubernetes_secret.localai_p2p,
```

- [ ] **Step 5: Validate**

```bash
cd terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Preview the controller change**

```bash
cd terraform && make plan-localai
```

Expected output includes:
- `kubernetes_deployment.localai[0]` will be updated in-place
- Removed: `"nvidia.com/gpu"` from limits
- Removed: GPU-related node_selector entries
- Added: two env vars (`LOCALAI_P2P`, `LOCALAI_P2P_TOKEN`)

- [ ] **Step 7: Commit**

```bash
git add terraform/localai.tf
git commit -m "feat(localai): convert controller to GPU-free P2P scheduler"
```

---

### Task 3: Add GPU worker DaemonSet

**Files:**
- Modify: `terraform/localai.tf` — add DaemonSet resource after the existing Deployment (after line ~435)

- [ ] **Step 1: Add the worker DaemonSet to `terraform/localai.tf`**

Insert after the closing `}` of `kubernetes_deployment.localai`, before the `# === Service ===` section:

```hcl
# =============================================================================
# Worker DaemonSet — one GPU worker per GPU node
# =============================================================================

resource "kubernetes_daemonset" "localai_worker" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    kubernetes_secret.localai_p2p,
    kubernetes_persistent_volume_claim.localai_models,
    kubernetes_persistent_volume_claim.localai_backends,
    kubernetes_persistent_volume_claim.localai_configuration,
    helm_release.longhorn,
  ]

  metadata {
    name      = "localai-worker"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai-worker"
    })
  }

  spec {
    selector {
      match_labels = { app = "localai-worker" }
    }

    template {
      metadata {
        labels = merge(var.common_labels, { app = "localai-worker" })
      }

      spec {
        container {
          name  = "localai-worker"
          image = "localai/localai:${var.localai_image_tag}"

          env {
            name  = "LOCALAI_WORKER"
            value = "true"
          }

          env {
            name = "LOCALAI_P2P_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_p2p[0].metadata[0].name
                key  = "token"
              }
            }
          }

          resources {
            requests = {
              memory = var.localai_memory_request
              cpu    = var.localai_cpu_request
            }
            limits = {
              memory           = var.localai_memory_limit
              cpu              = var.localai_cpu_limit
              "nvidia.com/gpu" = "1"
            }
          }

          volume_mount {
            name       = "models"
            mount_path = "/models"
          }

          volume_mount {
            name       = "backends"
            mount_path = "/backends"
          }

          volume_mount {
            name       = "configuration"
            mount_path = "/configuration"
          }
        }

        node_selector = { "nvidia.com/gpu.present" = "true" }

        volume {
          name = "models"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_models[0].metadata[0].name
          }
        }

        volume {
          name = "backends"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_backends[0].metadata[0].name
          }
        }

        volume {
          name = "configuration"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_configuration[0].metadata[0].name
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

- [ ] **Step 3: Preview the DaemonSet addition**

```bash
cd terraform && make plan-localai
```

Expected output includes:
- `kubernetes_daemonset.localai_worker[0]` will be created
- node_selector: `nvidia.com/gpu.present = "true"`
- GPU limit: `nvidia.com/gpu = "1"`
- Three volume mounts: models, backends, configuration

- [ ] **Step 4: Commit**

```bash
git add terraform/localai.tf
git commit -m "feat(localai): add GPU worker DaemonSet for P2P swarm"
```

---

### Task 4: Apply and verify

**Files:** None — this task applies and checks the deployed state.

- [ ] **Step 1: Apply**

```bash
cd terraform && make apply-localai
```

Wait for completion. Expected: no errors, all resources created/updated.

- [ ] **Step 2: Verify controller pod is running (no GPU)**

```bash
kubectl get pods -n localai -l app=localai
```

Expected: one pod in `Running` state.

```bash
kubectl describe pod -n localai -l app=localai | grep -A5 "Limits:"
```

Expected: no `nvidia.com/gpu` line in Limits.

- [ ] **Step 3: Verify worker pods are running (one per GPU node)**

```bash
kubectl get pods -n localai -l app=localai-worker -o wide
```

Expected: one pod per GPU node, all in `Running` state. The NODE column should match your nodes that have `nvidia.com/gpu.present=true`.

- [ ] **Step 4: Verify workers have joined the swarm**

```bash
kubectl logs -n localai -l app=localai-worker --tail=50
```

Expected: log lines indicating worker started and connected to the P2P swarm (look for `p2p` or `worker` in the output).

```bash
kubectl logs -n localai -l app=localai deploy/localai --tail=50
```

Expected: controller logs showing workers registered (look for connected worker addresses or model routing).

- [ ] **Step 5: Smoke test the API**

```bash
kubectl exec -n localai deploy/localai -- curl -s http://localhost:8080/v1/models
```

Expected: JSON response listing available models (may be empty `{"object":"list","data":[]}` if no models loaded yet — that's fine, it means the API is up).
