# Wave 0 + Wave 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy the NFS CSI driver for NAS storage access (Wave 0), then deploy CrowdSec intrusion detection, Traefik Bouncer middleware, and GitHub OAuth authentication (Wave 1) — establishing the foundation for all future service migrations.

**Architecture:** NFS CSI driver is installed via Helm into `kube-system`, providing a `nfs-csi` StorageClass that dynamically provisions PVs from the Synology NAS at 192.168.0.148. CrowdSec runs as a DaemonSet (agents) + Deployment (LAPI) in its own namespace, with the Traefik Bouncer integrated as a Traefik plugin middleware. OAuth2-proxy provides GitHub-based SSO as a ForwardAuth middleware, replacing basic auth on protected routes.

**Tech Stack:** Terraform (Kubernetes + Helm providers), Helm charts (csi-driver-nfs, crowdsec, oauth2-proxy), Traefik CRD middlewares (kubernetes_manifest)

---

## Task 1: Create `nfs.tf` — NFS CSI Driver Helm Release

**Files:**
- Create: `terraform/nfs.tf`

**Step 1: Write the NFS CSI driver Terraform file**

```hcl
# =============================================================================
# NFS CSI Driver — Dynamic NFS Provisioning from Synology NAS
# =============================================================================
# Installs the Kubernetes NFS CSI driver via Helm and creates a StorageClass
# for dynamic PV provisioning from the NAS NFS exports.
#
# NAS: 192.168.0.148 (Synology)
# Exports: /volume2/media, /volume2/downloads
# =============================================================================

# Variables
variable "nfs_csi_chart_version" {
  description = "NFS CSI driver Helm chart version"
  type        = string
  default     = "4.11.0"
}

variable "nfs_server" {
  description = "IP address or hostname of the NFS server"
  type        = string
  default     = "192.168.0.148"
}

variable "nfs_media_share" {
  description = "NFS export path for media files"
  type        = string
  default     = "/volume2/media"
}

variable "nfs_downloads_share" {
  description = "NFS export path for downloads"
  type        = string
  default     = "/volume2/downloads"
}

# Helm Release — NFS CSI Driver
resource "helm_release" "nfs_csi_driver" {
  name       = "csi-driver-nfs"
  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts"
  chart      = "csi-driver-nfs"
  version    = var.nfs_csi_chart_version
  namespace  = "kube-system"

  values = [
    yamlencode({
      controller = {
        replicas = 1
      }
    })
  ]

  timeout = 300
  wait    = true
}

# StorageClass — NFS Media (read-write-many, retain)
resource "kubernetes_storage_class" "nfs_media" {
  metadata {
    name   = "nfs-media"
    labels = var.common_labels
  }

  storage_provisioner    = "nfs.csi.k8s.io"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    server = var.nfs_server
    share  = var.nfs_media_share
  }

  mount_options = ["nfsvers=4.1", "hard"]

  depends_on = [helm_release.nfs_csi_driver]
}

# StorageClass — NFS Downloads (read-write-many, retain)
resource "kubernetes_storage_class" "nfs_downloads" {
  metadata {
    name   = "nfs-downloads"
    labels = var.common_labels
  }

  storage_provisioner    = "nfs.csi.k8s.io"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    server = var.nfs_server
    share  = var.nfs_downloads_share
  }

  mount_options = ["nfsvers=4.1", "hard"]

  depends_on = [helm_release.nfs_csi_driver]
}

# Outputs
output "nfs_info" {
  description = "NFS CSI driver information"
  value = {
    nfs_server           = var.nfs_server
    media_storage_class  = kubernetes_storage_class.nfs_media.metadata[0].name
    downloads_storage_class = kubernetes_storage_class.nfs_downloads.metadata[0].name

    commands = {
      check_driver = "kubectl get csidrivers"
      check_sc     = "kubectl get storageclass"
      check_pods   = "kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-nfs"
    }
  }
}
```

**Step 2: Validate Terraform configuration**

