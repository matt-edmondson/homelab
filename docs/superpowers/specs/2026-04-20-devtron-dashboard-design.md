# Devtron Dashboard — Design

**Date:** 2026-04-20
**Status:** Approved (pending user review of this spec)

## Goal

Add Devtron (dashboard-only, no CI/CD) to the homelab cluster as a visibility-focused Kubernetes UI. Reachable at `https://devtron.${traefik_domain}` behind the existing oauth2-proxy + CrowdSec ingress stack. Users still log into Devtron's built-in admin after passing the OAuth gate — Devtron does not support disabling its own auth.

## Scope

**In scope**
- Deploying Devtron dashboard-only (installer.modules = [])
- Bundled Postgres on Longhorn PVC (chart default)
- Traefik IngressRoute with the project's standard middleware chain (crowdsec-bouncer + oauth-forward-auth)
- Azure DNS A record for the `devtron` subdomain
- Makefile targets for plan/apply/debug
- Dual auth (OAuth at ingress, Devtron admin login inside)

**Out of scope**
- CI/CD module (`installer.modules=[cicd]`) — pipelines, GitOps, image scanning, Argo CD/Workflows
- Helm app management workflows (user chose "pure visibility" use case)
- Multi-cluster registration (only this cluster)
- OIDC SSO integration between oauth2-proxy and Devtron's embedded Dex — future work if dual login becomes annoying
- External Postgres (bundled Postgres matches every other stateful service in this cluster)
- Tuning resource requests/limits (accept chart defaults; revisit only if pods get OOMKilled)

## Architecture

### File layout

One new Terraform file, three edits to existing files:

| File | Change |
|------|--------|
| `terraform/devtron.tf` | **New.** Variables, namespace, Helm release, output. |
| `terraform/ingress.tf` | **Edit.** Add IngressRoute for `devtron.${traefik_domain}`. |
| `terraform/dns.tf` | **Edit.** Add Azure A record for the `devtron` subdomain. |
| `terraform/Makefile` | **Edit.** Add `plan-devtron`, `apply-devtron`, `debug-devtron` targets. |
| `terraform/terraform.tfvars.example` | **Edit.** Document the three new variables. |

### Chart

- **Repository:** `https://helm.devtron.ai`
- **Chart name:** `devtron-operator`
- **Chart version:** `0.23.2` (pinned via `var.devtron_chart_version`; appVersion 2.1.1 at time of writing)
- **Release name:** `devtron`
- **Namespace:** `devtroncd` (hardcoded convention — Devtron components reference this namespace internally)

### Variables

All declared inside `devtron.tf`, following the project pattern of co-locating variables with the resources they govern.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `devtron_enabled` | `bool` | `false` | Opt-in toggle. User flips to `true` in `terraform.tfvars`. |
| `devtron_chart_version` | `string` | `"0.23.2"` | Exact Helm chart version. Bumped by editing `terraform.tfvars`. |
| `devtron_postgres_storage_size` | `string` | `"20Gi"` | Longhorn PVC size for the bundled Postgres StatefulSet. |

### Helm values (overrides only)

The Helm release sets only the values that differ from chart defaults:

```yaml
installer:
  modules: []                      # dashboard-only (no CI/CD)

global:
  storageClass: "longhorn"         # all PVCs on Longhorn

postgres:
  persistence:
    volumeSize: "20Gi"             # from var.devtron_postgres_storage_size

devtron:
  service:
    type: ClusterIP                # override chart default (LoadBalancer)
    port: 80
  ingress:
    enabled: false                 # Traefik IngressRoute CRD handles ingress
```

### Resources created

All resources are conditional on `var.devtron_enabled` via `count`.

**In `devtron.tf`:**
- `kubernetes_namespace.devtron` — namespace `devtroncd` with `var.common_labels`
- `helm_release.devtron` — `devtron-operator` chart
  - `depends_on`: `data.kubernetes_storage_class.longhorn` (ensure Longhorn StorageClass exists before Postgres PVC provisions)
- `output "devtron_info"` — sensitive, contains namespace, chart version, access URL, and helper commands (admin password retrieval, pod status, log tail)

**In `ingress.tf`:**
- `kubernetes_manifest.ingressroute_devtron` — IngressRoute resource
  - Host: `devtron.${var.traefik_domain}`
  - Middlewares: `crowdsec-bouncer`, `oauth-forward-auth` (exact same pattern as Longhorn/Headlamp/Traefik-dashboard)
  - Backend service: `devtron-service` on port 80 in namespace `devtroncd`
  - TLS: `letsencrypt` resolver with wildcard SAN
  - `depends_on`: `helm_release.traefik`, `helm_release.devtron`, `kubernetes_manifest.middleware_crowdsec_bouncer`, `kubernetes_manifest.middleware_oauth_forward_auth`

