# Static Sites Webserver Design

## Overview

Add a lightweight nginx-based static site server to the homelab cluster. Supports multiple sites on different primary domains, with git-based content delivery and automatic updates.

## Architecture

A single nginx Deployment in a `static-sites` namespace serves all configured sites via virtual hosts. Content is cloned from git repos and kept up-to-date by a sidecar.

### Components

- **Init containers** (one per site): Clone each git repo into a shared `emptyDir` volume at `/sites/<domain>/`
- **Sidecar container**: Alpine/git image running a loop that `git pull`s each repo on a configurable interval (default 60s)
- **Nginx container**: Serves all sites using dynamically generated vhost config, routing by domain to `/sites/<domain>/`
- **ConfigMap**: Contains the nginx vhost configuration (generated from the sites list) and the git-pull script

### Configuration

Sites defined as a Terraform variable:

```hcl
static_sites = [
  { domain = "example.com",      repo_url = "https://github.com/user/site1.git", branch = "main" },
  { domain = "another-site.org", repo_url = "https://github.com/user/site2.git", branch = "main" },
]
```

### Networking & Routing

- ClusterIP Service for the nginx Deployment
- One IngressRoute per site with `Host()` matching on each domain
- TLS via Traefik ACME with Azure DNS challenge (individual certs per domain)

### DNS

For each site domain:
- Create an Azure DNS zone
- Create an A record (`@`) pointing to `external_ip`
- Output nameservers for registrar configuration

### Git Auth

Optional `static_sites_git_credentials` variable for private repos. Public repos need no auth.

## File Changes

- **`static-sites.tf`** (new) — namespace, configmap, deployment, service, variables, outputs
- **`ingress.tf`** — add IngressRoute per site via `for_each`
- **`dns.tf`** — add DNS zones + A records per site via `for_each`
- **`Makefile`** — add plan/apply/debug/status targets for static-sites
- **`terraform.tfvars.example`** — document new variables
- **`CLAUDE.md`** — add static-sites.tf to file organization

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `static_sites` | `[]` | List of `{domain, repo_url, branch}` objects |
| `static_sites_git_poll_interval` | `"60"` | Seconds between git pulls |
| `static_sites_nginx_image` | `"nginx:alpine"` | Nginx container image |
| `static_sites_resources` | sensible defaults | CPU/memory requests and limits |
| `static_sites_git_credentials` | `""` | Optional git credentials for private repos |
