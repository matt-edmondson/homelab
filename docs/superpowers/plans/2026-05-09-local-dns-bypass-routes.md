# Local DNS Bypass Routes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `<svc>.local.ktsu.dev` hostnames for every public service so they're reachable from the LAN at Traefik's VIP `192.168.0.238` with no middleware (OAuth/CrowdSec bypassed).

**Architecture:** One new file `terraform/ingress-local.tf` with a `local.local_routes` map and a single `kubernetes_manifest.ingressroute_local` resource using `for_each`. `dns.tf` gains a parallel `azurerm_dns_a_record.local_services` for_each pointing to the LAN VIP. `traefik.tf` is unchanged — the new IngressRoutes' `tls.domains` triggers Let's Encrypt to issue a `local.ktsu.dev` + `*.local.ktsu.dev` cert via the existing Azure DNS-01 challenge.

**Tech Stack:** Terraform (~> 1.0), `hashicorp/kubernetes` ~> 2.38, `hashicorp/azurerm` ~> 4.0, Traefik 34.5.0 with Let's Encrypt + Azure DNS challenge.

**Conventions:**
- All `make` and `terraform` commands run from the `terraform/` directory.
- Commit messages use lower-case conventional prefixes (`feat`, `chore`, etc.). NO `Co-Authored-By` lines (per project memory).
- `*.tfvars` is gitignored — this plan never edits tfvars.

---

## Spec reference

`docs/superpowers/specs/2026-05-09-local-dns-bypass-routes-design.md` (commit `bdb7cb1`).

---

### Task 1: Add `traefik_local_ip` variable to `dns.tf`

**Files:**
- Modify: `terraform/dns.tf` (add a new variable block alongside `external_ip`)

- [ ] **Step 1: Add the variable**

In `terraform/dns.tf`, immediately after the `external_ip` variable block (currently around lines 13–17), insert:

```hcl
variable "traefik_local_ip" {
  description = "LAN IP of the Traefik LoadBalancer service, used as the A-record target for *.local.ktsu.dev hostnames. Must match the loadBalancerIP set in traefik.tf."
  type        = string
  default     = "192.168.0.238"
}
```

The default matches `loadBalancerIP = "192.168.0.238"` in `terraform/traefik.tf:178`.

- [ ] **Step 2: Validate the configuration parses**

Run from `terraform/`:
```bash
cd terraform
terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add dns.tf
git commit -m "feat(dns): add traefik_local_ip variable for local.* bypass routes"
```

---

### Task 2: Add `azurerm_dns_a_record.local_services` to `dns.tf`

**Files:**
- Modify: `terraform/dns.tf` (add a new resource block after `azurerm_dns_a_record.services`, currently around lines 94–104)

- [ ] **Step 1: Add the resource**

In `terraform/dns.tf`, immediately after the `azurerm_dns_a_record.services` resource (the one with `for_each = local.dns_records`), insert:

```hcl
# Local-only A records: <svc>.local.ktsu.dev -> Traefik LAN VIP.
# Iterates the same dns_records map as the public records, so every public
# service automatically gets a parallel local hostname. Bypass IngressRoutes
# (no OAuth/CrowdSec middleware) live in ingress-local.tf.
resource "azurerm_dns_a_record" "local_services" {
  for_each = local.dns_records

  name                = "${each.value}.local"
  zone_name           = data.azurerm_dns_zone.main.name
  resource_group_name = var.azure_dns_resource_group
  ttl                 = var.dns_ttl
  records             = [var.traefik_local_ip]

  tags = var.common_labels
}
```

- [ ] **Step 2: Extend the `dns_info` output**

In `terraform/dns.tf`, locate the `output "dns_info"` block (currently around lines 132–149). Inside the `value = { ... }` map, add a `local_records` field next to `records`:

```hcl
    local_records = { for k, v in azurerm_dns_a_record.local_services : k => "${v.name}.${data.azurerm_dns_zone.main.name}" }
```

Place it on the line immediately after the existing `records = ...` line.

- [ ] **Step 3: Validate**

