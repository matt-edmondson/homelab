# Static Sites Webserver Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a git-powered nginx static site server that hosts multiple sites on different primary domains with auto-updating content.

**Architecture:** Single nginx Deployment with init containers (one per site) that clone git repos, a sidecar that polls for updates, and dynamically generated vhost config. Each site gets its own Azure DNS zone, A record, and Traefik IngressRoute with individual TLS certificates.

**Tech Stack:** Terraform, Kubernetes (Deployment, Service, ConfigMap, Namespace), Nginx, Alpine/Git sidecar, Azure DNS, Traefik IngressRoute CRDs

---

### Task 1: Create static-sites.tf — Variables

**Files:**
- Create: `terraform/static-sites.tf`

**Step 1: Write the variables section**

```hcl
# =============================================================================
# Static Sites - Nginx-based static site hosting with git-based content
# =============================================================================

# Variables
variable "static_sites" {
  description = "List of static sites to host. Each site needs a domain, git repo URL, and branch."
  type = list(object({
    domain   = string
    repo_url = string
    branch   = string
  }))
  default = []
}

variable "static_sites_git_poll_interval" {
  description = "Interval in seconds between git pull operations for content updates"
  type        = string
  default     = "60"
}

variable "static_sites_nginx_image" {
  description = "Nginx container image for serving static sites"
  type        = string
  default     = "nginx:alpine"
}

variable "static_sites_git_image" {
  description = "Git container image for cloning and pulling repos"
  type        = string
  default     = "alpine/git:latest"
}

variable "static_sites_memory_request" {
  description = "Memory request for the nginx container"
  type        = string
  default     = "64Mi"
}

variable "static_sites_memory_limit" {
  description = "Memory limit for the nginx container"
  type        = string
  default     = "128Mi"
}

variable "static_sites_cpu_request" {
  description = "CPU request for the nginx container"
  type        = string
  default     = "50m"
}

variable "static_sites_cpu_limit" {
  description = "CPU limit for the nginx container"
  type        = string
  default     = "200m"
}

variable "static_sites_git_credentials" {
  description = "Optional git credentials URL (e.g. https://user:token@github.com) for private repos"
  type        = string
  sensitive   = true
  default     = ""
}
```

**Step 2: Validate syntax**

Run: `cd terraform && terraform validate`
Expected: Success (no resources yet, just variables)

**Step 3: Commit**

```bash
git add terraform/static-sites.tf
git commit -m "feat: add static-sites variables"
```

---

### Task 2: Create static-sites.tf — Namespace and ConfigMap

**Files:**
- Modify: `terraform/static-sites.tf`

**Step 1: Add the namespace resource** (append after variables)

```hcl
# Namespace
resource "kubernetes_namespace" "static_sites" {
  count = length(var.static_sites) > 0 ? 1 : 0

  metadata {
    name = "static-sites"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "static-sites"
    })
  }
}
```

**Step 2: Add the ConfigMap with nginx config and git-pull script**

The nginx config uses a `server` block per site, routing by `server_name` to the site's directory. The git-pull script loops through all sites and runs `git pull` on each.

```hcl
# Nginx virtual host configuration (generated from static_sites list)
resource "kubernetes_config_map" "static_sites_config" {
  count = length(var.static_sites) > 0 ? 1 : 0

  metadata {
    name      = "static-sites-config"
    namespace = kubernetes_namespace.static_sites[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    "nginx.conf" = templatefile("${path.module}/templates/static-sites-nginx.conf.tpl", {
      sites = var.static_sites
    })

    "git-pull.sh" = templatefile("${path.module}/templates/static-sites-git-pull.sh.tpl", {
      sites    = var.static_sites
      interval = var.static_sites_git_poll_interval
    })
  }
}
```

**Step 3: Create the nginx config template**

Create file: `terraform/templates/static-sites-nginx.conf.tpl`

```nginx
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    # Logging
    access_log /var/log/nginx/access.log;

%{ for site in sites ~}
    server {
        listen 80;
        server_name ${site.domain};
        root /sites/${site.domain};
        index index.html index.htm;

        location / {
            try_files $uri $uri/ =404;
        }
    }

%{ endfor ~}
    # Default server — return 404 for unknown hosts
    server {
        listen 80 default_server;
        server_name _;
        return 404;
    }
}
```

