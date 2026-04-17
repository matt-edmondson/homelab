# Self-Hosted GitHub Runners (ARC) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy GitHub's modern Actions Runner Controller (ARC) to the homelab cluster with auto-scaling ephemeral runners for the `ktsu-dev` organization and `matt-edmondson/CardApp` repository, authenticated via a GitHub App, with a Docker-in-Docker sidecar so container-build workflows work.

**Architecture:** One Terraform file (`terraform/github-runners.tf`) drives everything. Two Helm releases: one singleton controller in `arc-system`, then one `gha-runner-scale-set` per scale set in `arc-runners` (ktsu-dev org-scoped, cardapp repo-scoped). Each scale set runs `min=0 / max=25` ephemeral runners with a privileged `dind` sidecar.

**Tech Stack:** Terraform (hashicorp/kubernetes ~> 2.38, hashicorp/helm ~> 3.0.2), Helm charts from `oci://ghcr.io/actions/actions-runner-controller-charts/*`, Kubernetes Secrets for GitHub App credentials.

**Design spec:** `docs/superpowers/specs/2026-04-17-github-runners-arc-design.md`

---

## Pre-flight: Chart version verification

Before starting Task 1, confirm the latest `gha-runner-scale-set-controller` and `gha-runner-scale-set` chart versions by visiting the [ARC releases page](https://github.com/actions/actions-runner-controller/releases). The plan pins **`0.11.0`** as a known-stable default (late 2024 release). If a newer stable release is out, bump the default in Task 1's variable definitions. Both charts always release with matching version numbers.

---

## Task 1: Create github-runners.tf skeleton — header, variables, namespaces

**Files:**
- Create: `terraform/github-runners.tf`

- [ ] **Step 1: Create the file with the standard header and variable block**

Create `terraform/github-runners.tf` with this exact content:

```hcl
# =============================================================================
# GitHub Self-Hosted Runners — Actions Runner Controller (ARC)
# =============================================================================
# Deploys the modern GitHub ARC (gha-runner-scale-set) with two scale sets:
#   - ktsu-dev-runners   — org-scoped, covers all ktsu-dev/* repos
#   - cardapp-runners    — repo-scoped to matt-edmondson/CardApp
#
# Runners are ephemeral (one pod per job), scale 0→N on demand, and include
# a privileged docker:dind sidecar so workflows can build container images.
#
# Authentication: GitHub App (one App installed on both the ktsu-dev org and
# the CardApp repo). Per-install credentials live in separate K8s secrets.
#
# Spec: docs/superpowers/specs/2026-04-17-github-runners-arc-design.md
# =============================================================================

# Variables — enable flag and chart versions
variable "arc_enabled" {
  description = "Enable Actions Runner Controller and scale sets"
  type        = bool
  default     = true
}

variable "arc_controller_chart_version" {
  description = "Helm chart version for gha-runner-scale-set-controller"
  type        = string
  default     = "0.11.0"
}

variable "arc_runner_set_chart_version" {
  description = "Helm chart version for gha-runner-scale-set (should match controller version)"
  type        = string
  default     = "0.11.0"
}

# Variables — scaling
variable "arc_ktsu_dev_max_runners" {
  description = "Maximum concurrent runners for the ktsu-dev org scale set"
  type        = number
  default     = 25
}

variable "arc_cardapp_max_runners" {
  description = "Maximum concurrent runners for the matt-edmondson/CardApp scale set"
  type        = number
  default     = 25
}

# Variables — GitHub App credentials
variable "arc_github_app_id" {
  description = "GitHub App ID (numeric). Create the App under your personal account with permissions: repo Actions/Administration/Metadata + org Self-hosted runners."
  type        = string
  sensitive   = true
  default     = ""
}

variable "arc_github_app_installation_id_ktsu_dev" {
  description = "GitHub App installation ID for the ktsu-dev organization install"
  type        = string
  sensitive   = true
  default     = ""
}

variable "arc_github_app_installation_id_cardapp" {
  description = "GitHub App installation ID for the matt-edmondson/CardApp install"
  type        = string
  sensitive   = true
  default     = ""
}

variable "arc_github_app_private_key" {
  description = "Contents of the GitHub App private key .pem file (full PEM, including BEGIN/END lines)"
  type        = string
  sensitive   = true
  default     = ""
}

# Namespaces
resource "kubernetes_namespace" "arc_system" {
  count = var.arc_enabled ? 1 : 0

  metadata {
    name = "arc-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "arc-system"
    })
  }
}

resource "kubernetes_namespace" "arc_runners" {
  count = var.arc_enabled ? 1 : 0

  metadata {
    name = "arc-runners"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "arc-runners"
    })
  }
}
```

- [ ] **Step 2: Format and validate**

Run from `terraform/`:

```bash
make format
make validate
```

Expected: `terraform fmt` prints nothing (no formatting needed); `terraform validate` prints `Success! The configuration is valid.`

- [ ] **Step 3: Plan and verify the skeleton adds only the two namespaces**

Run from `terraform/`:

```bash
terraform plan -target=kubernetes_namespace.arc_system -target=kubernetes_namespace.arc_runners
```

Expected: `Plan: 2 to add, 0 to change, 0 to destroy.` The plan shows `arc-system` and `arc-runners` namespaces with `managed-by=terraform` and `environment=homelab` labels.

- [ ] **Step 4: Commit**

```bash
git add terraform/github-runners.tf
git commit -m "feat: add ARC skeleton with variables and namespaces"
```

---

## Task 2: Add GitHub App credential secrets

**Files:**
- Modify: `terraform/github-runners.tf` (append)

- [ ] **Step 1: Append the two secret resources**

Append to `terraform/github-runners.tf`:

```hcl
# GitHub App credential secrets — one per scale set
# The gha-runner-scale-set chart reads these three keys: github_app_id,
# github_app_installation_id, github_app_private_key.

resource "kubernetes_secret" "arc_ktsu_dev_github_app" {
  count = var.arc_enabled ? 1 : 0

  metadata {
    name      = "arc-ktsu-dev-github-app"
    namespace = kubernetes_namespace.arc_runners[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    github_app_id              = var.arc_github_app_id
    github_app_installation_id = var.arc_github_app_installation_id_ktsu_dev
    github_app_private_key     = var.arc_github_app_private_key
  }

  depends_on = [kubernetes_namespace.arc_runners]
}

resource "kubernetes_secret" "arc_cardapp_github_app" {
  count = var.arc_enabled ? 1 : 0

  metadata {
    name      = "arc-cardapp-github-app"
    namespace = kubernetes_namespace.arc_runners[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    github_app_id              = var.arc_github_app_id
    github_app_installation_id = var.arc_github_app_installation_id_cardapp
    github_app_private_key     = var.arc_github_app_private_key
  }

  depends_on = [kubernetes_namespace.arc_runners]
}
```

- [ ] **Step 2: Format and validate**

```bash
make format
make validate
```

Expected: both succeed.

- [ ] **Step 3: Plan and verify the two secrets appear**

```bash
terraform plan \
  -target=kubernetes_secret.arc_ktsu_dev_github_app \
  -target=kubernetes_secret.arc_cardapp_github_app
```

Expected: `Plan: 2 to add, 0 to change, 0 to destroy.` (Namespaces already planned from Task 1 show as part of the dependency chain.) Secrets planned with empty data values (populated after Task 9).

- [ ] **Step 4: Commit**

```bash
git add terraform/github-runners.tf
git commit -m "feat: add GitHub App credential secrets for ARC scale sets"
```

---

## Task 3: Add ARC controller Helm release

**Files:**
- Modify: `terraform/github-runners.tf` (append)

- [ ] **Step 1: Append the controller Helm release**

Append to `terraform/github-runners.tf`:

```hcl
# ARC Controller — singleton, watches AutoscalingRunnerSet CRs cluster-wide
resource "helm_release" "arc_controller" {
  count = var.arc_enabled ? 1 : 0

  name       = "arc"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = var.arc_controller_chart_version
  namespace  = kubernetes_namespace.arc_system[0].metadata[0].name

  # Default values are sufficient — controller watches all namespaces by default.
  # Chart docs: https://github.com/actions/actions-runner-controller/blob/master/charts/gha-runner-scale-set-controller/README.md

  depends_on = [kubernetes_namespace.arc_system]
}
```

- [ ] **Step 2: Format and validate**

```bash
make format
make validate
```

Expected: both succeed.

- [ ] **Step 3: Plan and verify the controller release**

```bash
terraform plan -target=helm_release.arc_controller
```

Expected: `Plan: N to add, 0 to change, 0 to destroy.` (N includes the namespace + the helm_release.) The plan output shows `chart = "gha-runner-scale-set-controller"`, `version = "0.11.0"`, `namespace = "arc-system"`.

- [ ] **Step 4: Commit**

```bash
git add terraform/github-runners.tf
git commit -m "feat: add ARC controller helm release"
```

---

## Task 4: Add ktsu-dev org-scoped runner scale set

**Files:**
- Modify: `terraform/github-runners.tf` (append)

- [ ] **Step 1: Append the ktsu-dev scale set Helm release**

Append to `terraform/github-runners.tf`:

```hcl
# Scale set — ktsu-dev organization
# Workflows target these runners with: runs-on: ktsu-dev-runners
resource "helm_release" "arc_ktsu_dev" {
  count = var.arc_enabled ? 1 : 0

  name       = "ktsu-dev-runners"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = var.arc_runner_set_chart_version
  namespace  = kubernetes_namespace.arc_runners[0].metadata[0].name

  values = [
    yamlencode({
      githubConfigUrl    = "https://github.com/ktsu-dev"
      githubConfigSecret = kubernetes_secret.arc_ktsu_dev_github_app[0].metadata[0].name

      runnerScaleSetName = "ktsu-dev-runners"

      minRunners = 0
      maxRunners = var.arc_ktsu_dev_max_runners

      # DinD mode — chart injects a privileged docker:dind sidecar and wires
      # DOCKER_HOST into the runner container. No custom sidecar needed.
      containerMode = {
        type = "dind"
      }

      template = {
        spec = {
          containers = [
            {
              name  = "runner"
              image = "ghcr.io/actions/actions-runner:latest"
              command = ["/home/runner/run.sh"]
              resources = {
                requests = {
                  cpu    = "250m"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = "2"
                  memory = "4Gi"
                }
              }
            },
          ]
        }
      }
    }),
  ]

  depends_on = [
    helm_release.arc_controller,
    kubernetes_secret.arc_ktsu_dev_github_app,
  ]
}
```

- [ ] **Step 2: Format and validate**

```bash
make format
make validate
```

Expected: both succeed.

- [ ] **Step 3: Plan and verify the scale set release**

```bash
terraform plan -target=helm_release.arc_ktsu_dev
```

Expected: `Plan: N to add, 0 to change, 0 to destroy.` Plan output shows `chart = "gha-runner-scale-set"`, `name = "ktsu-dev-runners"`, and a `values` block containing `githubConfigUrl = "https://github.com/ktsu-dev"` and `containerMode.type = "dind"`.

- [ ] **Step 4: Commit**

```bash
git add terraform/github-runners.tf
git commit -m "feat: add ktsu-dev org-scoped runner scale set"
```

---

## Task 5: Add matt-edmondson/CardApp repo-scoped runner scale set

**Files:**
- Modify: `terraform/github-runners.tf` (append)

- [ ] **Step 1: Append the cardapp scale set Helm release**

Append to `terraform/github-runners.tf`:

```hcl
# Scale set — matt-edmondson/CardApp
# Workflows target these runners with: runs-on: cardapp-runners
resource "helm_release" "arc_cardapp" {
  count = var.arc_enabled ? 1 : 0

  name       = "cardapp-runners"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = var.arc_runner_set_chart_version
  namespace  = kubernetes_namespace.arc_runners[0].metadata[0].name

  values = [
    yamlencode({
      githubConfigUrl    = "https://github.com/matt-edmondson/CardApp"
      githubConfigSecret = kubernetes_secret.arc_cardapp_github_app[0].metadata[0].name

      runnerScaleSetName = "cardapp-runners"

      minRunners = 0
      maxRunners = var.arc_cardapp_max_runners

      containerMode = {
        type = "dind"
      }

      template = {
        spec = {
          containers = [
            {
              name  = "runner"
              image = "ghcr.io/actions/actions-runner:latest"
              command = ["/home/runner/run.sh"]
              resources = {
                requests = {
                  cpu    = "250m"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = "2"
                  memory = "4Gi"
                }
              }
            },
          ]
        }
      }
    }),
  ]

  depends_on = [
    helm_release.arc_controller,
    kubernetes_secret.arc_cardapp_github_app,
  ]
}
```

- [ ] **Step 2: Format and validate**

```bash
make format
make validate
```

Expected: both succeed.

- [ ] **Step 3: Full plan — verify the whole file composes correctly**

```bash
terraform plan \
  -target=kubernetes_namespace.arc_system \
  -target=kubernetes_namespace.arc_runners \
  -target=kubernetes_secret.arc_ktsu_dev_github_app \
  -target=kubernetes_secret.arc_cardapp_github_app \
  -target=helm_release.arc_controller \
  -target=helm_release.arc_ktsu_dev \
  -target=helm_release.arc_cardapp
```

Expected: `Plan: 7 to add, 0 to change, 0 to destroy.` All seven resources planned; no cycles or missing dependencies.

- [ ] **Step 4: Commit**

```bash
git add terraform/github-runners.tf
git commit -m "feat: add CardApp repo-scoped runner scale set"
```

---

## Task 6: Update terraform.tfvars.example

**Files:**
- Modify: `terraform/terraform.tfvars.example`

- [ ] **Step 1: Append the ARC section at the end of the file**

Append these lines to `terraform/terraform.tfvars.example`:

```hcl

# GitHub Self-Hosted Runners (ARC — Actions Runner Controller)
# -----------------------------------------------------------------------------
# Setup steps:
#   1. Create a GitHub App under your personal account.
#      - Repository permissions: Actions (read), Administration (read/write), Metadata (read)
#      - Organization permissions: Self-hosted runners (read/write)
#      - Webhook: NOT required (ARC uses long-polling, not webhooks)
#   2. Generate a private key (.pem) and download it.
#   3. Install the App on:
#        - The `ktsu-dev` organization (all repos)
#        - The `matt-edmondson/CardApp` repository
#   4. Find each Installation ID from the install URL:
#        https://github.com/organizations/ktsu-dev/settings/installations/<ID>
#        https://github.com/settings/installations/<ID>
#   5. Populate the four values below. The private key is the full PEM contents
#      (use heredoc syntax: arc_github_app_private_key = <<EOT ... EOT).
# -----------------------------------------------------------------------------
#arc_enabled                             = true     # Set to false to disable ARC
#arc_controller_chart_version            = "0.11.0"
#arc_runner_set_chart_version            = "0.11.0" # Must match controller version
#arc_ktsu_dev_max_runners                = 25       # Peak concurrent runners for ktsu-dev org
#arc_cardapp_max_runners                 = 25       # Peak concurrent runners for CardApp repo
#arc_github_app_id                       = "123456"
#arc_github_app_installation_id_ktsu_dev = "12345678"
#arc_github_app_installation_id_cardapp  = "87654321"
#arc_github_app_private_key              = <<EOT
#-----BEGIN RSA PRIVATE KEY-----
#MIIEpAIBAAKCAQEA...
#-----END RSA PRIVATE KEY-----
#EOT
```

- [ ] **Step 2: Verify the file is still valid HCL**

```bash
terraform fmt -check terraform.tfvars.example
```

Expected: no output (comments are valid HCL; `-check` returns 0 when nothing needs reformatting). If it reports the file needs formatting, run `terraform fmt terraform.tfvars.example` and re-check.

- [ ] **Step 3: Commit**

```bash
git add terraform/terraform.tfvars.example
git commit -m "docs: add ARC variables to tfvars example"
```

---

## Task 7: Add Makefile targets — plan-runners, apply-runners, debug-runners

**Files:**
- Modify: `terraform/Makefile`

- [ ] **Step 1: Locate the insertion points**

The existing Makefile groups targets into three sections: `plan-<component>`, `apply-<component>`, and `debug-<component>`. Find section boundaries with:

```bash
grep -n "^plan-\|^apply-\|^debug-" terraform/Makefile | head -40
```

Pick any existing adjacent block in each section to model the new targets on. The plan target for ARC slots near the end of the plan section (e.g., after `plan-homepage`, around line 697). The apply and debug targets go in their respective sections following the same pattern.

- [ ] **Step 2: Add the plan target**

Insert after the `plan-homepage` block (around line 697):

```make
plan-runners: check-vars check-init ## Plan GitHub self-hosted runners (ARC)
	@echo "Planning GitHub runners (ARC)..."
	terraform plan \
		-target=kubernetes_namespace.arc_system \
		-target=kubernetes_namespace.arc_runners \
		-target=kubernetes_secret.arc_ktsu_dev_github_app \
		-target=kubernetes_secret.arc_cardapp_github_app \
		-target=helm_release.arc_controller \
		-target=helm_release.arc_ktsu_dev \
		-target=helm_release.arc_cardapp
```

- [ ] **Step 3: Add the apply target**

Insert in the apply section (parallel to where plan-runners was inserted):

```make
apply-runners: check-vars check-init ## Deploy GitHub self-hosted runners (ARC)
	@echo "Deploying GitHub runners (ARC)..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.arc_system \
		-target=kubernetes_namespace.arc_runners \
		-target=kubernetes_secret.arc_ktsu_dev_github_app \
		-target=kubernetes_secret.arc_cardapp_github_app \
		-target=helm_release.arc_controller \
		-target=helm_release.arc_ktsu_dev \
		-target=helm_release.arc_cardapp
```

- [ ] **Step 4: Add the debug target**

Insert in the debug section:

```make
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

- [ ] **Step 5: Verify Makefile parses**

```bash
cd terraform && make -n plan-runners apply-runners debug-runners
```

Expected: `make -n` prints the commands each target would run without executing them. All three targets print their `terraform plan` / `terraform apply` / `kubectl` commands without errors.

- [ ] **Step 6: Commit**

```bash
git add terraform/Makefile
git commit -m "feat: add make targets for ARC (plan-runners, apply-runners, debug-runners)"
```

---

## Task 8: Update CLAUDE.md architecture section

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add one line to the File Organization list**

The `CLAUDE.md` File Organization list has entries for every `.tf` file. Add a new entry in alphabetical order (between `github-runners` would slot after `flaresolverr.tf` and before `homepage.tf` / `ingress.tf`... actually between `flaresolverr.tf` and `ingress.tf`):

```markdown
- [github-runners.tf](terraform/github-runners.tf) — GitHub Actions Runner Controller (ARC) — controller + two `gha-runner-scale-set` Helm releases (ktsu-dev org-scoped, matt-edmondson/CardApp repo-scoped), DinD sidecar, GitHub App auth, no ingress
```

Find the insertion point with:

```bash
grep -n "flaresolverr.tf\|homepage.tf\|ingress.tf" CLAUDE.md
```

Insert the new bullet so the list stays roughly alphabetical.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document github-runners.tf in CLAUDE.md"
```

---

## Task 9: Create and install the GitHub App (manual, user action)

**Files:** none (GitHub UI)

This is a manual setup step that must happen before `make apply-runners` can successfully register runners. The engineer should hand this task to the homelab operator.

- [ ] **Step 1: Create the GitHub App**

Go to https://github.com/settings/apps/new and fill in:

- **GitHub App name:** `homelab-arc-runners` (or similar — must be globally unique)
- **Homepage URL:** anything (e.g., `https://github.com/matt-edmondson/homelab`)
- **Webhook:** **Uncheck "Active"** — ARC uses long-polling, no webhook required.
- **Repository permissions:**
  - Actions: Read and write
  - Administration: Read and write
  - Metadata: Read-only
- **Organization permissions:**
  - Self-hosted runners: Read and write
- **Where can this GitHub App be installed?** Any account.

Click **Create GitHub App**.

- [ ] **Step 2: Capture the App ID and generate a private key**

On the app's settings page:
- Copy the numeric **App ID** (top of page). Save it.
- Scroll to **Private keys** → **Generate a private key**. A `.pem` file downloads. Save it securely.

- [ ] **Step 3: Install the App on `ktsu-dev`**

On the app page, click **Install App** (left sidebar) → find `ktsu-dev` in the account list → **Install**. Choose "All repositories" unless you want a subset.

After install, the URL bar shows:
```
https://github.com/organizations/ktsu-dev/settings/installations/<INSTALLATION_ID>
```

Copy that numeric `INSTALLATION_ID`. Save it as the **ktsu-dev installation ID**.

- [ ] **Step 4: Install the App on `matt-edmondson/CardApp`**

Same page, **Install App** again → `matt-edmondson` (personal account) → **Only select repositories** → `CardApp` → **Install**.

After install, the URL:
```
https://github.com/settings/installations/<INSTALLATION_ID>
```

Copy this different `INSTALLATION_ID`. Save it as the **CardApp installation ID**.

- [ ] **Step 5: Verify captured values**

You should now have:
- App ID (numeric, e.g., `123456`)
- Private key PEM file contents
- ktsu-dev installation ID (numeric)
- CardApp installation ID (numeric)

---

## Task 10: Populate terraform.tfvars and deploy

**Files:**
- Modify: `terraform/terraform.tfvars` (gitignored, not committed)

- [ ] **Step 1: Add the four ARC values to terraform.tfvars**

Append to `terraform/terraform.tfvars` (using actual values from Task 9):

```hcl
arc_github_app_id                       = "123456"
arc_github_app_installation_id_ktsu_dev = "12345678"
arc_github_app_installation_id_cardapp  = "87654321"
arc_github_app_private_key              = <<EOT
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
(full PEM contents)
-----END RSA PRIVATE KEY-----
EOT
```

- [ ] **Step 2: Plan and review**

```bash
cd terraform && make plan-runners
```

Expected: `Plan: 7 to add, 0 to change, 0 to destroy.` Review that the secret data references look right (Terraform will mask the values as `(sensitive value)`).

- [ ] **Step 3: Apply**

```bash
make apply-runners
```

Expected: all 7 resources created. The Helm release outputs may take 1-2 minutes as the charts download and the controller + listener pods start.

---

## Task 11: Verify deployment health

**Files:** none (kubectl commands)

- [ ] **Step 1: Verify controller pod is running**

```bash
kubectl get pods -n arc-system
```

Expected: one pod named like `arc-gha-rs-controller-<hash>` with `STATUS=Running` and `READY=1/1`.

- [ ] **Step 2: Verify both listener pods are running**

```bash
kubectl get pods -n arc-runners
```

Expected: two pods with names containing `listener` and `STATUS=Running`, `READY=1/1`:
- `ktsu-dev-runners-<hash>-listener`
- `cardapp-runners-<hash>-listener`

- [ ] **Step 3: Check listener logs confirm registration**

```bash
kubectl logs -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener --tail=20
```

Expected: each listener logs `"Listening for messages"` or similar. No `401 Unauthorized` or `404 Not Found` errors (those indicate App permissions or installation ID issues).

- [ ] **Step 4: Verify scale sets appear in GitHub**

Visit:
- `https://github.com/organizations/ktsu-dev/settings/actions/runners` — `ktsu-dev-runners` scale set listed, 0 active runners.
- `https://github.com/matt-edmondson/CardApp/settings/actions/runners` — `cardapp-runners` scale set listed, 0 active runners.

- [ ] **Step 5: Run the debug target for a full snapshot**

```bash
cd terraform && make debug-runners
```

Expected: controller Running, both listeners Running, 0 runner pods, 2 AutoscalingRunnerSets, no error lines in controller logs.

---

## Task 12: Functional test — migrate one lightweight workflow

**Files:**
- Modify: one chosen workflow file under `C:\dev\ktsu-dev\<pick-a-repo>\.github\workflows\`

- [ ] **Step 1: Pick a low-risk workflow to migrate**

Open `C:\dev\ktsu-dev\Abstractions\.github\workflows\dependabot-merge.yml` (or any ktsu-dev `dependabot-merge.yml`). These are short and idempotent.

Change the `runs-on:` line from `ubuntu-latest` to `ktsu-dev-runners`.

- [ ] **Step 2: Commit and push the workflow change**

Commit inside that repo (not homelab):

```bash
cd /c/dev/ktsu-dev/Abstractions
git checkout -b test/arc-runners
git commit -am "test: route dependabot-merge to self-hosted ktsu-dev-runners"
git push origin test/arc-runners
```

- [ ] **Step 3: Trigger the workflow**

Either open a PR on the branch, or use `gh workflow run dependabot-merge.yml --ref test/arc-runners` if the workflow supports `workflow_dispatch`.

- [ ] **Step 4: Watch a runner pod spin up**

In a separate terminal:

```bash
kubectl get pods -n arc-runners -w
```

Expected within ~30s of job queuing: a new pod named like `ktsu-dev-runners-<hash>-runner-<hash>` appears in `ContainerCreating`, then `Running`. The pod terminates within a few seconds of job completion and is garbage-collected.

- [ ] **Step 5: Verify job succeeded on GitHub**

Open the Actions tab for the workflow. The job should show as run on `ktsu-dev-runners` (under the runner label list) and complete successfully.

- [ ] **Step 6: Revert the test change OR merge if you want it in main**

If this was just a smoke test:

```bash
cd /c/dev/ktsu-dev/Abstractions
git checkout main
git branch -D test/arc-runners
git push origin :test/arc-runners
```

If you want the change to stick, open a normal PR and merge.

---

## Task 13: Functional test — CardApp docker build on self-hosted

**Files:**
- Modify: `C:\dev\matt-edmondson\CardApp\.github\workflows\docker.yml`

- [ ] **Step 1: Change runs-on**

In `docker.yml`, change `runs-on: ubuntu-latest` to `runs-on: cardapp-runners`.

- [ ] **Step 2: Commit on a branch and push**

```bash
cd /c/dev/matt-edmondson/CardApp
git checkout -b test/arc-docker
git commit -am "test: run docker build on self-hosted cardapp-runners"
git push origin test/arc-docker
```

- [ ] **Step 3: Open a PR or push to main (per your preference) to trigger**

The `docker.yml` workflow triggers on `push: branches: [main]`. To trigger without merging, temporarily add `test/arc-docker` to the branch list, OR merge the PR.

- [ ] **Step 4: Watch the runner pod + dind sidecar**

```bash
kubectl get pods -n arc-runners -w
```

When a pod starts, describe it to confirm both containers are present:

```bash
kubectl describe pod -n arc-runners -l app.kubernetes.io/component=runner | head -50
```

Expected: two containers listed — one `runner`, one `dind`. The `dind` container has `privileged: true` in its security context.

- [ ] **Step 5: Verify docker build succeeded**

In the Actions UI, the `Build and push Docker Images` job completed, and both `cardapp-backend:latest` and `cardapp-frontend:latest` were pushed to `ghcr.io/matt-edmondson/`.

- [ ] **Step 6: Keep or revert the runs-on change**

If the test succeeded and you want CardApp's docker.yml to permanently use self-hosted runners, merge the branch. Otherwise revert:

```bash
git checkout main
git branch -D test/arc-docker
git push origin :test/arc-docker
```

---

## Task 14: Final commit — mark rollout complete

**Files:** none

- [ ] **Step 1: Verify clean state**

```bash
cd /c/dev/matt-edmondson/homelab
git status
```

Expected: working tree clean (all commits from Tasks 1-8 already pushed).

- [ ] **Step 2: Tag the rollout milestone (optional)**

```bash
git tag -a arc-v1 -m "ARC self-hosted runners rollout complete"
git push origin arc-v1
```

Rollout done. Additional repos can be added later by copying the `helm_release.arc_cardapp` block and swapping in a new installation ID.

---

## Self-review checklist

- [x] **Spec coverage:**
  - Architecture (ARC controller + 2 scale sets) → Tasks 1-5
  - Namespaces (arc-system, arc-runners) → Task 1
  - Scale sets with names, scope, min/max, labels → Tasks 4-5
  - Runner pod spec with DinD + resources → Tasks 4-5 (via `containerMode.type=dind`)
  - GitHub App auth → Tasks 2, 9, 10
  - New `github-runners.tf` file → Tasks 1-5
  - Modified `terraform.tfvars.example` → Task 6
  - Modified `Makefile` → Task 7
  - CLAUDE.md update → Task 8
  - Rollout / testing → Tasks 9-13
- [x] **Placeholder scan:** no TBD/TODO; all code blocks complete.
- [x] **Type consistency:** resource names consistent across tasks (`arc_controller`, `arc_ktsu_dev`, `arc_cardapp`, `arc_system`, `arc_runners`, `arc_ktsu_dev_github_app`, `arc_cardapp_github_app`). Variable names consistent (`arc_enabled`, `arc_controller_chart_version`, etc.).
- [x] **DinD detail:** using `containerMode.type = "dind"` — the chart injects the privileged sidecar automatically, so the spec's "two containers + privileged dind" is satisfied without hand-rolling the sidecar.
