# LocalAI Distributed Mode Migration

**Date:** 2026-05-12
**Files:** `terraform/localai.tf` (rewrite), `terraform/localai-postgres.tf` (new), `terraform/localai-nats.tf` (new), `terraform/terraform.tfvars.example`, `terraform/Makefile`

## Goal

Migrate the LocalAI deployment from the deprecated P2P / libp2p worker mode (`worker p2p-llama-cpp-rpc` + shared `TOKEN`) to the upstream **distributed mode** introduced in PR mudler/LocalAI#9124 (merged 2026-03-29, first released in v4.1.0 on 2026-04-02). The current floating image tag `latest-gpu-nvidia-cuda-13` pulled in v4.2.x, which removed the old worker subcommand structure, causing every worker pod to crash on startup with `local-ai: error: unexpected argument p2p-llama-cpp-rpc`.

Target feature scope: **inference + agents + MCP + skills + built-in RAG**. This requires the pgvector-enabled postgres image used by upstream's `docker-compose.distributed.yaml`, plus an agent-worker process for NATS-driven agent chat execution.

## Reference

Upstream `docker-compose.distributed.yaml` ([github.com/mudler/LocalAI](https://github.com/mudler/LocalAI/blob/master/docker-compose.distributed.yaml)) is the canonical reference for env vars, image tags, port layout, and DNS workarounds. This design translates that compose file into Kubernetes resources following this repo's conventions.

## Architecture

```
                    ┌──────────────────────┐
                    │   Traefik (existing) │
                    │   localai.ktsu.dev   │
                    └──────────┬───────────┘
                               │ HTTPS
                    ┌──────────▼───────────┐
                    │  localai (frontend)  │   stateless, --distributed
                    │  v4.2.1-aio-cpu      │   mounts NFS /models etc.
                    │  1 replica           │
                    └────┬──────────┬──────┘
                         │          │
              ┌──────────┘          └──────────┐
              │                                │
   ┌──────────▼──────────┐         ┌──────────▼──────────┐
   │  localai-postgres   │         │  localai-nats        │
   │  localrecall:       │         │  nats:2-alpine       │
   │  v0.5.5-postgresql  │         │  JetStream + monit.  │
   │  (pgvector)         │         │  Longhorn /data PVC  │
   │  Longhorn PVC       │         │                      │
   └─────────────────────┘         └──────────────────────┘
                ▲                                ▲
                │ auth + agent-pool              │ NATS coord
                │ vectors + node-registry        │ file-transfer signal
                │                                │
   ┌────────────┴──────────┐         ┌──────────┴────────────┐
   │  localai-worker-Ngpu  │         │  localai-agent-worker │
   │  DaemonSet per GPU    │         │  Deployment (CPU)     │
   │  tier (for_each)      │         │  1 replica            │
   │  hostPort 50050/50051 │         │  NATS-only, no probes │
   │  advertise NODE_IP    │         │  no Docker socket     │
   │  shared NFS /models   │         │                      │
   └───────────────────────┘         └───────────────────────┘
```

## Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Feature scope | Inference + agents + MCP + skills | User intent; matches compose exactly |
| Volume strategy | Shared NFS (frontend + workers see same `/models`, `/backends`, `/configuration`) | Reuses existing NFS layout; no model duplication; SmartRouter file staging is a no-op when paths match (per compose comment) |
| Worker network identity | DaemonSet + `hostPort` + `NODE_IP` advertise via downward API | Matches existing per-GPU-tier `for_each` DaemonSet; stable address per node; idiomatic with existing `kube-vip-ds`, `csi-nfs-node`, `crowdsec-agent` patterns |
| Image tag | Pin to explicit version `v4.2.1` (component-specific suffix appended) | Avoids the floating-tag silent-break that caused this incident; reproducible builds |
| Postgres image | `quay.io/mudler/localrecall:v0.5.5-postgresql` (Mudler's pgvector build) | Required for `LOCALAI_AGENT_POOL_VECTOR_ENGINE=postgres`; pinned tag from compose |
| NATS | Single replica, JetStream enabled, Longhorn PVC for `/data` | Single user homelab; JetStream clustering needs 3+ nodes and isn't justified |
| Agent worker docker socket | **Skip** (omit the compose's `apt-get install docker.io` entrypoint) | We don't run `docker run` MCP stdio servers; HTTP/SSE MCPs work without Docker access; avoids mounting host socket |
| Frontend image | Switch from GPU-CUDA to `aio-cpu` flavor | Frontend doesn't compute — that's what workers do |

## Components

### Postgres (`terraform/localai-postgres.tf`)

- **Image:** `quay.io/mudler/localrecall:v0.5.5-postgresql`
- **Secret `localai-postgres`** (`kubernetes_secret.localai_postgres`):
  - `POSTGRES_USER=localai`
  - `POSTGRES_DB=localai`
  - `POSTGRES_PASSWORD=${var.localai_postgres_password}`
  - `DATABASE_URL=postgresql://localai:${pwd}@localai-postgres:5432/localai?sslmode=disable`
- **PVC `localai-postgres-data`**: Longhorn RWO, `${var.localai_postgres_storage_size}` (default `20Gi`), depends on `helm_release.longhorn`
- **Deployment `localai-postgres`**: 1 replica, `Recreate` strategy, `env_from` the secret, mounts PVC at `/var/lib/postgresql` with `sub_path = "pgdata"`, `pg_isready -U localai` liveness/readiness, resources 256Mi–1Gi mem / 50m–500m CPU
- **Service `localai-postgres`**: ClusterIP, port 5432
- **Pattern reference:** mirrors `kubernetes_deployment.poker_postgres` in `terraform/poker.tf`

### NATS (`terraform/localai-nats.tf`)

- **Image:** `nats:2-alpine`
- **Args:** `["--js", "-m", "8222", "--store_dir", "/data/jetstream"]`
- **PVC `localai-nats-data`**: Longhorn RWO, `${var.localai_nats_storage_size}` (default `5Gi`)
- **Deployment `localai-nats`**: 1 replica, mounts PVC at `/data`, TCP probe on 4222 (liveness + readiness)
- **Service `localai-nats`**: ClusterIP, ports `4222` (client) + `8222` (monitoring, optional but useful for debugging)

### Frontend (`terraform/localai.tf` — modify `kubernetes_deployment.localai`)

- **Image:** `localai/localai:${var.localai_image_version}-aio-cpu` (switching from `gpu-nvidia-cuda-13`)
- **Remove env:** `LOCALAI_P2P`, `LOCALAI_P2P_TOKEN`
- **Add env:**
  - `LOCALAI_DISTRIBUTED=true`
  - `LOCALAI_NATS_URL=nats://localai-nats.localai.svc:4222`
  - `LOCALAI_REGISTRATION_TOKEN` ← `kubernetes_secret.localai_registration` key `token`
  - `LOCALAI_AGENT_POOL_EMBEDDING_MODEL=${var.localai_agent_pool_embedding_model}` (default `granite-embedding-107m-multilingual`)
  - `LOCALAI_AGENT_POOL_VECTOR_ENGINE=postgres`
  - `LOCALAI_AGENT_POOL_DATABASE_URL` ← postgres secret `DATABASE_URL`
  - `LOCALAI_AUTH=true`
  - `LOCALAI_AUTH_DATABASE_URL` ← postgres secret `DATABASE_URL` (same DSN)
  - `GODEBUG=netdns=go` (per compose: forces pure-Go DNS resolver; avoids systemd-resolved 127.0.0.53 unreachable from container)
  - `MODELS_PATH=/models`
- **Volumes:** keep all five NFS PVC mounts + read-only `ollama-blobs` + `comfyui-models`
- **`depends_on`:** add `kubernetes_deployment.localai_postgres`, `kubernetes_deployment.localai_nats`, `kubernetes_secret.localai_postgres`
- **Probes:** unchanged (`/readyz` on 8080)
- **Resources / nodeSelector:** unchanged

### Worker DaemonSet (`terraform/localai.tf` — modify `kubernetes_daemonset.localai_worker` for_each)

- **Image:** `localai/localai:${var.localai_image_version}-gpu-nvidia-cuda-13`
- **Args:** `["worker"]` (drop positional `p2p-llama-cpp-rpc`)
- **Downward API env:**
  - `NODE_IP` ← `status.hostIP`
  - `NODE_NAME` ← `spec.nodeName`
- **Worker env:**
  - `LOCALAI_REGISTER_TO=http://localai.localai.svc:8080`
  - `LOCALAI_REGISTRATION_TOKEN` ← registration secret
  - `LOCALAI_NATS_URL=nats://localai-nats.localai.svc:4222`
  - `LOCALAI_SERVE_ADDR=0.0.0.0:50051`
  - `LOCALAI_ADVERTISE_ADDR=$(NODE_IP):50051`
  - `LOCALAI_ADVERTISE_HTTP_ADDR=$(NODE_IP):50050`
  - `LOCALAI_NODE_NAME=$(NODE_NAME)-${each.key}gpu`
  - `LOCALAI_HEARTBEAT_INTERVAL=10s`
  - `HEALTHCHECK_ENDPOINT=http://localhost:50050/readyz` (overrides image-baked HEALTHCHECK which assumes 8080)
  - `GODEBUG=netdns=go`
  - `MODELS_PATH=/models`
- **Container ports:** add `containerPort 50050 hostPort 50050` (HTTP file transfer) and `containerPort 50051 hostPort 50051` (gRPC backend)
- **Readiness probe:** `httpGet /readyz` on port 50050
- **NodeSelector:** unchanged (`gpu-count-exact-${each.key}=true` + optional `gpu-vram-${N}gb=true`)
- **Resources:** unchanged including `nvidia.com/gpu = each.key`
- **Volumes:** keep NFS mounts for `/models`, `/backends`, `/configuration`, `/ollama-blobs`, `/comfyui-models`

### Agent worker (`terraform/localai.tf` — new `kubernetes_deployment.localai_agent_worker`)

- **Image:** `localai/localai:${var.localai_image_version}-aio-cpu`
- **Args:** `["agent-worker"]` (skip the compose's `apt-get install docker.io` entrypoint — see "Skip docker socket" decision above)
- **Env:**
  - `LOCALAI_NATS_URL=nats://localai-nats.localai.svc:4222`
  - `LOCALAI_REGISTER_TO=http://localai.localai.svc:8080`
  - `LOCALAI_REGISTRATION_TOKEN` ← registration secret
  - `LOCALAI_NODE_NAME=agent-worker`
  - `GODEBUG=netdns=go`
- **Replicas:** 1
- **No volumes, no probes** (NATS-only — no HTTP server to probe; compose explicitly disables healthcheck)
- **Resources:** 256Mi / 100m request, 1Gi / 500m limit
- **No nodeSelector** — lands anywhere

### Service (`terraform/localai.tf` — keep `kubernetes_service.localai`)

Unchanged. Still ClusterIP port 80 → 8080, selector `app=localai`. Traefik IngressRoute (`terraform/ingress.tf`) continues to route `localai.ktsu.dev` → this service.

## Variables

In `terraform/localai.tf`:

| Variable | Action | Default | Sensitive |
|---|---|---|---|
| `localai_image_tag` | **remove** | — | — |
| `localai_image_version` | **add** | `"v4.2.1"` | no |
| `localai_p2p_token` | **rename → `localai_registration_token`** | (required) | yes |
| `localai_postgres_password` | **add** | (required) | yes |
| `localai_postgres_storage_size` | **add** | `"20Gi"` | no |
| `localai_nats_storage_size` | **add** | `"5Gi"` | no |
| `localai_agent_pool_embedding_model` | **add** | `"granite-embedding-107m-multilingual"` | no |

Existing variables (`localai_enabled`, `localai_memory_*`, `localai_cpu_*`, `localai_gpu_enabled`, `localai_gpu_min_vram_gb`) unchanged.

`terraform.tfvars.example` gains the two new sensitive entries. `make generate-secrets` should emit a `localai_postgres_password = "<random hex>"` line.

## Secret rename

The current `kubernetes_secret.localai_p2p` becomes `kubernetes_secret.localai_registration`. Use a `moved` block to preserve state:

```hcl
moved {
  from = kubernetes_secret.localai_p2p
  to   = kubernetes_secret.localai_registration
}
```

The Kubernetes object name itself also changes (`localai-p2p` → `localai-registration`), which is a destroy/create at K8s level. This is harmless: terraform creates the new secret before updating the deployments that reference it; the value (the registration token string) is identical; old pods are being replaced anyway as part of the same plan.

## File structure

```
terraform/
├── localai.tf              namespace, registration secret, NFS PV+PVCs (×5),
│                           frontend Deployment, worker DaemonSet (per-tier for_each),
│                           agent-worker Deployment, Service, output
├── localai-postgres.tf     postgres secret, PVC, Deployment, Service
└── localai-nats.tf         NATS PVC, Deployment, Service
```

One-concern-per-file (per `CLAUDE.md`). Postgres and NATS are LocalAI-internal infrastructure but get their own files to keep `localai.tf` reviewable (~250 lines per file rather than ~900).

## Makefile changes

The current `plan-localai` / `apply-localai` targets are missing `kubernetes_daemonset.localai_worker` (which is why we had to call `terraform apply -target=kubernetes_daemonset.localai_worker` manually during the prior debug). Fix that omission and add the new resources:

```makefile
plan-localai:
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

Mirror in `apply-localai`.

## Apply order

Terraform handles ordering via `depends_on` graph:

1. Namespace, secrets (registration + postgres)
2. Postgres PVC → Deployment → Service
3. NATS PVC → Deployment → Service
4. Frontend Deployment update (depends on postgres + NATS Deployments)
5. Worker DaemonSet update (per-tier `for_each`)
6. Agent-worker Deployment (new)
7. Old `localai-p2p` Kubernetes secret destroyed

Postgres takes a few seconds to initialize on first run; the frontend's `LOCALAI_AUTH=true` creates auth tables and `LOCALAI_AGENT_POOL_*` creates the vector tables on first connection.

## Rollback

`git revert` the terraform commit + `terraform apply` reverts everything except postgres data. The five NFS PVs use `persistent_volume_reclaim_policy = "Retain"` so model files persist regardless. Postgres data on Longhorn would be lost on rollback, but it's all derived state (node registry, auth — recreated automatically on next boot). Rollback isn't expected to be needed since the change adds new infra rather than mutating existing model storage.

## Out of scope

- HA postgres (single replica only; sufficient for homelab)
- NATS clustering (single node; JetStream cluster requires 3+ nodes)
- Multiple frontend replicas with shared state (single replica; can scale later when `LOCALAI_DISTRIBUTED=true` is operational)
- Docker-socket-based MCP stdio servers in the agent worker (HTTP/SSE MCPs only)
- Migrating older `localai-data` PVC contents (skill configs etc. on NFS preserved; auth data resets to postgres)
- Image tag auto-bumps via Keel (left as a future task; the rationale for pinning is explicit)
