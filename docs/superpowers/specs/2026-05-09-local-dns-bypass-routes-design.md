# Local DNS Bypass Routes — Design

**Date:** 2026-05-09
**Status:** Approved

## Goal

For every externally-available service that today has an Azure DNS A record under `ktsu.dev`, expose a parallel `<svc>.local.ktsu.dev` hostname that:

- Resolves (via Azure public DNS) to Traefik's LAN VIP `192.168.0.238`.
- Has **no middleware** — bypasses OAuth, CrowdSec, rate-limit, basic-auth.
- Serves a Let's Encrypt certificate for `local.ktsu.dev` + `*.local.ktsu.dev`, issued via the existing Azure DNS-01 challenge.

Public hostnames and their middleware stacks are unchanged. Local hostnames are a parallel path, not a replacement.

## Decisions

| Question | Decision | Reason |
|---|---|---|
| DNS source | Azure public DNS (same zone as existing records) | Simplicity; works from any device without a local resolver. LAN IP visibility in public DNS is accepted. |
| Hostname pattern | `<svc>.local.ktsu.dev` | Lets a single wildcard `*.local.ktsu.dev` cert cover everything; same Azure DNS-01 challenge as today. |
| Scope | All services with public DNS records under `ktsu.dev` | Consistent rule; avoids a per-service exception list. |
| Middleware on local routes | None | Bypassing OAuth is the point; CrowdSec on LAN risks banning local IPs and adds little value on private networks. |

## Architecture

### New file: `terraform/ingress-local.tf`

A single `kubernetes_manifest.ingressroute_local` resource driven by `for_each` over a `local.local_routes` map. Each map entry describes one local hostname with:

- `host_prefix` — the leftmost label (e.g. `grafana`)
- `service_name` — backing Kubernetes Service name (or `api@internal` for Traefik dashboard)
- `service_namespace` — optional, omitted for Traefik internal services
- `service_port` — optional, defaults to `80`
- `service_kind` — optional, defaults to `Service`; set to `TraefikService` for `api@internal`

The map is built by merging:

- A base entry for `traefik` (host_prefix `traefik`, kind `TraefikService`, name `api@internal`)
- A base entry for `longhorn`
- Per-feature blocks gated on the same `var.*_enabled` flags used in `dns.tf` (`monitoring_enabled`, `kubernetes_dashboard_enabled`, `devtron_enabled`, `baget_enabled`, `n8n_enabled`, the *arr stack, AI/ML stack, `homepage_enabled`, `claudecluster_enabled`, `poker_enabled`)
- A `for` expansion of `local.cams_web_toys_subdomains` (each toy becomes its own local route)

The generated IngressRoute has:

- Name `local-<key>`, namespace `traefik`
- Single route matching `Host(`${host_prefix}.local.${var.traefik_domain}`)` with **no `middlewares`** field
- `tls.domains = [{ main = "local.${var.traefik_domain}", sans = ["*.local.${var.traefik_domain}"] }]`
- `depends_on = [helm_release.traefik]`

Traefik dedupes identical `tls.domains` requests across IngressRoutes, so all local routes share one certificate.

### Modified file: `terraform/dns.tf`

- New variable `traefik_local_ip` (default `"192.168.0.238"`, matching the hard-coded `loadBalancerIP` in `traefik.tf`).
- New `azurerm_dns_a_record.local_services` resource with `for_each` over the existing `local.dns_records` map. Names use the form `<value>.local` (e.g. `grafana.local`); records contain `[var.traefik_local_ip]`. Same `ttl` and `tags` as the public records.
- Static-site DNS handling is unchanged.
- The `dns_info` output gains a `local_records` map mirroring the existing `records` map for visibility.

### Unchanged: `terraform/traefik.tf`

No edits required. The existing `letsencrypt` cert resolver, Azure DNS credentials, and websecure entrypoint already provide everything needed. The new IngressRoutes' `tls.domains` field is what triggers the second certificate request.

## Excluded

- **Static sites** — they use custom apex domains tracked in separate Azure zones (`var.static_sites`), so the `<svc>.local.ktsu.dev` pattern does not apply.
- Anything not currently producing an entry in `local.dns_records`.

## Accepted trade-offs

- LAN IP `192.168.0.238` is publicly resolvable in DNS. Public clients querying `*.local.ktsu.dev` get an unroutable RFC1918 address — no security exposure beyond topology disclosure.
- No rate-limiting or CrowdSec on local routes; acceptable on LAN.
- Hairpin routing for public hostnames is unchanged — local hostnames provide an explicit on-LAN path that bypasses the router NAT loopback.
- The Traefik LoadBalancer IP appears as a literal in two places (`traefik.tf` `loadBalancerIP` and the new `traefik_local_ip` default). Promoting it to a shared variable is out of scope for this change.

## Validation

After apply:

- `nslookup grafana.local.ktsu.dev` returns `192.168.0.238` from any LAN client.
- `curl -v https://grafana.local.ktsu.dev/` from LAN reaches Grafana directly without OAuth redirect, with a valid Let's Encrypt cert chain whose SAN includes `*.local.ktsu.dev`.
- Public hostnames (`grafana.ktsu.dev`) still resolve to `var.external_ip` and still enforce their existing middleware.
