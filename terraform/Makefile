# Cross-platform help - Simple approach that works everywhere
# We'll hardcode the help sections for reliability

.PHONY: help init plan apply destroy force-clean destroy-clean validate format lint check-vars status clean \
	plan-networking plan-storage plan-monitoring plan-applications plan-dns \
	apply-networking apply-storage apply-monitoring apply-applications apply-dns \
	debug-networking debug-storage debug-monitoring debug-applications debug-dns \
	status-networking status-storage status-monitoring status-applications status-dns \
	list-components deploy-core deploy-apps plan-all-components status-all-components \
	show-structure quick-debug taint-component

# Default target
help: ## Show this help message
	@echo "Kubernetes Homelab Terraform Management (Modular Structure)"
	@echo "Usage: make [target]"
	@echo ""
	@echo "🚀 QUICK START:"
	@echo "  make list-components  # See all infrastructure components"
	@echo "  make setup           # Initialize and validate"
	@echo "  make deploy          # Full deployment"
	@echo ""
	@echo "📋 GENERAL TARGETS:"
	@echo "  help                 Show this help message"
	@echo "  init                 Initialize Terraform"
	@echo "  plan                 Plan Terraform deployment"
	@echo "  apply                Apply Terraform configuration"
	@echo "  destroy              Destroy Terraform infrastructure"
	@echo "  force-clean          Force cleanup of all resources (use when destroy fails)"
	@echo "  destroy-clean        Alias for force-clean"
	@echo "  validate             Validate Terraform configuration"
	@echo "  format               Format Terraform files"
	@echo "  lint                 Lint and validate Terraform code"
	@echo "  check-vars           Check if terraform.tfvars exists"
	@echo "  status               Show current deployment status"
	@echo "  clean                Clean Terraform cache and state"
	@echo "  setup                Complete setup process"
	@echo "  deploy               Full deployment"
	@echo "  generate-secrets     Generate secure passwords"
	@echo "  list-components      List all infrastructure components"
	@echo "  logs                 Show logs for all deployed applications"
	@echo "  bgp-status           Check BGP configuration status"
	@echo "  deploy-core          Deploy core infrastructure"
	@echo "  deploy-apps          Deploy applications"
	@echo "  show-structure       Show the modular file structure"
	@echo "  quick-debug          Quick debug of all components"
	@echo "  taint-component      Taint a component for recreation"
	@echo ""
	@echo "🎯 COMPONENT PLANNING (plan before deploy):"
	@echo "  plan-networking      Plan networking components"
	@echo "  plan-storage         Plan storage components"
	@echo "  plan-monitoring      Plan monitoring components"
	@echo "  plan-applications    Plan application components"
	@echo "  plan-dns             Plan DNS components"
	@echo "  plan-all-components  Plan all components individually"
	@echo ""
	@echo "🚀 COMPONENT DEPLOYMENT:"
	@echo "  apply-networking     Deploy networking components"
	@echo "  apply-storage        Deploy storage components"
	@echo "  apply-monitoring     Deploy monitoring components"
	@echo "  apply-applications   Deploy application components"
	@echo "  apply-dns            Deploy DNS components"
	@echo ""
	@echo "🔍 COMPONENT DEBUGGING:"
	@echo "  debug-networking     Debug networking components"
	@echo "  debug-storage        Debug storage components"
	@echo "  debug-monitoring     Debug monitoring components"
	@echo "  debug-applications   Debug application components"
	@echo "  debug-dns            Debug DNS components"
	@echo ""
	@echo "📊 COMPONENT STATUS:"
	@echo "  status-networking    Show networking component status"
	@echo "  status-storage       Show storage component status"
	@echo "  status-monitoring    Show monitoring component status"
	@echo "  status-applications  Show application component status"
	@echo "  status-dns           Show DNS component status"
	@echo "  status-all-components Show status for all components"
	@echo ""
	@echo "💡 EXAMPLES:"
	@echo "  make plan-storage && make apply-storage    # Deploy only Longhorn"
	@echo "  make debug-networking                      # Debug MetalLB issues"
	@echo "  make status-monitoring                     # Check Prometheus/Grafana"

