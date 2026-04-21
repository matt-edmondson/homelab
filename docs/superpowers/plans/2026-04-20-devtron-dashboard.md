# Devtron Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Devtron (dashboard-only, no CI/CD) to the homelab Kubernetes cluster at `https://devtron.${traefik_domain}`, gated by the existing oauth-forward-auth + crowdsec-bouncer middleware and logged into via Devtron's built-in admin credentials.

**Architecture:** One new Terraform file (`devtron.tf`) holding a `helm_release` for the `devtron-operator` chart (dashboard-only mode, bundled Postgres on Longhorn), plus targeted edits to `ingress.tf` (new IngressRoute), `dns.tf` (add `devtron` to the existing DNS record `local.dns_records` merge), `terraform.tfvars.example` (document new variables), and `Makefile` (new `plan-devtron`/`apply-devtron`/`debug-devtron` targets, and extend `plan-ingress`/`apply-ingress` to include the new IngressRoute).

**Tech Stack:** Terraform (Kubernetes provider 2.38, Helm provider 3.0.2, azurerm), Helm chart `devtron-operator` 0.23.2 from `https://helm.devtron.ai`, Longhorn storage, Traefik IngressRoute CRD.

---

## File Structure

| File | Change | Purpose |
|------|--------|---------|
| `terraform/devtron.tf` | **Create** | Variables, namespace, Helm release, output |
| `terraform/ingress.tf` | **Modify** | Append one new `kubernetes_manifest.ingressroute_devtron` resource |
| `terraform/dns.tf` | **Modify** | Append one conditional line to `local.dns_records` merge |
| `terraform/terraform.tfvars.example` | **Modify** | Append a Devtron variables section |
| `terraform/Makefile` | **Modify** | Add 3 new targets; extend `plan-ingress` and `apply-ingress` target lists |

All work is done from `terraform/` unless otherwise specified.

> **Note on verification:** This is Terraform/Helm infrastructure, not application code with unit tests. "Test" in each task means running `terraform fmt`, `terraform validate`, and `terraform plan` to confirm the configuration parses and the diff matches intent. No pods are created until the user flips `devtron_enabled = true` in `terraform.tfvars` and runs `make apply-devtron`, which is explicitly out of scope for this plan (the plan only changes code, not cluster state).

---

## Task 1: Create `terraform/devtron.tf`

**Files:**
- Create: `terraform/devtron.tf`

- [ ] **Step 1: Create the file with variables, namespace, Helm release, and output**

Create `terraform/devtron.tf` with the following exact content:

```hcl
# =============================================================================
# Devtron — Kubernetes Dashboard (dashboard-only, no CI/CD)
# =============================================================================
# Devtron is an extensible Kubernetes dashboard providing visibility into
# cluster workloads. Installed in dashboard-only mode (installer.modules=[]),
# without the CI/CD module (no Argo CD, Argo Workflows, NATS, MinIO, etc.).
#
# Auth: Devtron does not support disabling its own auth. The ingress is gated
# by oauth-forward-auth + crowdsec-bouncer (see ingress.tf), and users log in
# to Devtron with the admin password auto-generated in devtron-secret.
# Retrieve with: make debug-devtron
#
# Chart: https://helm.devtron.ai (chart name: devtron-operator)
# =============================================================================

# Variables
variable "devtron_enabled" {
  description = "Enable Devtron dashboard deployment"
  type        = bool
  default     = false
}

variable "devtron_chart_version" {
  description = "Version of Devtron Helm chart (devtron-operator)"
  type        = string
  default     = "0.23.2"
}

variable "devtron_postgres_storage_size" {
  description = "Longhorn PVC size for Devtron's bundled Postgres"
  type        = string
  default     = "20Gi"
}

# Namespace
resource "kubernetes_namespace" "devtron" {
  count = var.devtron_enabled ? 1 : 0

  metadata {
    name = "devtroncd"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "devtron"
    })
  }
}

# Devtron Helm Release (dashboard-only mode)
resource "helm_release" "devtron" {
  count = var.devtron_enabled ? 1 : 0

  name       = "devtron"
  repository = "https://helm.devtron.ai"
  chart      = "devtron-operator"
  version    = var.devtron_chart_version
  namespace  = kubernetes_namespace.devtron[0].metadata[0].name

  values = [
    yamlencode({
      installer = {
        modules = []
      }

      global = {
        storageClass = data.kubernetes_storage_class.longhorn.metadata[0].name
      }

      postgres = {
        persistence = {
          storageClass = data.kubernetes_storage_class.longhorn.metadata[0].name
          volumeSize   = var.devtron_postgres_storage_size
        }
      }

      devtron = {
        service = {
          type = "ClusterIP"
          port = 80
        }
        ingress = {
          enabled = false
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.devtron,
    helm_release.longhorn,                 # Ensure storage backend is available
    data.kubernetes_storage_class.longhorn, # Ensure default storage class exists
  ]
}

# Outputs
output "devtron_info" {
  description = "Devtron dashboard information"
  value = var.devtron_enabled ? {
    namespace     = kubernetes_namespace.devtron[0].metadata[0].name
    chart_version = var.devtron_chart_version

    access = {
      web_ui = "https://devtron.${var.traefik_domain}"
    }

    commands = {
      admin_password = "kubectl -n ${kubernetes_namespace.devtron[0].metadata[0].name} get secret devtron-secret -o jsonpath='{.data.ACD_PASSWORD}' | base64 -d"
      check_pods     = "kubectl get pods -n ${kubernetes_namespace.devtron[0].metadata[0].name}"
      check_pvcs     = "kubectl get pvc -n ${kubernetes_namespace.devtron[0].metadata[0].name}"
      check_service  = "kubectl get svc -n ${kubernetes_namespace.devtron[0].metadata[0].name}"
      view_logs      = "kubectl logs -n ${kubernetes_namespace.devtron[0].metadata[0].name} -l app=devtron -f"
    }
  } : null

  sensitive = true
}
```