**Step 4: Create the git-pull script template**

Create file: `terraform/templates/static-sites-git-pull.sh.tpl`

```bash
#!/bin/sh
set -e

echo "Starting git pull loop (interval: ${interval}s)"

while true; do
%{ for site in sites ~}
  echo "Pulling ${site.domain} (${site.branch})..."
  cd /sites/${site.domain} && git pull origin ${site.branch} 2>&1 || echo "Failed to pull ${site.domain}"
%{ endfor ~}
  sleep ${interval}
done
```

**Step 5: Validate**

Run: `cd terraform && terraform validate`
Expected: Success

**Step 6: Commit**

```bash
git add terraform/static-sites.tf terraform/templates/
git commit -m "feat: add static-sites namespace, configmap, and templates"
```

---

### Task 3: Create static-sites.tf — Deployment and Service

**Files:**
- Modify: `terraform/static-sites.tf`

**Step 1: Add the Deployment resource**

The deployment has:
- One init container per site that clones the git repo
- One sidecar container that runs the git-pull loop
- One nginx container serving the sites
- A shared `emptyDir` volume at `/sites`

```hcl
# Deployment
resource "kubernetes_deployment" "static_sites" {
  count = length(var.static_sites) > 0 ? 1 : 0

  depends_on = [
    kubernetes_config_map.static_sites_config,
  ]

  metadata {
    name      = "static-sites"
    namespace = kubernetes_namespace.static_sites[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "static-sites"
    })
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "static-sites"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "static-sites"
        })
      }

      spec {
        # Init containers — one per site to clone the repo
        dynamic "init_container" {
          for_each = var.static_sites
          content {
            name    = "git-clone-${replace(init_container.value.domain, ".", "-")}"
            image   = var.static_sites_git_image
            command = ["sh", "-c", "git clone --branch ${init_container.value.branch} --single-branch --depth 1 ${init_container.value.repo_url} /sites/${init_container.value.domain}"]

            volume_mount {
              name       = "sites"
              mount_path = "/sites"
            }
          }
        }

        # Nginx container
        container {
          name  = "nginx"
          image = var.static_sites_nginx_image

          port {
            container_port = 80
          }

          volume_mount {
            name       = "sites"
            mount_path = "/sites"
            read_only  = true
          }

          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
          }

          resources {
            requests = {
              memory = var.static_sites_memory_request
              cpu    = var.static_sites_cpu_request
            }
            limits = {
              memory = var.static_sites_memory_limit
              cpu    = var.static_sites_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        # Git pull sidecar
        container {
          name    = "git-pull"
          image   = var.static_sites_git_image
          command = ["sh", "/scripts/git-pull.sh"]

          volume_mount {
            name       = "sites"
            mount_path = "/sites"
          }

          volume_mount {
            name       = "nginx-config"
            mount_path = "/scripts/git-pull.sh"
            sub_path   = "git-pull.sh"
          }

          resources {
            requests = {
              memory = "32Mi"
              cpu    = "10m"
            }
            limits = {
              memory = "64Mi"
              cpu    = "50m"
            }
          }
        }

        # Shared volume for site content
        volume {
          name = "sites"
          empty_dir {}
        }

        # Config volume
        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.static_sites_config[0].metadata[0].name
          }
        }
      }
    }
  }
}
```

**Step 2: Add the ClusterIP Service**

```hcl
# Service
resource "kubernetes_service" "static_sites" {
  count = length(var.static_sites) > 0 ? 1 : 0

  depends_on = [
    kubernetes_deployment.static_sites,
  ]

  metadata {
    name      = "static-sites-service"
    namespace = kubernetes_namespace.static_sites[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "static-sites"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "static-sites"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
  }
}
```

**Step 3: Add Outputs**