init: ## Initialize Terraform
	terraform init

plan: check-vars check-init ## Plan Terraform deployment
	terraform plan

check-init: ## Check if Terraform is initialized
ifeq ($(OS),Windows_NT)
	@if not exist .terraform\providers (echo Error: Terraform not initialized. Run 'make init' first. && exit /b 1)
else
	@if [ ! -d ".terraform/providers" ]; then echo "Error: Terraform not initialized. Run 'make init' first."; exit 1; fi
endif

apply: check-vars check-init ## Apply Terraform configuration
	terraform apply

destroy: check-vars check-init ## Destroy Terraform infrastructure
	terraform destroy

force-clean: ## Force cleanup of all resources (use when destroy fails)
	@echo "🧹 Starting comprehensive cleanup..."
	@echo "Step 1: Setting Longhorn deletion flag..."
	@kubectl -n longhorn-system patch settings.longhorn.io deleting-confirmation-flag --type='merge' -p='{"value":"true"}' 2>/dev/null || echo "Longhorn settings not found, continuing..."
	@echo "Step 2: Cleaning up failed jobs..."
	@kubectl delete jobs -n longhorn-system longhorn-uninstall --ignore-not-found=true
	@echo "Step 3: Running terraform destroy..."
	@terraform destroy -auto-approve || echo "Terraform destroy completed with warnings"
	@echo "Step 4: Cleaning up leftover cluster resources..."
	@kubectl delete clusterrolebinding system:metrics-server metrics-server:system:auth-delegator --ignore-not-found=true
	@kubectl delete clusterrole system:metrics-server longhorn-role system:node-proxier --ignore-not-found=true
	@kubectl delete storageclass longhorn --ignore-not-found=true
	@kubectl delete priorityclass longhorn-critical --ignore-not-found=true
	@echo "Step 5: Force delete stuck namespaces..."
	@kubectl delete namespace longhorn-system monitoring baget --ignore-not-found=true --timeout=30s || echo "Namespace deletion timeout, continuing..."
	@echo "Step 6: Clean up any remaining kube-vip resources..."
	@kubectl delete configmap -n kube-system kubevip --ignore-not-found=true
	@echo "Step 7: Clean up metrics-server resources..."
	@kubectl delete deployment -n kube-system metrics-server --ignore-not-found=true
	@kubectl delete service -n kube-system metrics-server --ignore-not-found=true
	@kubectl delete serviceaccount -n kube-system metrics-server --ignore-not-found=true
	@echo "Step 8: Clean up Longhorn CRDs and webhooks..."
	@kubectl delete crd -l app.kubernetes.io/name=longhorn --ignore-not-found=true || echo "CRDs with label not found, trying individual deletion..."
	@kubectl delete crd backingimagedatasources.longhorn.io backingimagemanagers.longhorn.io backingimages.longhorn.io backupbackingimages.longhorn.io backups.longhorn.io backuptargets.longhorn.io backupvolumes.longhorn.io engineimages.longhorn.io engines.longhorn.io instancemanagers.longhorn.io nodes.longhorn.io orphans.longhorn.io recurringjobs.longhorn.io replicas.longhorn.io settings.longhorn.io sharemanagers.longhorn.io snapshots.longhorn.io supportbundles.longhorn.io systembackups.longhorn.io systemrestores.longhorn.io volumeattachments.longhorn.io volumes.longhorn.io --ignore-not-found=true
	@kubectl delete validatingwebhookconfigurations longhorn-webhook-validator --ignore-not-found=true
	@kubectl delete mutatingwebhookconfigurations longhorn-webhook-mutator --ignore-not-found=true
	@echo "Step 9: Clean up any remaining pods and controllers..."
	@kubectl delete pods -n longhorn-system --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No pods to delete"
	@kubectl delete daemonsets,deployments,replicasets -n longhorn-system --all --ignore-not-found=true 2>/dev/null || echo "No controllers to delete"
	@echo "Step 10: Force delete any stuck namespaces (final cleanup)..."
	@kubectl delete namespace longhorn-system monitoring baget --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "Namespaces already deleted or deletion completed"
	@echo "Step 11: Clean up any remaining Helm releases..."
	@helm uninstall longhorn -n longhorn-system --ignore-not-found 2>/dev/null || echo "No Helm releases to clean up"
	@echo "Step 12: Clean up Prometheus/monitoring CRDs..."
	@kubectl delete crd alertmanagerconfigs.monitoring.coreos.com --ignore-not-found=true
	@kubectl delete crd alertmanagers.monitoring.coreos.com --ignore-not-found=true
	@kubectl delete crd podmonitors.monitoring.coreos.com --ignore-not-found=true
	@kubectl delete crd probes.monitoring.coreos.com --ignore-not-found=true
	@kubectl delete crd prometheusagents.monitoring.coreos.com --ignore-not-found=true
	@kubectl delete crd prometheuses.monitoring.coreos.com --ignore-not-found=true
	@kubectl delete crd prometheusrules.monitoring.coreos.com --ignore-not-found=true
	@kubectl delete crd scrapeconfigs.monitoring.coreos.com --ignore-not-found=true
	@kubectl delete crd servicemonitors.monitoring.coreos.com --ignore-not-found=true
	@kubectl delete crd thanosrulers.monitoring.coreos.com --ignore-not-found=true
	@echo "Step 13: Clean up leftover Prometheus services..."
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-coredns --ignore-not-found=true
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kube-controller-manager --ignore-not-found=true
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kube-etcd --ignore-not-found=true
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kube-proxy --ignore-not-found=true
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kube-scheduler --ignore-not-found=true
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kubelet --ignore-not-found=true
	@echo "Step 14: Final verification..."
	@kubectl get pods -n longhorn-system --ignore-not-found=true 2>nul || echo "✓ longhorn-system namespace is clean"
	@kubectl get crd 2>nul | findstr /i "longhorn" >nul && echo "⚠ Some Longhorn CRDs still present" || echo "✓ Longhorn CRDs cleaned up"
	@kubectl get crd 2>nul | findstr /i "monitoring.coreos.com" >nul && echo "⚠ Some Prometheus CRDs still present" || echo "✓ Prometheus CRDs cleaned up"
	@echo "✅ Comprehensive cleanup completed!"