```bash
cd terraform
terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Plan and review the diff**

```bash
cd terraform
make plan-azure-dns 2>&1 | tee /tmp/local-dns-plan.txt
```
Expected: Plan adds N new `azurerm_dns_a_record.local_services["<key>"]` resources, where N equals the current count of `azurerm_dns_a_record.services`. No resources should be destroyed or modified. `external_ip` records are untouched.

Sanity-check by counting:
```bash
grep -c 'will be created' /tmp/local-dns-plan.txt
grep 'azurerm_dns_a_record\.local_services' /tmp/local-dns-plan.txt | wc -l
```
Both numbers should match the expected count of local records (one per enabled service).

- [ ] **Step 5: Commit**

```bash
git add dns.tf
git commit -m "feat(dns): add local.* A records pointing to Traefik LAN VIP"
```

---

### Task 3: Create `ingress-local.tf` with the `local_routes` map

**Files:**
- Create: `terraform/ingress-local.tf`

- [ ] **Step 1: Create the file with the locals block and IngressRoute resource**

Create `terraform/ingress-local.tf` with the following content (verbatim — every map entry mirrors the gating in `dns.tf`):

```hcl
# =============================================================================
# Traefik Local-Only Bypass IngressRoutes
# =============================================================================
# For every public service that gets an Azure DNS A record under ktsu.dev,
# this file creates a parallel <svc>.local.ktsu.dev IngressRoute that:
#   - Points to the same backend Service
#   - Has NO middleware (no OAuth, no CrowdSec, no rate-limit) — full bypass
#   - Serves a Let's Encrypt cert for local.ktsu.dev + *.local.ktsu.dev,
#     issued via the same Azure DNS-01 challenge configured in traefik.tf
#
# DNS A records for these hostnames live in dns.tf
# (azurerm_dns_a_record.local_services, target var.traefik_local_ip).
#
# IMPORTANT: This file uses Traefik CRDs installed by the Traefik Helm chart
# (traefik.tf). Apply order is unchanged: traefik first, then ingress.
# =============================================================================