```hcl
# Outputs
output "static_sites_info" {
  description = "Static sites hosting information"
  value = length(var.static_sites) > 0 ? {
    namespace    = kubernetes_namespace.static_sites[0].metadata[0].name
    service_name = kubernetes_service.static_sites[0].metadata[0].name
    sites        = { for site in var.static_sites : site.domain => site.repo_url }
    poll_interval = "${var.static_sites_git_poll_interval}s"

    commands = {
      check_pods = "kubectl get pods -n static-sites"
      logs_nginx = "kubectl logs -n static-sites -l app=static-sites -c nginx -f"
      logs_git   = "kubectl logs -n static-sites -l app=static-sites -c git-pull -f"
    }
  } : null
}
```

**Step 4: Validate**

Run: `cd terraform && terraform validate`
Expected: Success

**Step 5: Commit**

```bash
git add terraform/static-sites.tf
git commit -m "feat: add static-sites deployment, service, and outputs"
```

---

### Task 4: Add IngressRoutes to ingress.tf

**Files:**
- Modify: `terraform/ingress.tf`

**Step 1: Add a dynamic IngressRoute for each static site**

Append to the end of `ingress.tf`. These use individual domain certs (not the wildcard), and each site gets rate limiting.

```hcl
# --- Static Sites ---

# IngressRoute per static site (each on its own primary domain)
resource "kubernetes_manifest" "ingressroute_static_site" {
  for_each = { for site in var.static_sites : site.domain => site }

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "static-site-${replace(each.key, ".", "-")}"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`${each.key}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.static_sites[0].metadata[0].name
          namespace = kubernetes_namespace.static_sites[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = each.key
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.static_sites,
    kubernetes_manifest.middleware_rate_limit,
  ]
}
```

**Step 2: Validate**

Run: `cd terraform && terraform validate`
Expected: Success

**Step 3: Commit**

```bash
git add terraform/ingress.tf
git commit -m "feat: add IngressRoute for each static site domain"
```

---

### Task 5: Add Azure DNS zones and A records to dns.tf

**Files:**
- Modify: `terraform/dns.tf`

**Step 1: Add DNS zone and A record resources for static sites**

Append to `dns.tf` before the outputs section. Each site gets its own Azure DNS zone and an `@` A record.

```hcl
# --- Static Sites DNS ---

# Create Azure DNS zone for each static site domain
resource "azurerm_dns_zone" "static_sites" {
  for_each = { for site in var.static_sites : site.domain => site }

  name                = each.key
  resource_group_name = var.azure_dns_resource_group

  tags = var.common_labels
}

# Create A record (@) for each static site domain
resource "azurerm_dns_a_record" "static_sites" {
  for_each = { for site in var.static_sites : site.domain => site }

  name                = "@"
  zone_name           = azurerm_dns_zone.static_sites[each.key].name
  resource_group_name = var.azure_dns_resource_group
  ttl                 = var.dns_ttl
  records             = [var.external_ip]

  tags = var.common_labels
}
```

**Step 2: Update the dns_info output to include static site nameservers**

Update the output block to include static site DNS info:

```hcl
output "dns_info" {
  description = "Azure DNS record information"
  value = {
    zone    = data.azurerm_dns_zone.main.name
    records = { for k, v in azurerm_dns_a_record.services : k => "${v.name}.${data.azurerm_dns_zone.main.name}" }
    ip      = var.external_ip
    ttl     = var.dns_ttl

    static_sites = { for k, v in azurerm_dns_zone.static_sites : k => {
      nameservers = v.name_servers
      a_record    = var.external_ip
    }}

    commands = {
      verify = "nslookup grafana.${var.azure_dns_zone_name}"
    }
  }
}
```

**Step 3: Validate**

Run: `cd terraform && terraform validate`
Expected: Success

**Step 4: Commit**

```bash
git add terraform/dns.tf
git commit -m "feat: add Azure DNS zones and A records for static sites"
```

---

### Task 6: Add Makefile targets

**Files:**
- Modify: `terraform/Makefile`

**Step 1: Add to .PHONY line**

Add `plan-static-sites apply-static-sites debug-static-sites status-static-sites` to the .PHONY declaration.

**Step 2: Add help text**

In the help target, add under the component sections:
- Planning: `@echo "  plan-static-sites    Plan static sites components"`
- Deployment: `@echo "  apply-static-sites   Deploy static sites components"`
- Debugging: `@echo "  debug-static-sites   Debug static sites components"`
- Status: `@echo "  status-static-sites  Show static sites status"`

**Step 3: Add the plan target**

```makefile
plan-static-sites: check-vars check-init ## Plan static sites components
	@echo "Planning static sites components..."
	terraform plan \
		-target=kubernetes_namespace.static_sites \
		-target=kubernetes_config_map.static_sites_config \
		-target=kubernetes_deployment.static_sites \
		-target=kubernetes_service.static_sites