destroy-clean: force-clean ## Alias for force-clean

validate: ## Validate Terraform configuration
	terraform validate

format: ## Format Terraform files
	terraform fmt -recursive

lint: validate format ## Lint and validate Terraform code
	@echo "Terraform configuration is valid and formatted"

check-vars: ## Check if terraform.tfvars exists
ifeq ($(OS),Windows_NT)
	@if not exist terraform.tfvars ( \
		echo Error: terraform.tfvars not found! && \
		echo Please copy terraform.tfvars.example to terraform.tfvars and customize it. && \
		echo. && \
		echo   copy terraform.tfvars.example terraform.tfvars && \
		echo. && \
		exit /b 1 \
	)
else
	@if [ ! -f terraform.tfvars ]; then \
		echo "Error: terraform.tfvars not found!"; \
		echo "Please copy terraform.tfvars.example to terraform.tfvars and customize it."; \
		echo ""; \
		echo "  cp terraform.tfvars.example terraform.tfvars"; \
		echo ""; \
		exit 1; \
	fi
endif

status: ## Show current deployment status
	@echo "=== Terraform State Summary ==="
ifeq ($(OS),Windows_NT)
	@terraform state list >nul 2>&1 && echo "Terraform state found" || echo "No state found (not initialized)"
else
	@terraform state list 2>/dev/null | wc -l | xargs -I {} echo "Total resources: {}" || echo "No state found (not initialized)"