- [ ] **Step 2: Format the file**

Run: `terraform fmt devtron.tf`
Expected: Command exits 0. If the file needed formatting changes, its name is printed; otherwise no output.

- [ ] **Step 3: Validate Terraform syntax**

Run: `terraform validate`
Expected: `Success! The configuration is valid.`

If you see errors referencing `var.common_labels`, `var.traefik_domain`, `helm_release.longhorn`, or `data.kubernetes_storage_class.longhorn` being undeclared, stop — that means the file was placed outside the `terraform/` directory or the surrounding module is missing the expected declarations. Re-check the working directory is `terraform/`.

- [ ] **Step 4: Commit**

```bash
git add terraform/devtron.tf
git commit -m "feat(devtron): add dashboard-only Helm release"
```

---

## Task 2: Document variables in `terraform.tfvars.example`

**Files:**
- Modify: `terraform/terraform.tfvars.example` (append section)

- [ ] **Step 1: Append the Devtron section**

Append the following block to the end of `terraform/terraform.tfvars.example`:

```hcl

# Devtron Kubernetes Dashboard (dashboard-only, no CI/CD)
#devtron_enabled               = true    # Set to false to disable Devtron
#devtron_chart_version         = "0.23.2"
#devtron_postgres_storage_size = "20Gi"
```

- [ ] **Step 2: Verify the addition**

Run: `tail -5 terraform.tfvars.example`
Expected output (last 5 lines):

```
# Devtron Kubernetes Dashboard (dashboard-only, no CI/CD)
#devtron_enabled               = true    # Set to false to disable Devtron
#devtron_chart_version         = "0.23.2"
#devtron_postgres_storage_size = "20Gi"
```

- [ ] **Step 3: Commit**

```bash
git add terraform/terraform.tfvars.example
git commit -m "docs(devtron): document devtron variables in tfvars example"
```

---

## Task 3: Add DNS record entry in `dns.tf`

**Files:**
- Modify: `terraform/dns.tf` (add one line to `local.dns_records` merge)

- [ ] **Step 1: Add `devtron_enabled` entry to the merge**

Use the Edit tool to modify `terraform/dns.tf`. Find this existing block (around line 60):

```hcl
    # Kubernetes Dashboard
    var.kubernetes_dashboard_enabled ? { dashboard = "dashboard" } : {},
```

Replace it with:

```hcl
    # Kubernetes Dashboard
    var.kubernetes_dashboard_enabled ? { dashboard = "dashboard" } : {},
    # Devtron
    var.devtron_enabled ? { devtron = "devtron" } : {},
```

- [ ] **Step 2: Format and validate**

Run: `terraform fmt dns.tf && terraform validate`
Expected: Either no output from `fmt` or the filename printed, then `Success! The configuration is valid.` from `validate`.

- [ ] **Step 3: Commit**

```bash
git add terraform/dns.tf
git commit -m "feat(devtron): add devtron subdomain to Azure DNS records"
```

---

## Task 4: Add IngressRoute in `ingress.tf`

**Files:**
- Modify: `terraform/ingress.tf` (append one new resource before the "# --- Static Sites ---" section)

- [ ] **Step 1: Insert the IngressRoute resource**

Use the Edit tool on `terraform/ingress.tf`. Find this line (around line 1441):