Run: `cd terraform && terraform fmt -recursive && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Plan the NFS resources**

Run: `cd terraform && terraform plan -target=helm_release.nfs_csi_driver -target=kubernetes_storage_class.nfs_media -target=kubernetes_storage_class.nfs_downloads`
Expected: Plan shows 3 resources to add (1 Helm release, 2 StorageClasses)

**Step 4: Commit**

```bash
git add terraform/nfs.tf
git commit -m "feat: add NFS CSI driver for Synology NAS storage provisioning"
```

---

## Task 2: Update `terraform.tfvars.example` — NFS Variables

**Files:**
- Modify: `terraform/terraform.tfvars.example`

**Step 1: Add NFS configuration section**

Add the following section after the Storage Configuration section:

```hcl
# NFS Storage Configuration (Synology NAS)
#nfs_csi_chart_version = "4.11.0"
#nfs_server            = "192.168.0.148"
#nfs_media_share       = "/volume2/media"
#nfs_downloads_share   = "/volume2/downloads"
```

**Step 2: Validate**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/terraform.tfvars.example
git commit -m "feat: add NFS configuration to tfvars example"
```

---

## Task 3: Update Makefile — NFS Targets

**Files:**
- Modify: `terraform/Makefile`

**Step 1: Add plan-nfs and apply-nfs targets**

Add after the `apply-static-sites` target block:

```makefile
plan-nfs: check-vars check-init ## Plan NFS CSI driver
	@echo "Planning NFS CSI driver..."
	terraform plan \
		-target=helm_release.nfs_csi_driver \
		-target=kubernetes_storage_class.nfs_media \
		-target=kubernetes_storage_class.nfs_downloads

apply-nfs: check-vars check-init ## Deploy NFS CSI driver
	@echo "Deploying NFS CSI driver..."
	terraform apply -auto-approve \
		-target=helm_release.nfs_csi_driver \
		-target=kubernetes_storage_class.nfs_media \
		-target=kubernetes_storage_class.nfs_downloads
```

Also add to the `.PHONY` declaration at the top: `plan-nfs apply-nfs`

**Step 2: Test the target**

Run: `cd terraform && make plan-nfs`
Expected: Terraform plan output showing 3 resources to add

**Step 3: Commit**

```bash
git add terraform/Makefile
git commit -m "feat: add make targets for NFS CSI driver"
```

---

## Task 4: Deploy and Validate NFS CSI Driver

**Step 1: Apply NFS resources**

Run: `cd terraform && make apply-nfs`
Expected: 3 resources created successfully

**Step 2: Verify CSI driver pods are running**

Run: `kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-nfs`
Expected: Controller pod and node pods running (1 controller + 1 per node = 4 pods total)

**Step 3: Verify StorageClasses created**

Run: `kubectl get storageclass`
Expected: `nfs-media` and `nfs-downloads` StorageClasses listed alongside `longhorn`

**Step 4: Create a test PVC to validate NFS connectivity**

Run:
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-media
  resources:
    requests:
      storage: 1Gi
EOF
```

Then verify: `kubectl get pvc nfs-test-pvc -n default`
Expected: Status is `Bound`

**Step 5: Clean up test PVC**

Run: `kubectl delete pvc nfs-test-pvc -n default`

**Step 6: Commit (no code changes — this is a deploy verification step)**

No commit needed.

---

## Task 5: Create `crowdsec.tf` — CrowdSec Security Engine

**Files:**
- Create: `terraform/crowdsec.tf`

**Step 1: Write the CrowdSec Terraform file**

```hcl
# =============================================================================
# CrowdSec Security Engine
# =============================================================================
# CrowdSec provides intrusion detection using community threat intelligence.
# Deploys as:
#   - LAPI (Local API): Central decision engine (Deployment)
#   - Agent: Log processor on each node (DaemonSet)
#
# The Traefik Bouncer plugin (configured in traefik.tf) queries LAPI to
# block malicious IPs at the ingress level.
# =============================================================================

# Variables
variable "crowdsec_chart_version" {
  description = "CrowdSec Helm chart version"
  type        = string
  default     = "0.22.0"
}

variable "crowdsec_bouncer_key" {
  description = "API key for the Traefik bouncer to authenticate with CrowdSec LAPI. Generate with: openssl rand -hex 32"
  type        = string
  sensitive   = true
}

variable "crowdsec_enroll_key" {
  description = "CrowdSec console enrollment key (optional, from app.crowdsec.net)"
  type        = string
  default     = ""
}

# Namespace
resource "kubernetes_namespace" "crowdsec" {
  metadata {
    name = "crowdsec"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "crowdsec"
    })
  }
}