endif
	@echo ""
	@echo "=== Component Status Summary ==="
	@$(MAKE) --no-print-directory status-networking
	@echo ""
	@$(MAKE) --no-print-directory status-storage
	@echo ""
	@$(MAKE) --no-print-directory status-monitoring
	@echo ""
	@$(MAKE) --no-print-directory status-applications
	@echo ""
	@$(MAKE) --no-print-directory status-dns
	@echo ""
	@echo "=== LoadBalancer Services ==="
ifeq ($(OS),Windows_NT)
	@kubectl get services --all-namespaces 2>nul | findstr LoadBalancer || echo "No LoadBalancer services found"
else
	@kubectl get services --all-namespaces | grep LoadBalancer 2>/dev/null || echo "No LoadBalancer services found"
endif
	@echo ""
	@echo "Use 'make status-<component>' for detailed component status"

clean: ## Clean Terraform cache and state
ifeq ($(OS),Windows_NT)
	@if exist .terraform rmdir /s /q .terraform
	@if exist .terraform.lock.hcl del .terraform.lock.hcl
else
	rm -rf .terraform
	rm -f .terraform.lock.hcl
endif

# Deployment helpers
setup: ## Complete setup process (init, validate, plan)
	@echo "Setting up Terraform environment..."
	$(MAKE) init
	$(MAKE) validate
	$(MAKE) plan

deploy: ## Full deployment (setup + apply)
	@echo "Deploying infrastructure..."
	$(MAKE) setup
	$(MAKE) apply

# Generate secure credentials
generate-secrets: ## Generate secure passwords for terraform.tfvars
	@echo "Generating secure credentials..."
	@echo ""
	@echo "# Generated credentials - add to your terraform.tfvars file:"
	@echo "baget_api_key = \"$$(openssl rand -base64 32)\""
	@echo "grafana_admin_password = \"$$(openssl rand -base64 16)\""
	@echo ""
	@echo "Save these credentials securely!"

# Component Management
list-components: ## List all infrastructure components and their files
	@echo "Infrastructure Components:"
	@echo "========================="
	@echo "📦 Providers     -> providers.tf     (Terraform & provider config)"
	@echo "🏷️  Namespaces   -> namespaces.tf   (Kubernetes namespaces)"
	@echo "🌐 Networking    -> networking.tf    (MetalLB, Metrics Server)"
	@echo "💾 Storage       -> storage.tf       (Longhorn distributed storage)"
	@echo "📊 Monitoring    -> monitoring.tf    (Prometheus, Grafana, AlertManager)"
	@echo "🚀 Applications  -> applications.tf  (Baget NuGet server)"
	@echo "🔍 DNS           -> dns.tf           (Pi-hole DNS sync)"
	@echo ""
	@echo "Use 'make plan-<component>' or 'make apply-<component>' for targeted operations"

# Component-specific Planning
plan-networking: check-vars check-init ## Plan networking components (MetalLB, Metrics Server)
	@echo "Planning networking components..."
	terraform plan \
		-target=helm_release.metallb \
		-target=kubernetes_manifest.metallb_ipaddresspool \
		-target=kubernetes_manifest.metallb_bfd_profile \
		-target=kubernetes_manifest.metallb_bgp_peer \
		-target=kubernetes_manifest.metallb_bgp_advertisement \
		-target=helm_release.metrics_server

plan-storage: check-vars check-init ## Plan storage components (Longhorn)
	@echo "Planning storage components..."
	terraform plan \
		-target=helm_release.longhorn \
		-target=kubernetes_storage_class.longhorn \
		-target=kubernetes_service.longhorn_frontend_lb

plan-monitoring: check-vars check-init ## Plan monitoring components (Prometheus, Grafana)
	@echo "Planning monitoring components..."
	terraform plan \
		-target=helm_release.prometheus_stack

