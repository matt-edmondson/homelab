# Self-Hosted GitHub Runners via Actions Runner Controller

**Date:** 2026-04-17
**Status:** Draft

## Summary

Deploy GitHub's Actions Runner Controller (ARC) to the homelab Kubernetes cluster to provide self-hosted Linux runners for the `ktsu-dev` organization and the `matt-edmondson/CardApp` repository. Runners are ephemeral (one pod per job), auto-scaling from 0 to a configurable maximum, authenticate to GitHub via a GitHub App, and include a Docker-in-Docker sidecar so container-build workflows work identically to GitHub-hosted runners.

## Goals

- Provide on-demand Linux runners at the `ktsu-dev` org level (covers all current and future repos in the org).
- Provide on-demand Linux runners for `matt-edmondson/CardApp` specifically.
- Support Docker image builds (CardApp's `docker.yml` uses `docker/build-push-action`).
- Absorb matrix-over-issues bursts of up to ~20 parallel jobs with modest queueing beyond that.
- Zero idle cost — runners scale to zero when idle.

## Non-goals

- **Windows runners.** The 188 `windows-latest` jobs in `ktsu-dev` keep using GitHub-hosted runners. Migrating them to Linux is a separate future effort.
- **Per-personal-repo runners beyond CardApp.** Other `matt-edmondson/*` repos can be added later by appending a scale set; not included in initial rollout.
- **Custom runner images.** The default `ghcr.io/actions/actions-runner` image is used; workflow steps install toolchains on demand (setup-dotnet, setup-node, etc.).
- **Ingress / DNS.** ARC is pull-based (outbound long-poll from the listener to GitHub); no inbound exposure is required.
- **GPU access, NFS media mounts, Longhorn PVCs.** Runners stay fully ephemeral and schedulable on any node.

## Architecture

### Components

Two Helm charts from the official ARC project:

- **`gha-runner-scale-set-controller`** — singleton controller that watches `AutoscalingRunnerSet` CRs and manages listener pods. Installed once in `arc-system`.
- **`gha-runner-scale-set`** — installed once per scale set in `arc-runners`. Each install creates an `AutoscalingRunnerSet` CR plus the listener pod that registers with GitHub and spawns runner pods on demand.

### Namespaces

| Namespace | Purpose |
|---|---|
| `arc-system` | ARC controller deployment. |
| `arc-runners` | Listener pods and ephemeral runner pods for all scale sets, plus GitHub App secrets. |

### Scale sets

| Scale set name | GitHub scope | Min | Max (default) | `runs-on` label |
|---|---|---|---|---|
| `ktsu-dev-runners` | org `ktsu-dev` | 0 | 25 | `ktsu-dev-runners` |
| `cardapp-runners` | repo `matt-edmondson/CardApp` | 0 | 25 | `cardapp-runners` |

Runners also carry the implicit `self-hosted`, `linux`, `x64` labels added by the runner binary.

Workflows opt in by changing `runs-on: ubuntu-latest` to `runs-on: ktsu-dev-runners` (or `cardapp-runners`). Unchanged workflows continue to use GitHub-hosted runners.

### Runner pod spec

Each runner pod runs two containers plus two `emptyDir` volumes.

| Container | Image | Privileged | Req CPU | Req mem | Limit CPU | Limit mem |
|---|---|---|---|---|---|---|
| `runner` | `ghcr.io/actions/actions-runner:latest` | no | 250m | 1Gi | 2 | 4Gi |
| `dind` | `docker:dind` | **yes** | 200m | 256Mi | 2 | 2Gi |

Total request per pod: **450m CPU / 1.25Gi memory.** At max (25 pods per scale set), a single scale set reserves ~11 CPU / 31Gi — fits on the `rainbow` node (32 CPU / 62Gi) with room for bursts via limits. Both scale sets running simultaneously at max would exceed a single node's capacity, but in practice the scheduler spreads across nodes and `min=0` keeps steady-state occupancy low.

**Volumes:**
- `emptyDir` mounted at `/home/runner/_work` — workspace, wiped per pod.
- `emptyDir` mounted at `/var/lib/docker` — Docker layer cache, wiped per pod.

**DinD configuration:** TLS disabled on `tcp://localhost:2375`; `runner` container has `DOCKER_HOST=tcp://localhost:2375`. Both containers share the pod network namespace so `localhost` works without a separate service.

**No `nodeSelector`.** Runners land wherever the scheduler places them. In practice most will land on `rainbow` because the Raspberry Pi nodes (`pi4`, `pi5`) have insufficient RAM and `k8s01`/`k8s02` have limited memory.

### Authentication

ARC authenticates to GitHub as a GitHub App (not a PAT). The App is created once under the user's personal account and installed separately on:
- The `ktsu-dev` organization.
- The `matt-edmondson/CardApp` repository.

Each install has its own Installation ID; both share the same App ID and private key.

**Required GitHub App permissions:**
- Repository: Actions (read), Administration (read/write), Metadata (read).
- Organization: Self-hosted runners (read/write).

Two Kubernetes secrets in `arc-runners`:
- `arc-ktsu-dev-github-app` — App ID, ktsu-dev installation ID, private key.
- `arc-cardapp-github-app` — App ID, CardApp installation ID, private key.

Each Helm release references its corresponding secret via `githubConfigSecret`.

### Data flow

1. A workflow job with `runs-on: ktsu-dev-runners` is queued on GitHub.
2. The ktsu-dev listener pod (long-polling GitHub's message queue API) receives a job-assigned message.
3. The listener tells the ARC controller to create a runner pod.
4. The runner pod starts (~20-30s cold start), registers ephemerally with GitHub, and picks up the job.
5. The job runs. `docker build` / `buildx` calls go to the DinD sidecar via `localhost:2375`.
6. Job completes. The runner deregisters and the pod terminates. `emptyDir` volumes are garbage collected.

Peak burst of 20 queued jobs: up to ~20 pods spin up in parallel (bounded by `max`). Total matrix wall time is roughly `(slowest job) + ~30s cold start`.

## Terraform structure

### New file

**`terraform/github-runners.tf`** — follows the one-concern-per-file convention. Contains:

- Variables: `arc_enabled`, `arc_controller_chart_version`, `arc_runner_set_chart_version`, `arc_ktsu_dev_max_runners`, `arc_cardapp_max_runners`, `arc_github_app_id`, `arc_github_app_installation_id_ktsu_dev`, `arc_github_app_installation_id_cardapp`, `arc_github_app_private_key`.
- `kubernetes_namespace` resources for `arc-system` and `arc-runners`.
- `kubernetes_secret` resources for the two GitHub App secrets.
- `helm_release` for the controller (chart: `oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller`).
- `helm_release` x2 for scale sets (chart: `oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set`), each with values defining min/max replicas and the runner pod template with the DinD sidecar.
- `depends_on` chaining scale sets to the controller.
- A `count = var.arc_enabled ? 1 : 0` guard on every resource (matches the `claudecluster_enabled` pattern).

All resources carry `var.common_labels`.

### Modified files

- **`terraform/terraform.tfvars.example`** — add the four sensitive GitHub App inputs and the three chart/sizing inputs, with comments pointing to where to create the GitHub App and find the install IDs.
- **`terraform/Makefile`** — add `plan-runners`, `apply-runners`, `debug-runners` targets matching the existing pattern (`-target=kubernetes_namespace.arc_system -target=...`).

### Chart versions

Pinned in tfvars with sensible defaults. Upgrades are explicit edits, matching how `longhorn_chart_version` and `monitoring_chart_version` are handled.

## Enablement and rollout

1. Create the GitHub App under the personal account. Install it on `ktsu-dev` and `matt-edmondson/CardApp`. Capture App ID, both Installation IDs, and the private key PEM.
2. Populate the four GitHub App tfvars in `terraform.tfvars`.
3. `make apply-runners`.
4. Verify `kubectl get pods -n arc-system` shows the controller `Running` and `kubectl get pods -n arc-runners` shows two listener pods `Running`.
5. In a ktsu-dev repo, change one lightweight workflow (e.g., `dependabot-merge.yml`) from `runs-on: ubuntu-latest` to `runs-on: ktsu-dev-runners`. Trigger it and watch `kubectl get pods -n arc-runners -w` — a runner pod should appear, pick up the job, and terminate.
6. Repeat for `matt-edmondson/CardApp` with a simple workflow before migrating `docker.yml`.

## Operational notes

- **Scaling the ceiling.** `arc_ktsu_dev_max_runners` and `arc_cardapp_max_runners` are tfvars. Bump and `make apply-runners` — no code change needed.
- **Disabling.** Set `arc_enabled = false` and re-apply to tear down all ARC resources.
- **Adding another personal repo.** Add a new `helm_release` block in `github-runners.tf` (copy the CardApp block, change name + installation-ID tfvar) and a new App installation on that repo.
- **Stuck pods.** ARC cleans up registrations on pod termination, but if a node is lost mid-job, the runner may linger in GitHub's UI as "offline" until the listener reconciles (typically a few minutes).

## Risks and trade-offs

- **Privileged DinD.** The DinD sidecar runs as a privileged container. In a homelab trust boundary this is acceptable; not suitable for multi-tenant environments.
- **Single cluster node carries most load.** Because `rainbow` has the bulk of the cluster's memory, runner workload concentrates there. If `rainbow` goes down, job throughput drops sharply until it recovers.
- **Cold start latency.** `min=0` means first-job-in latency includes pod scheduling + image pull + runner registration (~20-30s). Acceptable for CI; not suitable if sub-second start is a requirement.
- **Windows workflows stay on GitHub-hosted.** If GitHub's pricing for private-repo Windows minutes becomes a concern, migrate the .NET Workflow jobs to `ubuntu-latest` in a follow-up.