```

**Step 4: Add the apply target**

```makefile
apply-static-sites: check-vars check-init ## Deploy static sites components
	@echo "Deploying static sites..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.static_sites \
		-target=kubernetes_config_map.static_sites_config \
		-target=kubernetes_deployment.static_sites \
		-target=kubernetes_service.static_sites
```

**Step 5: Add debug target**

```makefile
debug-static-sites: ## Debug static sites components
	@echo "=== Static Sites Debug ==="
	@echo "Pods:"
	@kubectl get pods -n static-sites -o wide 2>/dev/null || echo "No static-sites pods found"
	@echo ""
	@echo "Nginx Logs (last 20 lines):"
	@kubectl logs -n static-sites -l app=static-sites -c nginx --tail=20 2>/dev/null || echo "No nginx logs"
	@echo ""
	@echo "Git Pull Logs (last 20 lines):"
	@kubectl logs -n static-sites -l app=static-sites -c git-pull --tail=20 2>/dev/null || echo "No git-pull logs"
```

**Step 6: Add status target**

```makefile
status-static-sites: ## Show static sites status
	@echo "=== Static Sites Status ==="
ifeq ($(OS),Windows_NT)
	@kubectl get pods -n static-sites 2>nul || echo "Static sites not deployed"
	@kubectl get svc -n static-sites 2>nul || echo "No services found"
else
	@kubectl get pods -n static-sites 2>/dev/null || echo "Static sites not deployed"
	@kubectl get svc -n static-sites 2>/dev/null || echo "No services found"
endif
```

**Step 7: Add to deploy-apps and plan-all-components**

Add `$(MAKE) apply-static-sites` to the `deploy-apps` target and `$(MAKE) plan-static-sites` to `plan-all-components`. Add `$(MAKE) status-static-sites` to `status-all-components`.

**Step 8: Validate Makefile syntax**

Run: `cd terraform && make help`
Expected: Shows the new static-sites targets in the output

**Step 9: Commit**

```bash
git add terraform/Makefile
git commit -m "feat: add Makefile targets for static-sites"
```

---

### Task 7: Update terraform.tfvars.example and CLAUDE.md

**Files:**
- Modify: `terraform/terraform.tfvars.example`
- Modify: `CLAUDE.md`

**Step 1: Add static sites example config to terraform.tfvars.example**

Append before the Labels section:

```hcl
# Static Sites Configuration
# Each site needs a domain, git repo URL, and branch
static_sites = [
  # { domain = "example.com", repo_url = "https://github.com/user/site.git", branch = "main" },
]
static_sites_git_poll_interval = "60"       # Seconds between git pulls
static_sites_nginx_image       = "nginx:alpine"
static_sites_git_image         = "alpine/git:latest"
static_sites_memory_request    = "64Mi"
static_sites_memory_limit      = "128Mi"
static_sites_cpu_request       = "50m"
static_sites_cpu_limit         = "200m"
# static_sites_git_credentials = "https://user:token@github.com"  # For private repos
```

**Step 2: Update CLAUDE.md file organization**

Add to the file organization list:
- `static-sites.tf` — Nginx static site hosting (git-cloned content, auto-pull sidecar, multi-domain vhosts)

Add to common commands:
- `make plan-static-sites / make apply-static-sites`

**Step 3: Commit**

```bash
git add terraform/terraform.tfvars.example CLAUDE.md
git commit -m "docs: add static-sites configuration examples and docs"
```

---

### Task 8: Run terraform validate and format

**Files:**
- All modified `.tf` files

**Step 1: Format all Terraform files**

Run: `cd terraform && make format`
Expected: Files formatted

**Step 2: Validate full configuration**

Run: `cd terraform && make validate`
Expected: Success with no errors

**Step 3: Commit any formatting changes**

```bash
git add terraform/
git commit -m "chore: format terraform files"
```