plan-applications: check-vars check-init ## Plan application components (Baget)
	@echo "Planning application components..."
	terraform plan \
		-target=kubernetes_secret.baget_secrets \
		-target=kubernetes_config_map.baget_config \
		-target=kubernetes_persistent_volume_claim.baget_data \
		-target=kubernetes_deployment.baget \
		-target=kubernetes_service.baget

plan-dns: check-vars check-init ## Plan DNS components (Pi-hole sync)
	@echo "Planning DNS components..."
	terraform plan \
		-target=kubernetes_service_account.pihole_dns_sync \
		-target=kubernetes_cluster_role.pihole_dns_sync \
		-target=kubernetes_cluster_role_binding.pihole_dns_sync \
		-target=kubernetes_config_map.pihole_sync_script \
		-target=kubernetes_secret.pihole_credentials \
		-target=kubernetes_deployment.pihole_dns_sync \
		-target=kubernetes_service.pihole_dns_sync

# Component-specific Deployment
apply-networking: check-vars check-init ## Deploy networking components (MetalLB, Metrics Server)
	@echo "Deploying networking components..."
	terraform apply \
		-target=helm_release.metallb \
		-target=kubernetes_manifest.metallb_ipaddresspool \
		-target=kubernetes_manifest.metallb_bfd_profile \
		-target=kubernetes_manifest.metallb_bgp_peer \
		-target=kubernetes_manifest.metallb_bgp_advertisement \
		-target=helm_release.metrics_server

apply-storage: check-vars check-init ## Deploy storage components (Longhorn)
	@echo "Deploying storage components..."
	terraform apply \
		-target=helm_release.longhorn \
		-target=kubernetes_storage_class.longhorn \
		-target=kubernetes_service.longhorn_frontend_lb

apply-monitoring: check-vars check-init ## Deploy monitoring components (Prometheus, Grafana)
	@echo "Deploying monitoring components..."
	terraform apply \
		-target=helm_release.prometheus_stack

apply-applications: check-vars check-init ## Deploy application components (Baget)
	@echo "Deploying application components..."
	terraform apply \
		-target=kubernetes_secret.baget_secrets \
		-target=kubernetes_config_map.baget_config \
		-target=kubernetes_persistent_volume_claim.baget_data \
		-target=kubernetes_deployment.baget \
		-target=kubernetes_service.baget

apply-dns: check-vars check-init ## Deploy DNS components (Pi-hole sync)
	@echo "Deploying DNS components..."
	terraform apply \
		-target=kubernetes_service_account.pihole_dns_sync \
		-target=kubernetes_cluster_role.pihole_dns_sync \
		-target=kubernetes_cluster_role_binding.pihole_dns_sync \
		-target=kubernetes_config_map.pihole_sync_script \
		-target=kubernetes_secret.pihole_credentials \
		-target=kubernetes_deployment.pihole_dns_sync \
		-target=kubernetes_service.pihole_dns_sync

# Kubernetes helpers
k8s-status: ## Show Kubernetes cluster status
	@echo "=== Cluster Info ==="
	kubectl cluster-info
	@echo ""
	@echo "=== Node Status ==="
	kubectl get nodes -o wide
	@echo ""
	@echo "=== All Namespaces ==="
	kubectl get namespaces
	@echo ""
	@echo "=== All Pods ==="
	kubectl get pods --all-namespaces -o wide

# Component-specific Debugging
debug-networking: ## Debug networking components (MetalLB, Metrics Server)
	@echo "=== Networking Component Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep -E "(metallb|metrics_server)" || echo "No networking resources found in state"
	@echo ""
	@echo "MetalLB Pods:"
	@kubectl get pods -n metallb-system -o wide 2>/dev/null || echo "MetalLB namespace not found"
	@echo ""
	@echo "MetalLB Configuration:"
	@kubectl get bgppeers,ipaddresspools,bgpadvertisements -n metallb-system 2>/dev/null || echo "MetalLB CRDs not found"
	@echo ""
	@echo "Metrics Server Pods:"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server 2>/dev/null || echo "Metrics Server not found"