locals {
  # One entry per <svc>.local.ktsu.dev hostname. Schema:
  #   host_prefix        - leftmost label (e.g. "grafana")
  #   service_name       - backend Service name (or "api@internal" for Traefik)
  #   service_namespace  - optional; omitted for api@internal
  #   service_port       - optional; defaults to 80
  #   service_kind       - optional; defaults to "Service"; use "TraefikService"
  #                        for api@internal
  local_routes = merge(
    {
      traefik = {
        host_prefix  = "traefik"
        service_name = "api@internal"
        service_kind = "TraefikService"
      }
      longhorn = {
        host_prefix       = "longhorn"
        service_name      = kubernetes_service.longhorn_frontend_lb.metadata[0].name
        service_namespace = kubernetes_namespace.longhorn_system.metadata[0].name
        service_port      = 80
      }
    },
    var.monitoring_enabled ? {
      grafana = {
        host_prefix       = "grafana"
        service_name      = "prometheus-stack-grafana"
        service_namespace = kubernetes_namespace.monitoring[0].metadata[0].name
        service_port      = 80
      }
      prometheus = {
        host_prefix       = "prometheus"
        service_name      = "prometheus-stack-kube-prom-prometheus"
        service_namespace = kubernetes_namespace.monitoring[0].metadata[0].name
        service_port      = 9090
      }
      alertmanager = {
        host_prefix       = "alertmanager"
        service_name      = "prometheus-stack-kube-prom-alertmanager"
        service_namespace = kubernetes_namespace.monitoring[0].metadata[0].name
        service_port      = 9093
      }
    } : {},
    var.kubernetes_dashboard_enabled ? {
      dashboard = {
        host_prefix       = "dashboard"
        service_name      = "headlamp"
        service_namespace = kubernetes_namespace.headlamp[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.devtron_enabled ? {
      devtron = {
        host_prefix       = "devtron"
        service_name      = "devtron-service"
        service_namespace = kubernetes_namespace.devtron[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.baget_enabled ? {
      packages = {
        host_prefix       = "packages"
        service_name      = kubernetes_service.baget[0].metadata[0].name
        service_namespace = kubernetes_namespace.baget[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.n8n_enabled ? {
      n8n = {
        host_prefix       = "n8n"
        service_name      = kubernetes_service.n8n[0].metadata[0].name
        service_namespace = kubernetes_namespace.n8n[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.prowlarr_enabled ? {
      prowlarr = {
        host_prefix       = "prowlarr"
        service_name      = kubernetes_service.prowlarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.prowlarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.sonarr_enabled ? {
      sonarr = {
        host_prefix       = "sonarr"
        service_name      = kubernetes_service.sonarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.sonarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.radarr_enabled ? {
      radarr = {
        host_prefix       = "radarr"
        service_name      = kubernetes_service.radarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.radarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.qbittorrent_enabled ? {
      qbit = {
        host_prefix       = "qbit"
        service_name      = kubernetes_service.qbittorrent[0].metadata[0].name
        service_namespace = kubernetes_namespace.qbittorrent[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.emby_enabled ? {
      emby = {
        host_prefix       = "emby"
        service_name      = kubernetes_service.emby[0].metadata[0].name
        service_namespace = kubernetes_namespace.emby[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.bazarr_enabled ? {
      bazarr = {
        host_prefix       = "bazarr"
        service_name      = kubernetes_service.bazarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.bazarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.jackett_enabled ? {
      jackett = {
        host_prefix       = "jackett"
        service_name      = kubernetes_service.jackett[0].metadata[0].name
        service_namespace = kubernetes_namespace.jackett[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.cleanuparr_enabled ? {
      cleanuparr = {
        host_prefix       = "cleanuparr"
        service_name      = kubernetes_service.cleanuparr[0].metadata[0].name
        service_namespace = kubernetes_namespace.cleanuparr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.sabnzbd_enabled ? {
      sabnzbd = {
        host_prefix       = "sabnzbd"
        service_name      = kubernetes_service.sabnzbd[0].metadata[0].name
        service_namespace = kubernetes_namespace.sabnzbd[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.notifiarr_enabled ? {
      notifiarr = {
        host_prefix       = "notifiarr"
        service_name      = kubernetes_service.notifiarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.notifiarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.ollama_enabled ? {
      ollama = {
        host_prefix       = "ollama"
        service_name      = kubernetes_service.ollama[0].metadata[0].name
        service_namespace = kubernetes_namespace.ollama[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.qdrant_enabled ? {
      qdrant = {
        host_prefix       = "qdrant"
        service_name      = kubernetes_service.qdrant[0].metadata[0].name
        service_namespace = kubernetes_namespace.qdrant[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.chromadb_enabled ? {
      chromadb = {
        host_prefix       = "chromadb"
        service_name      = kubernetes_service.chromadb[0].metadata[0].name
        service_namespace = kubernetes_namespace.chromadb[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.comfyui_enabled ? {
      comfyui = {
        host_prefix       = "comfyui"
        service_name      = kubernetes_service.comfyui[0].metadata[0].name
        service_namespace = kubernetes_namespace.comfyui[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.homepage_enabled ? {
      homepage = {
        host_prefix       = "homepage"
        service_name      = kubernetes_service.homepage[0].metadata[0].name
        service_namespace = kubernetes_namespace.homepage[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.claudecluster_enabled ? {
      claude = {
        host_prefix       = "claude"
        service_name      = kubernetes_service.claudecluster_backend[0].metadata[0].name
        service_namespace = kubernetes_namespace.claude_sandbox[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.poker_enabled ? {
      poker = {
        host_prefix       = "poker"
        service_name      = kubernetes_service.poker[0].metadata[0].name
        service_namespace = kubernetes_namespace.poker[0].metadata[0].name
        service_port      = 3000
      }
    } : {},
    {
      for k, sub in local.cams_web_toys_subdomains :
      "cwt_${k}" => {
        host_prefix       = sub
        service_name      = kubernetes_service.cams_web_toys[0].metadata[0].name
        service_namespace = kubernetes_namespace.cams_web_toys[0].metadata[0].name
        service_port      = 3000
      }
    },
  )
}

resource "kubernetes_manifest" "ingressroute_local" {
  for_each = local.local_routes

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "local-${each.key}"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`${each.value.host_prefix}.local.${var.traefik_domain}`)"
        kind  = "Rule"
        # NOTE: deliberately no `middlewares` field — full bypass of OAuth,
        # CrowdSec, rate-limit, and basic-auth. That is the entire point of
        # this file.
        services = [merge(
          {
            name = each.value.service_name
            port = try(each.value.service_port, 80)
          },
          try(each.value.service_kind, null) != null ? { kind = each.value.service_kind } : {},
          try(each.value.service_namespace, null) != null ? { namespace = each.value.service_namespace } : {},
        )]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = "local.${var.traefik_domain}"
          sans = ["*.local.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [helm_release.traefik]
}
```

- [ ] **Step 2: Format**

```bash
cd terraform
terraform fmt ingress-local.tf
```
Expected: silent (no output) or filename echoed once. No formatting errors.

- [ ] **Step 3: Validate**

```bash
cd terraform
terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Plan and inspect**

```bash
cd terraform
make plan-ingress 2>&1 | tee /tmp/local-ingress-plan.txt
```
Expected: Plan adds N new `kubernetes_manifest.ingressroute_local["<key>"]` resources, where N matches the size of `local.local_routes`. No existing IngressRoute is modified or destroyed.

Sanity check the host matchers:
```bash
grep 'Host(`' /tmp/local-ingress-plan.txt | grep '\.local\.' | sort -u
```
Every line should be `Host(\`<svc>.local.ktsu.dev\`)`. There should be no `<svc>.local.local.` (double-`local`) — if you see one, it means a `host_prefix` already contained `local`, which is a bug to fix in the map.

- [ ] **Step 5: Commit**

```bash
git add ingress-local.tf
git commit -m "feat(ingress): add local.* bypass IngressRoutes for all public services"
```

---

### Task 4: Apply DNS records first, then IngressRoutes

**Files:**
- None modified — applies the changes from Tasks 1–3.

DNS goes first so that, by the time Traefik tries to issue the `*.local.ktsu.dev` cert, the zone records are stable. (Strictly, DNS-01 only needs the `_acme-challenge` TXT record which Traefik creates itself, so order is not critical for correctness — but applying DNS first keeps the apply log readable and lets you verify resolution before the cert handshake.)

- [ ] **Step 1: Apply DNS A records**

```bash
cd terraform
make apply-azure-dns
```
Expected: `Apply complete! Resources: N added, 0 changed, 0 destroyed.` where N matches the count from Task 2 step 4.

- [ ] **Step 2: Verify a couple of local records resolve**

From any LAN client (or directly on a control-plane node):
```bash
nslookup grafana.local.ktsu.dev 1.1.1.1
nslookup longhorn.local.ktsu.dev 1.1.1.1
```
Expected: both return `192.168.0.238`.

DNS may take up to `var.dns_ttl` (default 300s) to propagate. If `nslookup` returns NXDOMAIN immediately, retry after 30–60 seconds.

- [ ] **Step 3: Apply IngressRoutes**

```bash
cd terraform
make apply-ingress
```
Expected: `Apply complete! Resources: N added, 0 changed, 0 destroyed.` where N matches the count from Task 3 step 4.

- [ ] **Step 4: Verify the IngressRoutes exist in Kubernetes**

```bash
kubectl get ingressroute -n traefik | grep ^local-
```
Expected: one row per local route, with names `local-traefik`, `local-longhorn`, `local-grafana`, etc.

- [ ] **Step 5: No commit needed**

Apply does not modify tracked files. Move on.

---

### Task 5: Verify cert issuance for `*.local.ktsu.dev`

**Files:**
- None modified — observation only.

Traefik issues the new cert lazily on first request to a `local.*` hostname. Trigger it explicitly so you can confirm the issue path works.

- [ ] **Step 1: Trigger cert issuance**

From a LAN client (any machine that can resolve `*.local.ktsu.dev`):
```bash
curl -v https://grafana.local.ktsu.dev/ 2>&1 | head -40
```
Expected: TLS handshake completes; the server cert chain shows `subject=CN=local.ktsu.dev` (or with `*.local.ktsu.dev` in SAN) and issuer `Let's Encrypt`. Body should be Grafana's HTML, not an OAuth redirect to `auth.ktsu.dev`.

If the first call returns `HTTP/2 404` or a self-signed default cert: Traefik is still completing the ACME challenge. Tail the logs:
```bash
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=100 | grep -iE 'acme|local\.ktsu\.dev'
```
Wait for a `Certificate obtained for domains=local.ktsu.dev,*.local.ktsu.dev` line, then retry the curl.

- [ ] **Step 2: Confirm the cert SAN list**

```bash
echo | openssl s_client -connect grafana.local.ktsu.dev:443 -servername grafana.local.ktsu.dev 2>/dev/null \
  | openssl x509 -noout -text | grep -A2 'Subject Alternative Name'
```
Expected: SAN contains both `DNS:local.ktsu.dev` and `DNS:*.local.ktsu.dev`.

- [ ] **Step 3: Confirm OAuth bypass on a previously OAuth-protected service**

```bash
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://prometheus.local.ktsu.dev/
```
Expected: `200` (or whatever Prometheus' root returns), and an empty `redirect_url`. The public hostname should still redirect — verify:
```bash
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://prometheus.ktsu.dev/
```
Expected: `302` with a `redirect_url` containing `auth.ktsu.dev`.

- [ ] **Step 4: Confirm public DNS for the same service is unchanged**

```bash
nslookup prometheus.ktsu.dev 1.1.1.1
```
Expected: returns `var.external_ip` (the public/router IP), NOT `192.168.0.238`. If this is wrong, something in `dns.tf` was edited beyond the new resource — review the diff.

---

## Self-review checklist

- [x] **Spec coverage:** Goal, hostname pattern, scope, middleware bypass, TLS via existing resolver, excluded static sites, `traefik_local_ip` variable — all covered by Tasks 1–4. Validation in Task 5 maps to the spec's "Validation" section.
- [x] **Placeholders:** None. Every code block is complete and ready to paste.
- [x] **Type/name consistency:** `local.local_routes` field names (`host_prefix`, `service_name`, `service_namespace`, `service_port`, `service_kind`) match between locals definition and IngressRoute resource. `var.traefik_local_ip` defined in Task 1, used in Task 2. The `make plan-azure-dns` / `make apply-azure-dns` / `make plan-ingress` / `make apply-ingress` targets all exist in `terraform/Makefile`.
- [x] **Gates aligned with `dns.tf`:** Every conditional in `local.local_routes` mirrors the corresponding conditional in `local.dns_records`. `auth = "auth"` from `dns.tf` is intentionally excluded (bypassing OAuth on the OAuth service is meaningless).