# Helm Release — CrowdSec
resource "helm_release" "crowdsec" {
  name       = "crowdsec"
  repository = "https://crowdsecurity.github.io/helm-charts"
  chart      = "crowdsec"
  version    = var.crowdsec_chart_version
  namespace  = kubernetes_namespace.crowdsec.metadata[0].name

  values = [
    yamlencode({
      container_runtime = "containerd"

      lapi = {
        env = concat(
          var.crowdsec_enroll_key != "" ? [
            {
              name  = "ENROLL_KEY"
              value = var.crowdsec_enroll_key
            },
            {
              name  = "ENROLL_INSTANCE_NAME"
              value = "homelab-k8s"
            },
          ] : [],
          []
        )

        persistentVolume = {
          data = {
            enabled       = true
            accessModes   = ["ReadWriteOnce"]
            storageClassName = data.kubernetes_storage_class.longhorn.metadata[0].name
            size          = "1Gi"
          }
          config = {
            enabled       = true
            accessModes   = ["ReadWriteOnce"]
            storageClassName = data.kubernetes_storage_class.longhorn.metadata[0].name
            size          = "100Mi"
          }
        }

        resources = {
          requests = {
            memory = "256Mi"
            cpu    = "100m"
          }
          limits = {
            memory = "512Mi"
            cpu    = "500m"
          }
        }
      }

      agent = {
        acquisition = [
          {
            namespace = "traefik"
            podName   = "traefik-*"
            program   = "traefik"
          },
        ]

        resources = {
          requests = {
            memory = "128Mi"
            cpu    = "100m"
          }
          limits = {
            memory = "256Mi"
            cpu    = "500m"
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.crowdsec,
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn,
  ]

  timeout = 300
  wait    = true
}

# Outputs
output "crowdsec_info" {
  description = "CrowdSec security engine information"
  value = {
    namespace    = kubernetes_namespace.crowdsec.metadata[0].name
    lapi_service = "crowdsec-service.${kubernetes_namespace.crowdsec.metadata[0].name}.svc.cluster.local:8080"

    commands = {
      check_pods    = "kubectl get pods -n ${kubernetes_namespace.crowdsec.metadata[0].name}"
      check_lapi    = "kubectl exec -n ${kubernetes_namespace.crowdsec.metadata[0].name} -it deploy/crowdsec-lapi -- cscli decisions list"
      list_bouncers = "kubectl exec -n ${kubernetes_namespace.crowdsec.metadata[0].name} -it deploy/crowdsec-lapi -- cscli bouncers list"
      add_bouncer   = "kubectl exec -n ${kubernetes_namespace.crowdsec.metadata[0].name} -it deploy/crowdsec-lapi -- cscli bouncers add traefik-bouncer"
    }
  }
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt -recursive && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/crowdsec.tf
git commit -m "feat: add CrowdSec security engine with LAPI and agent"
```

---

## Task 6: Modify `traefik.tf` — Add CrowdSec Bouncer Plugin

**Files:**
- Modify: `terraform/traefik.tf`

**Step 1: Add the CrowdSec bouncer plugin to Traefik Helm values**

In the `helm_release.traefik` resource, add the `experimental.plugins` section and Traefik access log configuration to the `values` block. The exact location depends on the current values structure — add these top-level keys to the yamlencode block:

```hcl
# Add to the yamlencode block in helm_release.traefik values:
experimental = {
  plugins = {
    bouncer = {
      moduleName = "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
      version    = "v1.5.1"
    }
  }
}

logs = {
  access = {
    enabled = true
    format  = "json"
  }
}
```

Also add `helm_release.crowdsec` to the `depends_on` list if CrowdSec is deployed before Traefik, or alternatively note that CrowdSec should be deployed first.

**Step 2: Validate**

Run: `cd terraform && terraform fmt -recursive && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/traefik.tf
git commit -m "feat: add CrowdSec bouncer plugin to Traefik"
```

---

## Task 7: Modify `ingress.tf` — Add CrowdSec Bouncer Middleware

**Files:**
- Modify: `terraform/ingress.tf`

**Step 1: Add the CrowdSec bouncer Middleware CRD resource**

Add after the existing middleware resources (after `kubernetes_manifest.middleware_basic_auth`):

```hcl
# CrowdSec Bouncer Middleware
resource "kubernetes_manifest" "middleware_crowdsec_bouncer" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "crowdsec-bouncer"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      plugin = {
        bouncer = {
          Enabled              = "true"
          crowdsecMode         = "stream"
          crowdsecLapiHost     = "crowdsec-service.${kubernetes_namespace.crowdsec.metadata[0].name}.svc.cluster.local:8080"
          crowdsecLapiScheme   = "http"
          crowdsecLapiKey      = var.crowdsec_bouncer_key
          updateIntervalSeconds = 15
        }
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.crowdsec,
  ]
}
```

**Step 2: Add the bouncer middleware to all existing IngressRoute resources**

For each IngressRoute (grafana, prometheus, alertmanager, baget, longhorn, dashboard, traefik-dashboard, static sites), add the crowdsec-bouncer middleware reference to the `middlewares` list:

```hcl
{
  name      = "crowdsec-bouncer"
  namespace = kubernetes_namespace.traefik.metadata[0].name
},
```

Also add `kubernetes_manifest.middleware_crowdsec_bouncer` to each IngressRoute's `depends_on` list.

**Step 3: Validate**

Run: `cd terraform && terraform fmt -recursive && terraform validate`
Expected: "Success! The configuration is valid."

**Step 4: Commit**

```bash
git add terraform/ingress.tf
git commit -m "feat: add CrowdSec bouncer middleware to all ingress routes"
```

---

## Task 8: Create `oauth.tf` — OAuth2 Proxy with GitHub Provider

**Files:**
- Create: `terraform/oauth.tf`

**Step 1: Write the OAuth2 Proxy Terraform file**

```hcl
# =============================================================================
# OAuth2 Proxy — GitHub SSO for Protected Services
# =============================================================================
# Deploys oauth2-proxy as a ForwardAuth middleware for Traefik.
# Users authenticate via GitHub, replacing basic auth on protected routes.
#
# Setup: Create a GitHub OAuth App at https://github.com/settings/developers
#   - Homepage URL: https://auth.<your-domain>
#   - Callback URL: https://auth.<your-domain>/oauth2/callback
# =============================================================================

# Variables
variable "oauth2_proxy_chart_version" {
  description = "OAuth2 Proxy Helm chart version"
  type        = string
  default     = "10.1.4"
}

variable "oauth_github_client_id" {
  description = "GitHub OAuth App client ID"
  type        = string
  sensitive   = true
}

variable "oauth_github_client_secret" {
  description = "GitHub OAuth App client secret"
  type        = string
  sensitive   = true
}

variable "oauth_cookie_secret" {
  description = "Random 32-byte base64 secret for cookie encryption. Generate with: openssl rand -base64 32 | head -c 32"
  type        = string
  sensitive   = true
}

variable "oauth_github_user" {
  description = "GitHub username allowed to authenticate (comma-separated for multiple)"
  type        = string
}

variable "oauth_enabled" {
  description = "Enable OAuth2 proxy deployment"
  type        = bool
  default     = true
}

# Namespace
resource "kubernetes_namespace" "oauth2_proxy" {
  count = var.oauth_enabled ? 1 : 0

  metadata {
    name = "oauth2-proxy"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "oauth2-proxy"
    })
  }
}

# Helm Release — OAuth2 Proxy
resource "helm_release" "oauth2_proxy" {
  count = var.oauth_enabled ? 1 : 0

  name       = "oauth2-proxy"
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  version    = var.oauth2_proxy_chart_version
  namespace  = kubernetes_namespace.oauth2_proxy[0].metadata[0].name

  values = [
    yamlencode({
      config = {
        clientID     = var.oauth_github_client_id
        clientSecret = var.oauth_github_client_secret
        cookieSecret = var.oauth_cookie_secret
      }

      extraArgs = {
        provider               = "github"
        github-user            = var.oauth_github_user
        cookie-secure          = "true"
        cookie-domain          = ".${var.traefik_domain}"
        set-xauthrequest       = "true"
        reverse-proxy          = "true"
        set-authorization-header = "true"
        email-domain           = "*"
        whitelist-domain       = ".${var.traefik_domain}"
        cookie-csrf-per-request = "true"
        skip-provider-button   = "true"
      }

      service = {
        type = "ClusterIP"
      }

      resources = {
        requests = {
          memory = "64Mi"
          cpu    = "50m"
        }
        limits = {
          memory = "128Mi"
          cpu    = "200m"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.oauth2_proxy[0],
  ]

  timeout = 300
  wait    = true
}

# Outputs
output "oauth2_proxy_info" {
  description = "OAuth2 Proxy information"
  value = var.oauth_enabled ? {
    namespace = kubernetes_namespace.oauth2_proxy[0].metadata[0].name
    auth_url  = "https://auth.${var.traefik_domain}"

    setup = {
      github_oauth_app = "Create at https://github.com/settings/developers"
      homepage_url     = "https://auth.${var.traefik_domain}"
      callback_url     = "https://auth.${var.traefik_domain}/oauth2/callback"
    }

    commands = {
      check_pods = "kubectl get pods -n oauth2-proxy"
      check_logs = "kubectl logs -n oauth2-proxy -l app.kubernetes.io/name=oauth2-proxy -f"
    }
  } : null

  sensitive = true
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt -recursive && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/oauth.tf
git commit -m "feat: add OAuth2 Proxy with GitHub SSO"
```

---

## Task 9: Modify `ingress.tf` — Add ForwardAuth Middleware for OAuth

**Files:**
- Modify: `terraform/ingress.tf`

**Step 1: Add the ForwardAuth middleware for OAuth2 Proxy**

Add after the crowdsec-bouncer middleware:

```hcl
# OAuth2 Proxy ForwardAuth Middleware
resource "kubernetes_manifest" "middleware_oauth_forward_auth" {
  count = var.oauth_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "oauth-forward-auth"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      forwardAuth = {
        address             = "http://oauth2-proxy.${kubernetes_namespace.oauth2_proxy[0].metadata[0].name}.svc.cluster.local/oauth2/auth"
        trustForwardHeader  = true
        authResponseHeaders = [
          "X-Auth-Request-User",
          "X-Auth-Request-Email",
          "X-Auth-Request-Access-Token",
          "Set-Cookie",
        ]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.oauth2_proxy,
  ]
}
```

**Step 2: Add an IngressRoute for the OAuth2 Proxy callback endpoint**

```hcl
# OAuth2 Proxy IngressRoute (callback + sign-in)
resource "kubernetes_manifest" "ingressroute_oauth2_proxy" {
  count = var.oauth_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "oauth2-proxy"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`auth.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "oauth2-proxy"
          namespace = kubernetes_namespace.oauth2_proxy[0].metadata[0].name
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
    helm_release.oauth2_proxy,
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
  ]
}
```

**Step 3: Replace basic-auth middleware with oauth-forward-auth on protected routes**

For IngressRoutes that currently use `basic-auth` (prometheus, alertmanager, traefik-dashboard, longhorn), replace the basic-auth middleware reference:

```hcl
# Replace this:
{
  name      = "basic-auth"
  namespace = kubernetes_namespace.traefik.metadata[0].name
},

# With this:
{
  name      = "oauth-forward-auth"
  namespace = kubernetes_namespace.traefik.metadata[0].name
},
```

Keep basic-auth available as a fallback by not removing the middleware resource itself.

**Step 4: Validate**

Run: `cd terraform && terraform fmt -recursive && terraform validate`
Expected: "Success! The configuration is valid."

**Step 5: Commit**

```bash
git add terraform/ingress.tf
git commit -m "feat: add OAuth ForwardAuth middleware and replace basic auth on protected routes"
```

---

## Task 10: Update `terraform.tfvars.example` — Wave 1 Variables

**Files:**
- Modify: `terraform/terraform.tfvars.example`

**Step 1: Add CrowdSec and OAuth sections**

Add after the NFS section:

```hcl
# CrowdSec Security Engine
#crowdsec_chart_version = "0.22.0"
#crowdsec_bouncer_key   = "your-bouncer-api-key-here-generate-with-openssl-rand-hex-32"
#crowdsec_enroll_key    = ""  # Optional: from https://app.crowdsec.net

# OAuth2 Proxy (GitHub SSO)
#oauth2_proxy_chart_version = "10.1.4"
#oauth_github_client_id     = "your-github-oauth-app-client-id"
#oauth_github_client_secret = "your-github-oauth-app-client-secret"
#oauth_cookie_secret         = "your-32-byte-base64-secret"
#oauth_github_user           = "your-github-username"
#oauth_enabled               = true
```

**Step 2: Validate**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/terraform.tfvars.example
git commit -m "feat: add CrowdSec and OAuth variables to tfvars example"
```

---

## Task 11: Update Makefile — CrowdSec and OAuth Targets

**Files:**
- Modify: `terraform/Makefile`

**Step 1: Add plan/apply targets for CrowdSec and OAuth**

Add after the NFS targets:

```makefile
plan-crowdsec: check-vars check-init ## Plan CrowdSec security engine
	@echo "Planning CrowdSec components..."
	terraform plan \
		-target=kubernetes_namespace.crowdsec \
		-target=helm_release.crowdsec

apply-crowdsec: check-vars check-init ## Deploy CrowdSec security engine
	@echo "Deploying CrowdSec..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.crowdsec \
		-target=helm_release.crowdsec

plan-oauth: check-vars check-init ## Plan OAuth2 Proxy
	@echo "Planning OAuth2 Proxy..."
	terraform plan \
		-target=kubernetes_namespace.oauth2_proxy \
		-target=helm_release.oauth2_proxy

apply-oauth: check-vars check-init ## Deploy OAuth2 Proxy
	@echo "Deploying OAuth2 Proxy..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.oauth2_proxy \
		-target=helm_release.oauth2_proxy
```

Add to `.PHONY`: `plan-crowdsec apply-crowdsec plan-oauth apply-oauth`

**Step 2: Commit**

```bash
git add terraform/Makefile
git commit -m "feat: add make targets for CrowdSec and OAuth"
```

---

## Task 12: Update `dns.tf` — Add Auth Subdomain

**Files:**
- Modify: `terraform/dns.tf`

**Step 1: Add `auth` to the dns_records local**

In the `locals` block, add to the `dns_records` map:

```hcl
auth = "auth"
```

This creates an A record for `auth.<domain>` pointing to the external IP, needed for the OAuth2 Proxy callback.

**Step 2: Validate and commit**

Run: `cd terraform && terraform fmt -recursive && terraform validate`

```bash
git add terraform/dns.tf
git commit -m "feat: add auth subdomain DNS record for OAuth"
```

---

## Task 13: Deploy Wave 1 — CrowdSec + Bouncer + OAuth

This task covers the sequential deployment of all Wave 1 components.

**Step 1: Configure terraform.tfvars**

Add real values to `terraform/terraform.tfvars` for:
- `crowdsec_bouncer_key` — generate with `openssl rand -hex 32`
- `oauth_github_client_id` — from GitHub OAuth App
- `oauth_github_client_secret` — from GitHub OAuth App
- `oauth_cookie_secret` — generate with `openssl rand -base64 32 | head -c 32`
- `oauth_github_user` — your GitHub username

**Step 2: Deploy CrowdSec**

Run: `cd terraform && make apply-crowdsec`
Expected: Namespace and Helm release created

**Step 3: Verify CrowdSec is running**

Run: `kubectl get pods -n crowdsec`
Expected: LAPI pod and agent pods (one per node) are Running

**Step 4: Register the bouncer with CrowdSec LAPI**

Run: `kubectl exec -n crowdsec -it deploy/crowdsec-lapi -- cscli bouncers add traefik-bouncer -k <your-bouncer-key>`
Where `<your-bouncer-key>` matches `crowdsec_bouncer_key` in terraform.tfvars.

**Step 5: Update Traefik (to add the plugin)**

Run: `cd terraform && make apply-traefik`
Expected: Traefik Helm release updated with plugin configuration. Traefik pods restart.

**Step 6: Deploy OAuth2 Proxy**

Run: `cd terraform && make apply-oauth`
Expected: Namespace and Helm release created

**Step 7: Deploy updated ingress routes**

Run: `cd terraform && make apply-ingress`
Expected: New middlewares (crowdsec-bouncer, oauth-forward-auth) and updated IngressRoutes applied

**Step 8: Deploy DNS for auth subdomain**

Run: `cd terraform && make apply-azure-dns`
Expected: `auth.<domain>` A record created

**Step 9: Verify OAuth flow**

Open `https://auth.<domain>` in a browser.
Expected: Redirects to GitHub for authentication, then shows the OAuth2 proxy page.

**Step 10: Verify protected route**

Open `https://grafana.<domain>` in a browser.
Expected: Redirects to GitHub OAuth instead of showing a basic auth prompt.

**Step 11: Verify CrowdSec bouncing**

Run: `kubectl exec -n crowdsec -it deploy/crowdsec-lapi -- cscli decisions list`
Expected: Shows active decisions (may be empty initially, which is fine)

---

## Deployment Order Summary

```
Wave 0:
  1. make apply-nfs           → NFS CSI driver + StorageClasses

Wave 1 (sequential):
  2. make apply-crowdsec      → CrowdSec LAPI + agents
  3. Register bouncer key     → cscli bouncers add
  4. make apply-traefik       → Traefik with bouncer plugin
  5. make apply-oauth         → OAuth2 Proxy
  6. make apply-ingress       → Updated middlewares + routes
  7. make apply-azure-dns     → Auth subdomain DNS
```