debug-storage: ## Debug storage components (Longhorn)
	@echo "=== Storage Component Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep longhorn || echo "No storage resources found in state"
	@echo ""
	@echo "Longhorn Pods:"
	@kubectl get pods -n longhorn-system -o wide 2>/dev/null || echo "Longhorn namespace not found"
	@echo ""
	@echo "Storage Classes:"
	@kubectl get storageclass 2>/dev/null || echo "No storage classes found"
	@echo ""
	@echo "Persistent Volumes:"
	@kubectl get pv,pvc --all-namespaces 2>/dev/null || echo "No persistent volumes found"

debug-monitoring: ## Debug monitoring components (Prometheus, Grafana)
	@echo "=== Monitoring Component Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep prometheus || echo "No monitoring resources found in state"
	@echo ""
	@echo "Monitoring Pods:"
	@kubectl get pods -n monitoring -o wide 2>/dev/null || echo "Monitoring namespace not found"
	@echo ""
	@echo "Services:"
	@kubectl get svc -n monitoring 2>/dev/null || echo "No monitoring services found"
	@echo ""
	@echo "ServiceMonitors:"
	@kubectl get servicemonitors -A 2>/dev/null || echo "No ServiceMonitors found"

debug-applications: ## Debug application components (Baget)
	@echo "=== Applications Component Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep baget || echo "No application resources found in state"
	@echo ""
	@echo "Application Pods:"
	@kubectl get pods -n baget -o wide 2>/dev/null || echo "Baget namespace not found"
	@echo ""
	@echo "Application Services:"
	@kubectl get svc -n baget 2>/dev/null || echo "No Baget services found"
	@echo ""
	@echo "Application Storage:"
	@kubectl get pvc -n baget 2>/dev/null || echo "No Baget storage found"

debug-dns: ## Debug DNS components (Pi-hole sync)
	@echo "=== DNS Component Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep pihole || echo "No DNS resources found in state"
	@echo ""
	@echo "Pi-hole Sync Pods:"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=pihole-dns-sync -o wide 2>/dev/null || echo "Pi-hole sync not found"
	@echo ""
	@echo "Pi-hole Sync Logs (last 20 lines):"
	@kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync --tail=20 2>/dev/null || echo "No Pi-hole sync logs found"

# Component-specific Status
status-networking: ## Show networking component status
	@echo "=== Networking Status ==="
ifeq ($(OS),Windows_NT)
	@kubectl get pods -n metallb-system 2>nul || echo "MetalLB not deployed"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server 2>nul || echo "Metrics Server not deployed"
	@kubectl get bgppeers,ipaddresspools -n metallb-system 2>nul || echo "MetalLB config not found"
else
	@kubectl get pods -n metallb-system 2>/dev/null || echo "MetalLB not deployed"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server 2>/dev/null || echo "Metrics Server not deployed"
	@kubectl get bgppeers,ipaddresspools -n metallb-system 2>/dev/null || echo "MetalLB config not found"
endif

status-storage: ## Show storage component status
	@echo "=== Storage Status ==="
ifeq ($(OS),Windows_NT)
	@kubectl get pods -n longhorn-system 2>nul || echo "Longhorn not deployed"
	@kubectl get storageclass longhorn 2>nul || echo "Longhorn StorageClass not found"
	@kubectl get svc -n longhorn-system longhorn-frontend-lb 2>nul || echo "Longhorn UI service not found"
else
	@kubectl get pods -n longhorn-system 2>/dev/null || echo "Longhorn not deployed"
	@kubectl get storageclass longhorn 2>/dev/null || echo "Longhorn StorageClass not found"
	@kubectl get svc -n longhorn-system longhorn-frontend-lb 2>/dev/null || echo "Longhorn UI service not found"
endif

status-monitoring: ## Show monitoring component status
	@echo "=== Monitoring Status ==="
