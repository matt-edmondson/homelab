# Pi-hole DNS Sync for Kubernetes LoadBalancer Services
# This creates an in-cluster deployment that automatically updates Pi-hole DNS records

# ServiceAccount for Pi-hole DNS sync
resource "kubernetes_service_account" "pihole_dns_sync" {
  count = var.pihole_enabled ? 1 : 0
  
  metadata {
    name      = "pihole-dns-sync"
    namespace = "kube-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "pihole-dns-sync"
    })
  }
}

# ClusterRole for Pi-hole DNS sync
resource "kubernetes_cluster_role" "pihole_dns_sync" {
  count = var.pihole_enabled ? 1 : 0
  
  metadata {
    name = "pihole-dns-sync"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "pihole-dns-sync"
    })
  }

  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "watch", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create"]
  }
}

# ClusterRoleBinding for Pi-hole DNS sync
resource "kubernetes_cluster_role_binding" "pihole_dns_sync" {
  count = var.pihole_enabled ? 1 : 0
  
  metadata {
    name = "pihole-dns-sync"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "pihole-dns-sync"
    })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.pihole_dns_sync[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.pihole_dns_sync[0].metadata[0].name
    namespace = kubernetes_service_account.pihole_dns_sync[0].metadata[0].namespace
  }
}