```hcl
# --- Static Sites ---
```

Replace it with:

```hcl
# Devtron Dashboard
resource "kubernetes_manifest" "ingressroute_devtron" {
  count = var.devtron_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "devtron"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`devtron.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "devtron-service"
          namespace = kubernetes_namespace.devtron[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.devtron,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# --- Static Sites ---
```

- [ ] **Step 2: Format and validate**

Run: `terraform fmt ingress.tf && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add terraform/ingress.tf
git commit -m "feat(devtron): add Traefik IngressRoute for devtron dashboard"
```

---

## Task 5: Add Makefile targets

**Files:**
- Modify: `terraform/Makefile` — add `plan-devtron`, `apply-devtron`, `debug-devtron` targets; extend `plan-ingress` and `apply-ingress` to include the new IngressRoute.

- [ ] **Step 1: Add `plan-devtron` target**

Use the Edit tool on `terraform/Makefile`. Find this existing block (around line 688):

```makefile
plan-homepage: check-vars check-init ## Plan Homepage dashboard
	@echo "Planning Homepage..."
	terraform plan \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage
```

Insert a new target immediately after it (before the next `plan-*` target), so the file contains:

```makefile
plan-homepage: check-vars check-init ## Plan Homepage dashboard
	@echo "Planning Homepage..."
	terraform plan \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage

plan-devtron: check-vars check-init ## Plan Devtron dashboard
	@echo "Planning Devtron..."
	terraform plan \
		-target=kubernetes_namespace.devtron \
		-target=helm_release.devtron
```

- [ ] **Step 2: Extend both `plan-ingress` and `apply-ingress` target lists in one edit**

The same line `-target=kubernetes_manifest.ingressroute_homepage \` appears twice in the Makefile — once in the `plan-ingress` target (around line 751) and once in the `apply-ingress` target (around line 1114). Both need the same follow-up line. Use the Edit tool with `replace_all: true`:

- `old_string` (exact):
  ```
  		-target=kubernetes_manifest.ingressroute_homepage \
  ```
  (Note: leading whitespace is TWO tabs, matching surrounding lines.)

- `new_string` (exact):
  ```
  		-target=kubernetes_manifest.ingressroute_homepage \
  		-target=kubernetes_manifest.ingressroute_devtron \
  ```

- `replace_all: true`

Expected: both occurrences updated in a single edit.

After the edit, verify:

Run: `grep -n "ingressroute_devtron" Makefile`
Expected: two line numbers printed — one inside the `plan-ingress` block, one inside the `apply-ingress` block.

- [ ] **Step 3: Add `apply-devtron` target**

Find this existing block (around line 1051):

```makefile
apply-homepage: check-vars check-init ## Deploy Homepage dashboard
	@echo "Deploying Homepage..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage
```

Insert a new target immediately after it:

```makefile
apply-homepage: check-vars check-init ## Deploy Homepage dashboard
	@echo "Deploying Homepage..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage

apply-devtron: check-vars check-init ## Deploy Devtron dashboard
	@echo "Deploying Devtron..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.devtron \
		-target=helm_release.devtron
```

- [ ] **Step 4: Add `debug-devtron` target**

Find this existing block (around line 1254):

```makefile
debug-runners: ## Debug GitHub runners (ARC) — show controller, listeners, runner pods
	@echo "=== ARC controller ==="
	kubectl get pods -n arc-system -l app.kubernetes.io/name=gha-rs-controller
	@echo ""
	@echo "=== Runner listeners ==="
	kubectl get pods -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener
	@echo ""
	@echo "=== Runner pods (ephemeral) ==="
	kubectl get pods -n arc-runners -l app.kubernetes.io/component=runner
	@echo ""
	@echo "=== AutoscalingRunnerSets ==="
	kubectl get autoscalingrunnersets.actions.github.com -n arc-runners
	@echo ""
	@echo "=== Controller logs (tail 50) ==="
	kubectl logs -n arc-system -l app.kubernetes.io/name=gha-rs-controller --tail=50
```

Insert a new target immediately after it:

```makefile
debug-runners: ## Debug GitHub runners (ARC) — show controller, listeners, runner pods
	@echo "=== ARC controller ==="
	kubectl get pods -n arc-system -l app.kubernetes.io/name=gha-rs-controller
	@echo ""
	@echo "=== Runner listeners ==="
	kubectl get pods -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener
	@echo ""
	@echo "=== Runner pods (ephemeral) ==="
	kubectl get pods -n arc-runners -l app.kubernetes.io/component=runner
	@echo ""
	@echo "=== AutoscalingRunnerSets ==="
	kubectl get autoscalingrunnersets.actions.github.com -n arc-runners
	@echo ""
	@echo "=== Controller logs (tail 50) ==="
	kubectl logs -n arc-system -l app.kubernetes.io/name=gha-rs-controller --tail=50

debug-devtron: ## Debug Devtron — show pods, PVCs, service, and admin password
	@echo "=== Devtron Pods ==="
	@kubectl get pods -n devtroncd -o wide 2>/dev/null || echo "Devtron namespace not found"
	@echo ""
	@echo "=== Devtron PVCs ==="
	@kubectl get pvc -n devtroncd 2>/dev/null || echo "No Devtron PVCs"
	@echo ""
	@echo "=== Devtron Services ==="
	@kubectl get svc -n devtroncd 2>/dev/null || echo "No Devtron services"
	@echo ""
	@echo "=== Devtron Admin Password ==="
	@kubectl -n devtroncd get secret devtron-secret -o jsonpath='{.data.ACD_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || echo "devtron-secret not found (pods may still be initializing)"
	@echo ""
```

- [ ] **Step 5: Verify Makefile parses**

Run: `make -n plan-devtron`
Expected: Prints the planned commands (the `@echo` line and the `terraform plan -target=... -target=...` line), without executing them. No `make: *** No rule to make target` errors.

Run: `make -n apply-devtron`
Expected: Same as above for the apply target.

Run: `make -n debug-devtron`
Expected: Prints the kubectl commands without executing them.

- [ ] **Step 6: Commit**

```bash
git add terraform/Makefile
git commit -m "feat(devtron): add devtron make targets and wire into ingress targets"
```

---

## Task 6: Final validation

**Files:** (read-only validation)

- [ ] **Step 1: Format the entire Terraform directory**

Run: `terraform fmt`
Expected: No output (all files already formatted). If any filenames print, run `git status` to confirm they're tracked files, then `git add` + commit with message `style: terraform fmt`.

- [ ] **Step 2: Validate**

Run: `terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Plan the full project with Devtron disabled**

This is the baseline case — `devtron_enabled` is `false` by default, so the plan should show **zero** Devtron-related resources added.

Run: `terraform plan -out=/tmp/tfplan-devtron-disabled.bin | tail -30`
Expected: Summary line similar to `Plan: 0 to add, 0 to change, 0 to destroy.` If there are non-zero numbers, inspect the full output — they must be unrelated to Devtron. Any line mentioning `devtron` is a bug in this plan's implementation; stop and investigate.

- [ ] **Step 4: Plan with Devtron enabled (simulated)**

Run: `terraform plan -var='devtron_enabled=true' -out=/tmp/tfplan-devtron-enabled.bin | tail -60`
Expected: A summary line like `Plan: 4 to add, 0 to change, 0 to destroy.` with these four resources being added:
- `kubernetes_namespace.devtron[0]`
- `helm_release.devtron[0]`
- `kubernetes_manifest.ingressroute_devtron[0]`
- `azurerm_dns_a_record.services["devtron"]`

If you see more than 4 adds or unrelated changes, inspect carefully — the extra changes may legitimately be from other services, but flag anything that looks like a regression.

Clean up the plan files afterwards:

Run: `rm -f /tmp/tfplan-devtron-disabled.bin /tmp/tfplan-devtron-enabled.bin`
Expected: No output.

- [ ] **Step 5: Final commit (if `terraform fmt` changed anything in Step 1)**

If Step 1 produced no output, skip this step. Otherwise:

```bash
git status
git add <files printed by fmt>
git commit -m "style: terraform fmt"
```

---

## Post-plan deployment (out of scope for this plan — user runs manually)

Once the plan is merged, the user flips `devtron_enabled = true` in `terraform.tfvars` and runs, in order:

1. `make apply-devtron` — creates the namespace and Helm release. Wait 3–5 minutes for Postgres PVC provisioning and initial migrations.
2. `make apply-ingress` — creates the IngressRoute once the `devtron-service` ClusterIP exists.
3. `make apply` (or apply the DNS records via the default apply path) — creates the Azure DNS A record for `devtron.${traefik_domain}`.
4. Retrieve the admin password: `make debug-devtron`
5. Visit `https://devtron.${traefik_domain}`, complete the OAuth flow at `auth.${traefik_domain}`, then log into Devtron as user `admin` with the retrieved password.

If any Devtron pod is in `CrashLoopBackOff`, re-run `make debug-devtron` for pod status and check `kubectl logs -n devtroncd <pod>` for specifics. Most common cause: Postgres PVC not yet bound because Longhorn is still provisioning — wait another minute and recheck.