ifeq ($(OS),Windows_NT)
	@kubectl get pods -n monitoring 2>nul || echo "Monitoring not deployed"
	@kubectl get svc -n monitoring 2>nul | findstr LoadBalancer || echo "No monitoring LoadBalancer services found"
else
	@kubectl get pods -n monitoring 2>/dev/null || echo "Monitoring not deployed"
	@kubectl get svc -n monitoring | grep LoadBalancer 2>/dev/null || echo "No monitoring LoadBalancer services found"
endif

status-applications: ## Show application component status
	@echo "=== Applications Status ==="
ifeq ($(OS),Windows_NT)
	@kubectl get pods -n baget 2>nul || echo "Baget not deployed"
	@kubectl get svc -n baget baget-service 2>nul || echo "Baget service not found"
else
	@kubectl get pods -n baget 2>/dev/null || echo "Baget not deployed"
	@kubectl get svc -n baget baget-service 2>/dev/null || echo "Baget service not found"
endif

status-dns: ## Show DNS component status
	@echo "=== DNS Status ==="
ifeq ($(OS),Windows_NT)
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=pihole-dns-sync 2>nul || echo "Pi-hole sync not deployed"
	@echo "Recent Pi-hole sync activity:"
	@kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync --tail=5 2>nul || echo "No recent activity"
else
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=pihole-dns-sync 2>/dev/null || echo "Pi-hole sync not deployed"
	@echo "Recent Pi-hole sync activity:"
	@kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync --tail=5 2>/dev/null || echo "No recent activity"
endif

logs: ## Show logs for all deployed applications
	@echo "=== All Component Logs ==="
	@echo "MetalLB Logs:"
	@kubectl logs -n metallb-system -l app=metallb --tail=5 2>/dev/null || echo "No MetalLB logs"
	@echo ""
	@echo "Longhorn Logs:"
	@kubectl logs -n longhorn-system -l app=longhorn-manager --tail=5 2>/dev/null || echo "No Longhorn logs"
	@echo ""
	@echo "Prometheus Logs:"
	@kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=5 2>/dev/null || echo "No Prometheus logs"
	@echo ""
	@echo "Grafana Logs:"
	@kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=5 2>/dev/null || echo "No Grafana logs"
	@echo ""
	@echo "Baget Logs:"
	@kubectl logs -n baget -l app=baget --tail=5 2>/dev/null || echo "No Baget logs"
	@echo ""
	@echo "Pi-hole Sync Logs:"
	@kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync --tail=5 2>/dev/null || echo "No Pi-hole sync logs"
	@echo ""
	@echo "Use 'make debug-<component>' for detailed component debugging"

# BGP helpers
bgp-status: ## Check BGP configuration status
	@echo "=== MetalLB BGP Configuration ==="
	kubectl get bgppeers -n metallb-system -o wide 2>/dev/null || echo "No BGP peers found"
	kubectl get ipaddresspools -n metallb-system -o wide 2>/dev/null || echo "No IP address pools found"
	kubectl get bgpadvertisements -n metallb-system -o wide 2>/dev/null || echo "No BGP advertisements found"
	@echo ""
	@echo "=== Router BGP Config Reminder ==="
	@echo "Make sure your router (UDM Pro) has this BGP configuration:"
	@echo ""
	@echo "configure"
	@echo "set protocols bgp 65001 parameters router-id 192.168.0.1"
	@echo "set protocols bgp 65001 neighbor 192.168.0.0/24 peer-group K8S-PEERS"
	@echo "set protocols bgp 65001 neighbor 192.168.0.0/24 remote-as 65002"
	@echo "commit"
	@echo "save"

# Workflow Shortcuts
deploy-core: ## Deploy core infrastructure (networking + storage)
	@echo "Deploying core infrastructure (networking + storage)..."
	$(MAKE) apply-networking
	$(MAKE) apply-storage

deploy-apps: ## Deploy applications (monitoring + apps + dns)
	@echo "Deploying applications (monitoring + apps + dns)..."
	$(MAKE) apply-monitoring
	$(MAKE) apply-applications
	$(MAKE) apply-dns