**In `dns.tf`:**
- `azurerm_dns_a_record.devtron` — `devtron` A record pointing at the Traefik LoadBalancer IP, conditional on `var.devtron_enabled`

### Auth flow

1. User visits `https://devtron.${traefik_domain}`
2. Traefik `crowdsec-bouncer` middleware checks for banned IPs
3. Traefik `oauth-forward-auth` middleware checks with oauth2-proxy (`http://oauth2-auth-bridge.oauth2-proxy.svc.cluster.local/verify`)
4. If unauthenticated, user is redirected to `https://auth.${traefik_domain}/oauth2/sign_in` to complete OAuth flow
5. Request reaches Devtron dashboard service, which presents Devtron's own admin login
6. User enters `admin` + the auto-generated password from `devtron-secret.ACD_PASSWORD`
7. User is now logged into Devtron

The two auth layers are independent; bypassing one does not bypass the other. This matches the pattern used for Longhorn and the Traefik dashboard — services whose internal auth can't be delegated.

### Makefile targets

Following the existing per-component pattern:

```makefile
plan-devtron:
	terraform plan -target=kubernetes_namespace.devtron -target=helm_release.devtron

apply-devtron:
	terraform apply -target=kubernetes_namespace.devtron -target=helm_release.devtron

debug-devtron:
	@echo "Devtron Pods:"
	kubectl get pods -n devtroncd
	@echo "\nDevtron PVCs:"
	kubectl get pvc -n devtroncd
	@echo "\nDevtron Services:"
	kubectl get svc -n devtroncd
	@echo "\nDevtron Admin Password:"
	kubectl -n devtroncd get secret devtron-secret -o jsonpath='{.data.ACD_PASSWORD}' | base64 -d
	@echo ""
```

### `terraform.tfvars.example` additions

Three new lines documenting the variables, following the file's existing comment style.

## Apply order

One-time initial rollout after flipping `devtron_enabled = true` in `terraform.tfvars`:

1. `make apply-devtron` — creates the namespace and Helm release. Postgres PVC provisioning and initial migrations typically take 3–5 minutes. Expect pods to cycle through `Pending → Init → Running`.
2. `make apply-ingress` — creates the IngressRoute once the `devtron-service` ClusterIP exists.
3. `make apply` (or a dns-targeted variant) — creates the Azure DNS A record.

After rollout:
- Retrieve admin password: `kubectl -n devtroncd get secret devtron-secret -o jsonpath='{.data.ACD_PASSWORD}' | base64 -d`
- Visit `https://devtron.${traefik_domain}`
- Complete OAuth at `auth.${traefik_domain}`, then log into Devtron as `admin`

## Testing / verification

After apply:
- `kubectl get pods -n devtroncd` — all pods `Running`, none in `CrashLoopBackOff`
- `kubectl get pvc -n devtroncd` — Postgres PVC `Bound` on Longhorn
- `kubectl get ingressroute -n traefik devtron` — exists, backend resolves
- `dig devtron.${traefik_domain}` — resolves to Traefik LB IP
- `curl -I https://devtron.${traefik_domain}` — returns a redirect to `auth.${traefik_domain}/oauth2/sign_in`
- Browser: complete OAuth, then Devtron admin login works with the password from `devtron-secret`

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Chart installs more than expected (Devtron has many subcomponents) | `installer.modules: []` is explicit; verify via `kubectl get pods -n devtroncd` that no CI/CD-only pods appear (e.g., no `argocd-*`, `argo-workflow-*`, `nats-*`, `minio-*`). |
| Postgres PVC provisioning hangs if Longhorn isn't ready | `depends_on = [data.kubernetes_storage_class.longhorn]` matches existing pattern. If it still hangs, Longhorn itself is broken — unrelated issue. |
| Chart default LoadBalancer service would consume a kube-vip IP | Explicit `devtron.service.type: ClusterIP` override prevents this. |
| Devtron admin password unknown | `devtron_info.commands.admin_password` output documents the `kubectl ... base64 -d` retrieval; `make debug-devtron` also prints it. |
| Double login is annoying | Documented in spec; future work is OIDC SSO (out of scope). |

## Future work (explicitly deferred)

- OIDC SSO between oauth2-proxy's IdP and Devtron's embedded Dex (single login)
- Enabling `installer.modules=[cicd]` if the user decides to move CI off GitHub Actions
- Tuning resource requests/limits based on observed usage
- Adding additional clusters to Devtron if the homelab grows