# ConfigMap with the embedded sync script
resource "kubernetes_config_map" "pihole_sync_script" {
  count = var.pihole_enabled ? 1 : 0
  
  metadata {
    name      = "pihole-sync-script"
    namespace = "kube-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "pihole-dns-sync"
    })
  }

  data = {
    "sync.sh" = <<-EOT
#!/bin/bash
set -euo pipefail

# Configuration from environment variables
PIHOLE_HOST="$${PIHOLE_HOST:-192.168.0.100}"
PIHOLE_API_URL="http://$${PIHOLE_HOST}/admin/api.php"
PIHOLE_API_KEY="$${PIHOLE_API_KEY:-}"  # Empty means no auth required
DOMAIN="$${DOMAIN:-homelab.local}"
SYNC_INTERVAL="$${SYNC_INTERVAL:-60}"

# Service mappings from environment variable
SERVICE_MAPPINGS_JSON="$${SERVICE_MAPPINGS_JSON:-{}}"

# Parse service mappings from JSON
declare -A SERVICE_MAPPINGS
if [[ -n "$SERVICE_MAPPINGS_JSON" ]] && [[ "$SERVICE_MAPPINGS_JSON" != "{}" ]]; then
    while IFS="=" read -r key value; do
        if [[ -n "$key" && -n "$value" ]]; then
            SERVICE_MAPPINGS["$key"]="$value"
        fi
    done < <(echo "$SERVICE_MAPPINGS_JSON" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
fi

# Logging
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
log_info() { log "INFO: $1"; }
log_success() { log "SUCCESS: $1"; }
log_warning() { log "WARNING: $1"; }
log_error() { log "ERROR: $1"; }

# Test Pi-hole connection
test_pihole_connection() {
    local response
    if ! response=$(curl -s --connect-timeout 10 "$${PIHOLE_API_URL}?status" 2>/dev/null); then
        log_error "Failed to connect to Pi-hole at $${PIHOLE_API_URL}"
        return 1
    fi
    
    if echo "$response" | jq -e '.status == "enabled"' >/dev/null 2>&1; then
        log_success "Pi-hole connection successful"
        return 0
    else
        log_error "Pi-hole returned unexpected status: $response"
        return 1
    fi
}

# Get LoadBalancer services from Kubernetes
get_loadbalancer_services() {
    local services_json
    if ! services_json=$(kubectl get services --all-namespaces -o json 2>/dev/null); then
        log_error "Failed to get LoadBalancer services"
        return 1
    fi
    
    echo "$services_json" | jq -r '
        .items[] | 
        select(.spec.type == "LoadBalancer" and .status.loadBalancer.ingress) |
        "\(.metadata.namespace)/\(.metadata.name):\(.status.loadBalancer.ingress[0].ip)"
    ' 2>/dev/null || true
}

# Get current Pi-hole local DNS records
get_pihole_dns_records() {
    local url="$${PIHOLE_API_URL}?customdns"
    
    # Add auth if API key is provided
    if [[ -n "$${PIHOLE_API_KEY}" ]]; then
        url="$${url}&auth=$${PIHOLE_API_KEY}"
    fi
    
    local response
    if ! response=$(curl -s --connect-timeout 10 "$url" 2>/dev/null); then
        log_error "Failed to get Pi-hole DNS records"
        return 1
    fi
    
    # Parse JSON response and output hostname:ip pairs
    echo "$response" | jq -r '.data[]? | "\(.domain):\(.ip)"' 2>/dev/null || true
}

# Set Pi-hole local DNS record
set_pihole_dns_record() {
    local hostname="$1"
    local ip="$2"
    local full_hostname="$${hostname}.$${DOMAIN}"
    
    local curl_data="domain=$${full_hostname}&ip=$${ip}&action=add"
    
    # Add auth if API key is provided
    if [[ -n "$${PIHOLE_API_KEY}" ]]; then
        curl_data="$${curl_data}&auth=$${PIHOLE_API_KEY}"
    fi
    
    local response
    if ! response=$(curl -s --connect-timeout 10 -X POST -d "$curl_data" "$${PIHOLE_API_URL}" 2>/dev/null); then
        log_error "Failed to set Pi-hole DNS record for $hostname"
        return 1
    fi
    
    # Check for success indicators in response
    if echo "$response" | grep -q "success\|Successfully" || echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        log_success "Updated DNS record: $${full_hostname} -> $ip"
        return 0
    else
        log_error "Failed to update DNS record for $${full_hostname}: $response"
        return 1
    fi
}

# Clear Pi-hole DNS cache
clear_pihole_dns_cache() {
    local url="$${PIHOLE_API_URL}?restartdns"
    
    # Add auth if API key is provided
    if [[ -n "$${PIHOLE_API_KEY}" ]]; then
        url="$${url}&auth=$${PIHOLE_API_KEY}"
    fi
    
    local response
    if ! response=$(curl -s --connect-timeout 10 "$url" 2>/dev/null); then
        log_error "Failed to clear Pi-hole DNS cache"
        return 1
    fi
    
    if echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        log_success "Pi-hole DNS cache cleared"
        return 0
    else
        log_warning "DNS cache clear may have failed: $response"
        return 0  # Don't fail the sync for this
    fi
}

# Sync services to Pi-hole DNS
sync_services_to_pihole() {
    local services_data="$1"
    local changes=false
    
    # Get current DNS records
    local dns_records_data
    if ! dns_records_data=$(get_pihole_dns_records); then
        log_error "Failed to get current Pi-hole DNS records"
        return 1
    fi
    
    # Parse current DNS records
    declare -A current_dns_records
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local hostname="$${line%:*}"
            local ip="$${line##*:}"
            current_dns_records["$hostname"]="$ip"
        fi
    done <<< "$dns_records_data"
    
    # Parse services data
    declare -A service_ip_map
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local key="$${line%:*}"
            local ip="$${line##*:}"
            service_ip_map["$key"]="$ip"
        fi
    done <<< "$services_data"
    
    # Update records for active services
    for service_key in "$${!SERVICE_MAPPINGS[@]}"; do
        local dns_name="$${SERVICE_MAPPINGS[$service_key]}"
        local full_hostname="$${dns_name}.$${DOMAIN}"
        
        if [[ -n "$${service_ip_map[$service_key]:-}" ]]; then
            local service_ip="$${service_ip_map[$service_key]}"
            local current_ip="$${current_dns_records[$full_hostname]:-}"
            
            if [[ "$current_ip" != "$service_ip" ]]; then
                log_info "Updating DNS record for $dns_name: $${current_ip:-none} -> $service_ip"
                if set_pihole_dns_record "$dns_name" "$service_ip"; then
                    changes=true
                fi
            else
                log_info "DNS record for $dns_name is up to date: $service_ip"
            fi
        else
            # Service not found but DNS record exists
            if [[ -n "$${current_dns_records[$full_hostname]:-}" ]]; then
                log_warning "Service $service_key not found but DNS record exists for $full_hostname"
            fi
        fi
    done
    
    # Clear DNS cache if changes were made
    if [[ "$changes" == "true" ]]; then
        clear_pihole_dns_cache || true
    fi
    
    return 0
}

# Show sync status
show_sync_status() {
    local services_data="$1"
    
    log_info "Current sync status:"
    
    # Get current DNS records
    local dns_records_data
    if ! dns_records_data=$(get_pihole_dns_records); then
        log_error "Failed to get Pi-hole DNS records for status"
        return 1
    fi
    
    # Parse DNS records
    declare -A dns_records
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local hostname="$${line%:*}"
            local ip="$${line##*:}"
            dns_records["$hostname"]="$ip"
        fi
    done <<< "$dns_records_data"
    
    # Parse services data
    declare -A service_ip_map
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local key="$${line%:*}"
            local ip="$${line##*:}"
            service_ip_map["$key"]="$ip"
        fi
    done <<< "$services_data"
    
    # Show status for each service
    for service_key in "$${!SERVICE_MAPPINGS[@]}"; do
        local dns_name="$${SERVICE_MAPPINGS[$service_key]}"
        local full_hostname="$${dns_name}.$${DOMAIN}"
        
        if [[ -n "$${service_ip_map[$service_key]:-}" ]]; then
            local service_ip="$${service_ip_map[$service_key]}"
            local dns_ip="$${dns_records[$full_hostname]:-}"
            
            if [[ "$dns_ip" == "$service_ip" ]]; then
                log_success "✓ $dns_name: K8s=$service_ip DNS=$dns_ip (SYNCED)"
            else
                log_warning "⚠ $dns_name: K8s=$service_ip DNS=$${dns_ip:-none} (OUT OF SYNC)"
            fi
        else
            local dns_ip="$${dns_records[$full_hostname]:-}"
            if [[ -n "$dns_ip" ]]; then
                log_warning "✗ $dns_name: K8s=none DNS=$dns_ip (ORPHANED DNS RECORD)"
            else
                log_info "○ $dns_name: K8s=none DNS=none (NOT DEPLOYED)"
            fi
        fi
    done
}

# Main sync loop
main() {
    log_info "Starting Pi-hole DNS sync for Kubernetes LoadBalancer services"
    log_info "Pi-hole Host: $PIHOLE_HOST"
    log_info "Domain: $DOMAIN"
    log_info "Sync Interval: $SYNC_INTERVAL seconds"
    log_info "Authentication: $$(if [[ -n "$PIHOLE_API_KEY" ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    
    # Test Pi-hole connection
    if ! test_pihole_connection; then
        log_error "Cannot connect to Pi-hole. Exiting."
        exit 1
    fi
    
    log_info "Service mappings configured: $${#SERVICE_MAPPINGS[@]} services"
    log_info "Monitored services:"
    for service_key in "$${!SERVICE_MAPPINGS[@]}"; do
        local dns_name="$${SERVICE_MAPPINGS[$service_key]}"
        log_info "  $service_key -> $${dns_name}.$${DOMAIN}"
    done
    
    if [[ $${#SERVICE_MAPPINGS[@]} -eq 0 ]]; then
        log_warning "No service mappings configured! Pi-hole sync will not create any DNS entries."
        log_info "To configure service mappings:"
        log_info "1. Add pihole_service_mappings to your terraform.tfvars file"
        log_info "2. Use ./nginx-sync/find-services.sh to discover your LoadBalancer services"
        log_info "3. Run: terraform apply"
        log_info "Current SERVICE_MAPPINGS_JSON: $SERVICE_MAPPINGS_JSON"
        log_info "The sync will continue running and check for configuration changes..."
    fi
    
    while true; do
        {
            log_info "Checking Kubernetes services..."
            
            # Get current services
            local services_data
            if services_data=$(get_loadbalancer_services); then
                local service_count=$(echo "$services_data" | grep -c . || echo "0")
                
                if [[ $service_count -gt 0 ]]; then
                    log_info "Found $service_count LoadBalancer services"
                    
                    # Sync to Pi-hole DNS
                    if sync_services_to_pihole "$services_data"; then
                        # Show current status
                        show_sync_status "$services_data"
                    else
                        log_error "Failed to sync services to Pi-hole"
                    fi
                else
                    log_warning "No LoadBalancer services found"
                fi
            else
                log_error "Failed to get LoadBalancer services"
            fi
            
            log_info "Next sync in $SYNC_INTERVAL seconds..."
            sleep "$SYNC_INTERVAL"
            
        } || {
            log_error "Error in sync loop, retrying in $SYNC_INTERVAL seconds..."
            sleep "$SYNC_INTERVAL"
        }
    done
}

# Run main function
main "$@"
    EOT
  }
}

# Secret for Pi-hole configuration (only if password is provided)
resource "kubernetes_secret" "pihole_credentials" {
  count = var.pihole_enabled && var.pihole_webpassword != "" ? 1 : 0
  
  metadata {
    name      = "pihole-credentials"
    namespace = "kube-system"
    labels    = var.common_labels
  }

  data = {
    api_key = base64encode(var.pihole_webpassword)
  }
  
  type = "Opaque"
}

# Deployment for Pi-hole DNS sync
resource "kubernetes_deployment" "pihole_dns_sync" {
  count = var.pihole_enabled ? 1 : 0
  
  metadata {
    name      = "pihole-dns-sync"
    namespace = "kube-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"    = "pihole-dns-sync"
      "app.kubernetes.io/version" = "1.0.0"
    })
  }

  spec {
    replicas = 1
    
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "pihole-dns-sync"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name" = "pihole-dns-sync"
        })
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.pihole_dns_sync[0].metadata[0].name
        
        container {
          name  = "pihole-dns-sync"
          image = "alpine/curl:3.14"
          
          command = ["/bin/sh"]
          args = [
            "-c",
            <<-EOT
              # Install required packages
              apk add --no-cache bash jq kubectl
              
              # Copy sync script from ConfigMap and make executable
              cp /scripts/sync.sh /usr/local/bin/sync.sh
              chmod +x /usr/local/bin/sync.sh
              
              # Run the sync script
              exec /usr/local/bin/sync.sh
            EOT
          ]

          env {
            name  = "PIHOLE_HOST"
            value = var.pihole_host
          }

          # Only set API key if authentication is required
          dynamic "env" {
            for_each = var.pihole_webpassword != "" ? [1] : []
            content {
              name = "PIHOLE_API_KEY"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.pihole_credentials[0].metadata[0].name
                  key  = "api_key"
                }
              }
            }
          }

          env {
            name  = "DOMAIN"
            value = var.homelab_domain
          }

          env {
            name  = "SYNC_INTERVAL"
            value = "60"
          }

          env {
            name  = "SERVICE_MAPPINGS_JSON"
            value = jsonencode(var.pihole_service_mappings)
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
          }

          resources {
            limits = {
              memory = "128Mi"
              cpu    = "100m"
            }
            requests = {
              memory = "64Mi"
              cpu    = "10m"
            }
          }

          liveness_probe {
            exec {
              command = ["pgrep", "-f", "sync.sh"]
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["pgrep", "-f", "sync.sh"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          security_context {
            run_as_non_root             = true
            run_as_user                 = 65534
            allow_privilege_escalation  = false
            read_only_root_filesystem   = false
            
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "scripts"
          config_map {
            name = kubernetes_config_map.pihole_sync_script[0].metadata[0].name
            default_mode = 0755
          }
        }

        restart_policy = "Always"
        
        security_context {
          fs_group = 65534
        }
      }
    }
  }
}

# Service for Pi-hole DNS sync (for monitoring/metrics)
resource "kubernetes_service" "pihole_dns_sync" {
  count = var.pihole_enabled ? 1 : 0
  
  metadata {
    name      = "pihole-dns-sync"
    namespace = "kube-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "pihole-dns-sync"
    })
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "8080"
      "prometheus.io/path"   = "/metrics"
    }
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "pihole-dns-sync"
    }

    port {
      name        = "metrics"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