plan-all-components: ## Plan all components individually
	@echo "Planning all components..."
	$(MAKE) plan-networking
	$(MAKE) plan-storage
	$(MAKE) plan-monitoring
	$(MAKE) plan-applications
	$(MAKE) plan-dns

status-all-components: ## Show status for all components
	@echo "Checking all component status..."
	$(MAKE) status-networking
	$(MAKE) status-storage
	$(MAKE) status-monitoring
	$(MAKE) status-applications
	$(MAKE) status-dns

show-structure: ## Show the modular file structure
	@echo "Terraform Modular File Structure:"
	@echo "================================="
	@echo ""
	@ls -la *.tf 2>/dev/null | awk '{print $$9, "(" $$5 " bytes)"}' | grep -v "^(" || echo "No .tf files found"
	@echo ""
	@echo "File Purposes:"
	@echo "-------------"
	@echo "providers.tf     - Terraform and provider configurations"
	@echo "variables.tf     - All variable definitions"
	@echo "outputs.tf       - All output definitions"
	@echo "namespaces.tf    - Kubernetes namespace resources"
	@echo "networking.tf    - MetalLB load balancer and metrics server"
	@echo "storage.tf       - Longhorn distributed storage"
	@echo "monitoring.tf    - Prometheus, Grafana, and AlertManager"
	@echo "applications.tf  - Application deployments (Baget)"
	@echo "dns.tf          - Pi-hole DNS sync for automatic service discovery"
	@echo ""
	@echo "Use 'make list-components' to see what each file contains"

quick-debug: ## Quick debug of all components
	@echo "=== Quick Debug Overview ==="
	@echo "Terraform Resources:"
	@terraform state list 2>/dev/null | wc -l | xargs -I {} echo "  Total: {}" || echo "  No state found"
	@echo ""
	@echo "Kubernetes Resources:"
	@kubectl get pods --all-namespaces --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  Total Pods: {}" || echo "  Cannot connect to cluster"
	@kubectl get svc --all-namespaces --no-headers | grep LoadBalancer 2>/dev/null | wc -l | xargs -I {} echo "  LoadBalancer Services: {}" || echo "  No LoadBalancer services"
	@echo ""
	@echo "Component Health:"
	@kubectl get pods -n metallb-system --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  MetalLB: {} pods running" || echo "  MetalLB: Not deployed"
	@kubectl get pods -n longhorn-system --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Longhorn: {} pods running" || echo "  Longhorn: Not deployed"
	@kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Monitoring: {} pods running" || echo "  Monitoring: Not deployed"
	@kubectl get pods -n baget --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Baget: {} pods running" || echo "  Baget: Not deployed"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=pihole-dns-sync --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Pi-hole Sync: {} pods running" || echo "  Pi-hole Sync: Not deployed"
	@echo ""
	@echo "Use 'make debug-<component>' for detailed debugging"

# Advanced workflows
taint-component: ## Taint a component for recreation (usage: make taint-component COMPONENT=storage)
ifndef COMPONENT
	@echo "Error: COMPONENT variable required"
	@echo "Usage: make taint-component COMPONENT=<networking|storage|monitoring|applications|dns>"
	@echo "Example: make taint-component COMPONENT=storage"
	@exit 1
endif
	@echo "Tainting $(COMPONENT) component for recreation..."
	@case "$(COMPONENT)" in \
		networking) terraform taint helm_release.metallb ;; \
		storage) terraform taint helm_release.longhorn ;; \
		monitoring) terraform taint helm_release.prometheus_stack ;; \
		applications) terraform taint kubernetes_deployment.baget ;; \
		dns) terraform taint kubernetes_deployment.pihole_dns_sync ;; \
		*) echo "Invalid component: $(COMPONENT)" && exit 1 ;; \
	esac
	@echo "Component $(COMPONENT) tainted. Run 'make apply-$(COMPONENT)' to recreate."
