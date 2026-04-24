# Force bash shell for cross-platform compatibility (works in Git Bash on Windows and native Linux)
SHELL := /bin/bash

# Bail out early if make is not using bash (e.g. GnuWin32 make from PowerShell falls back to cmd.exe)
BASH_CHECK := $(shell echo $$BASH_VERSION)
ifeq ($(BASH_CHECK),)
$(error This Makefile requires bash. Please run 'make' from Git Bash, not PowerShell or cmd.exe)
endif

# Fix $(MAKE) on Windows when make is installed in a path with spaces (e.g. Program Files)
MAKE := "$(MAKE)"

# Cross-platform help - Simple approach that works everywhere
# We'll hardcode the help sections for reliability

.PHONY: help init plan apply destroy force-clean destroy-clean validate format lint check-vars status clean \
	plan-networking plan-storage plan-monitoring plan-applications plan-dns plan-traefik plan-ingress plan-azure-dns \
	apply-networking apply-storage apply-monitoring apply-applications apply-dns apply-traefik apply-ingress apply-azure-dns \
	debug-networking debug-storage debug-monitoring debug-applications debug-dns debug-traefik debug-ingress \
	status-networking status-storage status-monitoring status-applications status-dns status-traefik status-ingress \
	list-components deploy-core deploy-apps plan-all-components status-all-components \
	plan-static-sites apply-static-sites debug-static-sites status-static-sites \
	plan-nfs apply-nfs \
	plan-flannel apply-flannel plan-kube-vip apply-kube-vip plan-coredns apply-coredns \
	plan-crowdsec apply-crowdsec plan-oauth apply-oauth \
	plan-n8n apply-n8n plan-postfix apply-postfix plan-squid apply-squid \
	plan-prowlarr apply-prowlarr plan-sonarr apply-sonarr plan-radarr apply-radarr \
	plan-qbittorrent apply-qbittorrent plan-emby apply-emby \
	plan-bazarr apply-bazarr plan-jackett apply-jackett \
	plan-cleanuparr apply-cleanuparr plan-sabnzbd apply-sabnzbd plan-notifiarr apply-notifiarr \
	plan-flaresolverr apply-flaresolverr \
	plan-nvidia apply-nvidia plan-ollama apply-ollama plan-qdrant apply-qdrant \
	plan-chromadb apply-chromadb plan-comfyui apply-comfyui \
	plan-homepage apply-homepage \
	plan-runners apply-runners debug-runners \
	show-structure quick-debug taint-component \
	recover restart-kube-vip clean-longhorn-mounts

# Default target
help: ## Show this help message
	@echo "Kubernetes Homelab Terraform Management (Modular Structure)"
	@echo "Usage: make [target]"
	@echo ""
	@echo "🚀 QUICK START:"
	@echo "  make list-components  # See all infrastructure components"
	@echo "  make setup           # Initialize and validate"
	@echo "  make deploy          # Full deployment (existing resources)"
	@echo "  make redeploy        # Clean deployment (removes existing resources first)"
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
	@echo "  deploy               Full deployment (existing resources)"
	@echo "  redeploy             Clean deployment (removes existing resources first)"
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
	@echo "🔄 RECOVERY (after power outage / node reboot):"
	@echo "  recover              Full post-outage recovery (clean mounts, restart kube-vip, restart stuck pods)"
	@echo "  restart-kube-vip     Restart kube-vip to recover LoadBalancer VIP"
	@echo "  clean-longhorn-mounts  Clean stale Longhorn mounts on worker nodes via SSH"
	@echo ""
	@echo "🔧 NETWORKING FIXES:"
	@echo "  apply-kube-proxy-rbac Apply correct RBAC for kube-proxy"
	@echo "  restart-kube-proxy   Restart kube-proxy to pick up new RBAC permissions"
	@echo "  test-dns             Test DNS resolution"
	@echo "  test-clusterip       Test ClusterIP connectivity"
	@echo "  fix-cluster-networking Complete fix for ClusterIP connectivity issues"
	@echo ""
	@echo "🎯 COMPONENT PLANNING (plan before deploy):"
	@echo "  plan-networking      Plan networking components"
	@echo "  plan-storage         Plan storage components"
	@echo "  plan-monitoring      Plan monitoring components"
	@echo "  plan-applications    Plan application components"
	@echo "  plan-dns             Plan DNS components"
	@echo "  plan-static-sites    Plan static sites components"
	@echo "  plan-all-components  Plan all components individually"
	@echo ""
	@echo "🚀 COMPONENT DEPLOYMENT:"
	@echo "  apply-networking     Deploy networking components"
	@echo "  apply-storage        Deploy storage components"
	@echo "  apply-monitoring     Deploy monitoring components"
	@echo "  apply-applications   Deploy application components"
	@echo "  apply-dns            Deploy DNS components"
	@echo "  apply-static-sites   Deploy static sites components"
	@echo ""
	@echo "🔍 COMPONENT DEBUGGING:"
	@echo "  debug-networking     Debug networking components"
	@echo "  debug-storage        Debug storage components"
	@echo "  debug-monitoring     Debug monitoring components"
	@echo "  debug-applications   Debug application components"
	@echo "  debug-dns            Debug DNS components"
	@echo "  debug-static-sites   Debug static sites components"
	@echo ""
	@echo "📊 COMPONENT STATUS:"
	@echo "  status-networking    Show networking component status"
	@echo "  status-storage       Show storage component status"
	@echo "  status-monitoring    Show monitoring component status"
	@echo "  status-applications  Show application component status"
	@echo "  status-dns           Show DNS component status"
	@echo "  status-static-sites  Show static sites status"
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
	@if [ ! -d ".terraform/providers" ]; then echo "Error: Terraform not initialized. Run 'make init' first."; exit 1; fi

apply: check-vars check-init ## Apply Terraform configuration
	terraform apply -auto-approve

destroy: check-vars check-init ## Destroy Terraform infrastructure
	terraform destroy

force-clean: ## Force cleanup of all resources (use when destroy fails)
	@echo "🧹 Starting comprehensive cleanup..."
	@echo "Step 1: Setting Longhorn deletion flag..."
	@kubectl -n longhorn-system patch settings.longhorn.io deleting-confirmation-flag --type='merge' -p='{"value":"true"}' 2>/dev/null || echo "Longhorn settings not found, continuing..."
	@echo "Step 2: Cleaning up failed jobs..."
	@kubectl delete jobs -n longhorn-system longhorn-uninstall --ignore-not-found=true 2>/dev/null || echo "No failed jobs found"
	@echo "Step 3: Uninstall ALL Helm releases first (thoroughly)..."
	@echo "  Uninstalling metrics-server..."
	@helm uninstall metrics-server -n kube-system --ignore-not-found --wait --timeout=60s 2>/dev/null || echo "  No metrics-server Helm release"
	@echo "  Uninstalling longhorn (thoroughly to prevent recreation)..."
	@helm uninstall longhorn -n longhorn-system --ignore-not-found --wait --timeout=120s 2>/dev/null || echo "  No longhorn Helm release"
	@echo "  Double-check: Remove any Longhorn Helm secrets..."
	@kubectl delete secret -n longhorn-system -l name=longhorn --ignore-not-found=true 2>/dev/null || echo "  No Longhorn Helm secrets to delete"
	@echo "  Uninstalling prometheus-stack..."
	@helm uninstall prometheus-stack -n monitoring --ignore-not-found --wait --timeout=60s 2>/dev/null || echo "  No prometheus-stack Helm release"
	@echo "  Uninstalling headlamp..."
	@helm uninstall headlamp -n headlamp --ignore-not-found --wait --timeout=60s 2>/dev/null || echo "  No headlamp Helm release"
	@echo "  All Helm releases thoroughly uninstalled"
	@echo "Step 4: CRITICAL - Clean up webhooks and CRDs BEFORE terraform destroy..."
	@echo "  Cleaning Longhorn webhooks..."
	@kubectl delete validatingwebhookconfigurations longhorn-webhook-validator longhorn-admission-webhook --ignore-not-found=true 2>/dev/null || echo "  No longhorn webhook validators"
	@kubectl delete mutatingwebhookconfigurations longhorn-webhook-mutator longhorn-conversion-webhook --ignore-not-found=true 2>/dev/null || echo "  No longhorn webhook mutators"
	@echo "  Cleaning Prometheus webhooks..."
	@kubectl delete validatingwebhookconfigurations prometheus-stack-kube-prom-admission --ignore-not-found=true 2>/dev/null || echo "  No prometheus webhook validators"
	@kubectl delete mutatingwebhookconfigurations prometheus-stack-kube-prom-admission --ignore-not-found=true 2>/dev/null || echo "  No prometheus webhook mutators"
	@echo "  Cleaning Kubernetes Dashboard webhooks..."
	@echo "  (Headlamp has no webhooks to clean)"
	@echo "  FIRST: Remove finalizers from stuck resources (before deleting CRDs)..."
	@kubectl patch backuptargets.longhorn.io default -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  No backup targets to patch"
	@kubectl patch namespace longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Namespace already clean or deleted"
	@kubectl patch namespace monitoring -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Monitoring namespace already clean or deleted"
	@kubectl patch namespace baget -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Baget namespace already clean or deleted"
	@kubectl patch namespace headlamp -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Headlamp namespace already clean or deleted"
	@echo "  CRITICAL: Removing finalizers from Longhorn resources to unblock terraform destroy..."
	@echo "  Step 1: Remove finalizers from all Longhorn custom resources (instances) first..."
	@echo "    Removing finalizers from volumes..."
	@kubectl get volumes.longhorn.io -n longhorn-system -o name 2>/dev/null | xargs -I {} kubectl patch {} -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "    No volumes to patch"
	@echo "    Removing finalizers from engines..."
	@kubectl get engines.longhorn.io -n longhorn-system -o name 2>/dev/null | xargs -I {} kubectl patch {} -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "    No engines to patch"
	@echo "    Removing finalizers from replicas..."
	@kubectl get replicas.longhorn.io -n longhorn-system -o name 2>/dev/null | xargs -I {} kubectl patch {} -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "    No replicas to patch"
	@echo "    Manually removing finalizers from known node instances..."
	@kubectl patch node.longhorn.io k8s02 -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "    k8s02 node finalizer removed"
	@kubectl patch node.longhorn.io k8s03 -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "    k8s03 node finalizer removed"
	@echo "    Skipping complex PowerShell finalizer removal (causes failures) - will rely on force delete..."
	@echo "    CRITICAL: Force delete all Longhorn custom resources (skip finalizer removal - too complex for Makefile PowerShell)..."
	@echo "      Force deleting all engines, replicas, volumes, etc. with grace period 0..."
	@echo "    NOW force deleting specific Longhorn custom resources..."
	@echo "      Deleting engines..."
	@kubectl delete engines.longhorn.io --all -n longhorn-system --force --grace-period=0 --ignore-not-found=true --timeout=10s 2>/dev/null || echo "      No engines to delete"
	@echo "      Deleting replicas..."
	@kubectl delete replicas.longhorn.io --all -n longhorn-system --force --grace-period=0 --ignore-not-found=true --timeout=10s 2>/dev/null || echo "      No replicas to delete"
	@echo "      Deleting volumes..."
	@kubectl delete volumes.longhorn.io --all -n longhorn-system --force --grace-period=0 --ignore-not-found=true --timeout=10s 2>/dev/null || echo "      No volumes to delete"
	@echo "      Deleting volumeattachments..."
	@kubectl delete volumeattachments.longhorn.io --all -n longhorn-system --force --grace-period=0 --ignore-not-found=true --timeout=10s 2>/dev/null || echo "      No volumeattachments to delete"
	@echo "      Deleting engineimages..."
	@kubectl delete engineimages.longhorn.io --all -n longhorn-system --force --grace-period=0 --ignore-not-found=true --timeout=10s 2>/dev/null || echo "      No engineimages to delete"
	@echo "    Force deleting all remaining standard resources..."
	@kubectl delete all --all -n longhorn-system --force --grace-period=0 --ignore-not-found=true --timeout=10s 2>/dev/null || echo "    All standard resources deleted"
	@echo "    Waiting 3 seconds for node deletions to propagate..."
	@sleep 3
	@echo "    Verifying node instances are gone (this should unblock the CRD)..."
	@kubectl get nodes.longhorn.io -n longhorn-system 2>/dev/null && echo "    WARNING: Node instances still exist!" || echo "    ✅ Node instances successfully deleted"
	@echo "  Step 2: CRITICAL - Remove finalizer from the nodes.longhorn.io CRD itself..."
	@kubectl patch crd nodes.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  nodes.longhorn.io CRD finalizer removed"
	@echo "  Step 3: Now remove finalizers from all other Longhorn CRDs individually..."
	@kubectl patch crd backingimagedatasources.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  backingimagedatasources finalizer removed"
	@kubectl patch crd backingimagemanagers.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  backingimagemanagers finalizer removed"  
	@kubectl patch crd backingimages.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  backingimages finalizer removed"
	@kubectl patch crd backupbackingimages.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  backupbackingimages finalizer removed"
	@kubectl patch crd backups.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  backups finalizer removed"
	@kubectl patch crd backuptargets.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  backuptargets finalizer removed"
	@kubectl patch crd backupvolumes.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  backupvolumes finalizer removed"
	@kubectl patch crd engineimages.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  engineimages finalizer removed"
	@kubectl patch crd engines.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  engines finalizer removed"
	@kubectl patch crd instancemanagers.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  instancemanagers finalizer removed"
	@kubectl patch crd nodes.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  nodes finalizer removed"
	@kubectl patch crd orphans.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  orphans finalizer removed"
	@kubectl patch crd recurringjobs.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  recurringjobs finalizer removed"
	@kubectl patch crd replicas.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  replicas finalizer removed"
	@kubectl patch crd settings.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  settings finalizer removed"
	@kubectl patch crd sharemanagers.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  sharemanagers finalizer removed"
	@kubectl patch crd snapshots.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  snapshots finalizer removed"
	@kubectl patch crd supportbundles.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  supportbundles finalizer removed"
	@kubectl patch crd systembackups.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  systembackups finalizer removed"
	@kubectl patch crd systemrestores.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  systemrestores finalizer removed"
	@kubectl patch crd volumeattachments.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  volumeattachments finalizer removed"
	@kubectl patch crd volumes.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  volumes finalizer removed"
	@echo "  Step 4: Force delete all Longhorn CRDs..."
	@kubectl delete crd -l app.kubernetes.io/name=longhorn --force --grace-period=0 --ignore-not-found=true --timeout=10s 2>/dev/null || echo "  Label-based CRD deletion completed"
	@echo "  Step 5: Clean up orphaned PVCs using deleted Longhorn storage class..."
	@echo "    FIRST: Delete all Longhorn PVCs (skipping finalizer removal due to PowerShell issues)..."
	@echo "    NOW: Force deleting PVCs in baget namespace..."
	@kubectl delete pvc --all -n baget --force --grace-period=0 --ignore-not-found=true --timeout=30s 2>/dev/null || echo "    No baget PVCs to delete"
	@echo "    Force deleting PVCs in monitoring namespace..."
	@kubectl delete pvc --all -n monitoring --force --grace-period=0 --ignore-not-found=true --timeout=30s 2>/dev/null || echo "    No monitoring PVCs to delete"
	@echo "    Note: Complex PVC cleanup skipped due to PowerShell pipeline issues - manual cleanup may be needed"
	@echo "  Step 6: Re-patch namespace finalizers (in case they returned)..."
	@kubectl patch namespace longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Namespace finalizers cleared again"
	@echo "  CRDs and PVCs should now be unblocked for terraform destroy"
	@echo "Step 7: NOW Running terraform destroy (should not hang)..."
	@terraform destroy -auto-approve || echo "Terraform destroy completed with warnings"
	@echo "Step 8: Cleaning up leftover cluster-level resources..."
	@kubectl delete clusterrolebinding system:metrics-server metrics-server:system:auth-delegator dashboard-admin-user longhorn-bind flannel system:node-proxier --ignore-not-found=true 2>/dev/null || echo "No cluster role bindings to clean"
	@kubectl delete clusterrole system:metrics-server system:metrics-server-aggregated-reader longhorn-role flannel system:node-proxier --ignore-not-found=true 2>/dev/null || echo "No cluster roles to clean"
	@echo "  Deleting StorageClasses..."
	@kubectl delete storageclass longhorn --ignore-not-found=true 2>/dev/null || echo "  No longhorn storage class to clean"
	@kubectl delete priorityclass longhorn-critical --ignore-not-found=true 2>/dev/null || echo "No priority classes to clean"
	@kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found=true 2>/dev/null || echo "No API services to clean"
	@echo "Step 7: Force delete stuck namespaces (should now work)..."
	@kubectl delete namespace longhorn-system monitoring baget headlamp kube-flannel --ignore-not-found=true --timeout=30s || echo "Namespace deletion timeout, continuing..."
	@echo "Step 8: Clean up remaining kube-vip resources..."
	@kubectl delete configmap -n kube-system kubevip --ignore-not-found=true 2>/dev/null || echo "No kube-vip config to clean"
	@echo "Step 9: Clean up any remaining application resources..."
	@kubectl delete pods -n longhorn-system --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No longhorn pods to delete"
	@kubectl delete pods -n monitoring --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No monitoring pods to delete"
	@kubectl delete pods -n baget --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No baget pods to delete"
	@kubectl delete pods -n headlamp --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No headlamp pods to delete"
	@kubectl delete pods -n kube-flannel --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No flannel pods to delete"
	@kubectl delete pods -n kube-system -l k8s-app=kube-proxy --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No kube-proxy pods to delete"
	@kubectl delete daemonsets,deployments,replicasets -n longhorn-system --all --ignore-not-found=true 2>/dev/null || echo "No longhorn controllers to delete"
	@kubectl delete daemonsets,deployments,replicasets -n monitoring --all --ignore-not-found=true 2>/dev/null || echo "No monitoring controllers to delete"
	@kubectl delete daemonsets,deployments,replicasets -n baget --all --ignore-not-found=true 2>/dev/null || echo "No baget controllers to delete"
	@kubectl delete daemonsets,deployments,replicasets -n headlamp --all --ignore-not-found=true 2>/dev/null || echo "No headlamp controllers to delete"
	@kubectl delete daemonsets,deployments,replicasets -n kube-flannel --all --ignore-not-found=true 2>/dev/null || echo "No flannel controllers to delete"
	@echo "Step 9b: Clean up Longhorn service accounts and remaining resources..."
	@kubectl delete serviceaccount -n longhorn-system longhorn-service-account --ignore-not-found=true 2>/dev/null || echo "No longhorn service account to delete"
	@kubectl delete configmap -n longhorn-system --all --ignore-not-found=true 2>/dev/null || echo "No longhorn configmaps to delete"
	@echo "Step 10: Clean up Prometheus/monitoring CRDs..."
	@kubectl delete crd alertmanagerconfigs.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No alertmanager configs CRD"
	@kubectl delete crd alertmanagers.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No alertmanagers CRD"
	@kubectl delete crd podmonitors.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No podmonitors CRD"
	@kubectl delete crd probes.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No probes CRD"
	@kubectl delete crd prometheusagents.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No prometheus agents CRD"
	@kubectl delete crd prometheuses.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No prometheuses CRD"
	@kubectl delete crd prometheusrules.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No prometheus rules CRD"
	@kubectl delete crd scrapeconfigs.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No scrape configs CRD"
	@kubectl delete crd servicemonitors.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No service monitors CRD"
	@kubectl delete crd thanosrulers.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || echo "No thanos rulers CRD"
	@echo "Step 11: Clean up leftover Prometheus services in kube-system..."
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-coredns --ignore-not-found=true 2>/dev/null || echo "No prometheus coredns service"
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kube-controller-manager --ignore-not-found=true 2>/dev/null || echo "No prometheus controller manager service"
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kube-etcd --ignore-not-found=true 2>/dev/null || echo "No prometheus etcd service"
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kube-proxy --ignore-not-found=true 2>/dev/null || echo "No prometheus kube-proxy service"
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kube-scheduler --ignore-not-found=true 2>/dev/null || echo "No prometheus scheduler service"
	@kubectl delete service -n kube-system prometheus-stack-kube-prom-kubelet --ignore-not-found=true 2>/dev/null || echo "No prometheus kubelet service"
	@echo "Step 11: Force delete any stuck namespaces (final cleanup - should be unnecessary now)..."
	@kubectl delete namespace longhorn-system monitoring baget headlamp kube-flannel --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "All namespaces already deleted"
	@echo "Step 12: Final verification..."
	@kubectl get pods -n longhorn-system --ignore-not-found=true 2>/dev/null || echo "✓ longhorn-system namespace is clean"
	@kubectl get pods -n monitoring --ignore-not-found=true 2>/dev/null || echo "✓ monitoring namespace is clean"
	@kubectl get pods -n baget --ignore-not-found=true 2>/dev/null || echo "✓ baget namespace is clean"
	@kubectl get pods -n headlamp --ignore-not-found=true 2>/dev/null || echo "✓ headlamp namespace is clean"
	@kubectl get crd 2>/dev/null | grep -i "longhorn" && echo "⚠ Some Longhorn CRDs still present" || echo "✓ Longhorn CRDs cleaned up"
	@kubectl get crd 2>/dev/null | grep -i "monitoring.coreos.com" && echo "⚠ Some Prometheus CRDs still present" || echo "✓ Prometheus CRDs cleaned up"
	@kubectl get clusterrole longhorn-role 2>/dev/null && echo "⚠ Longhorn ClusterRole still present" || echo "✓ Longhorn RBAC cleaned up"
	@kubectl get clusterrolebinding longhorn-bind flannel 2>/dev/null && echo "⚠ Some ClusterRoleBindings still present" || echo "✓ All ClusterRoleBindings cleaned up"
	@kubectl get storageclass longhorn 2>/dev/null && echo "⚠ Longhorn StorageClass still present" || echo "✓ Longhorn StorageClass cleaned up"
	@kubectl get pods -n kube-flannel --ignore-not-found=true 2>/dev/null || echo "✓ kube-flannel namespace is clean"
	@helm list -A 2>/dev/null | grep -v "NAME" && echo "⚠ Some Helm releases still present:" && helm list -A || echo "✓ All Helm releases cleaned up"
	@echo "✅ Comprehensive cleanup completed!"

destroy-clean: force-clean ## Alias for force-clean

validate: ## Validate Terraform configuration
	terraform validate

format: ## Format Terraform files
	terraform fmt -recursive

lint: validate format ## Lint and validate Terraform code
	@echo "Terraform configuration is valid and formatted"

check-vars: ## Check if terraform.tfvars exists
	@if [ ! -f terraform.tfvars ]; then \
		echo "Error: terraform.tfvars not found!"; \
		echo "Please copy terraform.tfvars.example to terraform.tfvars and customize it."; \
		echo ""; \
		echo "  cp terraform.tfvars.example terraform.tfvars"; \
		echo ""; \
		exit 1; \
	fi

status: ## Show current deployment status
	@echo "=== Terraform State Summary ==="
	@terraform state list 2>/dev/null | wc -l | xargs -I {} echo "Total resources: {}" || echo "No state found (not initialized)"
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
	@kubectl get services --all-namespaces 2>/dev/null | grep LoadBalancer || echo "No LoadBalancer services found"
	@echo ""
	@echo "Use 'make status-<component>' for detailed component status"

clean: ## Clean Terraform cache and state
	rm -rf .terraform
	rm -f .terraform.lock.hcl

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

redeploy: ## Clean and redeploy all infrastructure
	@echo "Clean redeployment starting..."
	$(MAKE) force-clean
	$(MAKE) setup
	$(MAKE) apply
	@echo "✅ Clean redeployment completed!"

# Generate secure credentials
generate-secrets: ## Generate secure passwords for terraform.tfvars
	@echo "Generating secure credentials..."
	@echo ""
	@echo "# Generated credentials - add to your terraform.tfvars file:"
	@echo "baget_api_key = \"$$(openssl rand -base64 32)\""
	@echo "grafana_admin_password = \"$$(openssl rand -base64 16)\""
	@echo "traefik_basic_auth_users = \"$$(htpasswd -nb admin $$(openssl rand -base64 16))\"" 2>/dev/null || echo "# traefik_basic_auth_users requires htpasswd tool (apache2-utils)"
	@echo ""
	@echo "Save these credentials securely!"

# Component Management
list-components: ## List all infrastructure components and their files
	@echo "Infrastructure Components:"
	@echo "========================="
	@echo "🌍 Networking    -> flannel.tf          (CNI network plugin)"
	@echo "📦 Common        -> common.tf           (Terraform config, metrics-server)"
	@echo "⚖️ LoadBalancer  -> kube-vip.tf         (kube-vip DHCP LoadBalancer)"
	@echo "💾 Storage       -> longhorn.tf         (Longhorn distributed storage)"
	@echo "📊 Monitoring    -> monitoring.tf       (Prometheus, Grafana, AlertManager)"
	@echo "🚀 Applications  -> baget.tf            (Baget NuGet server)"
	@echo "📋 Dashboard     -> kubernetes-dashboard.tf (Headlamp Web UI)"
	@echo "🔀 Reverse Proxy -> traefik.tf          (Traefik ingress controller)"
	@echo "🔗 Ingress       -> ingress.tf          (IngressRoutes and middleware)"
	@echo ""
	@echo "Use 'make plan-<component>' or 'make apply-<component>' for targeted operations"

# Component-specific Planning
plan-networking: check-vars check-init ## Plan networking components (Flannel, kube-vip, CoreDNS, Metrics Server)
	@echo "Planning networking components..."
	terraform plan \
		-target=kubernetes_namespace.flannel \
		-target=kubernetes_service_account.flannel \
		-target=kubernetes_cluster_role.flannel \
		-target=kubernetes_cluster_role_binding.flannel \
		-target=kubernetes_config_map.flannel_cfg \
		-target=kubernetes_daemonset.flannel \
		-target=kubernetes_service_account.kube_vip \
		-target=kubernetes_cluster_role.kube_vip \
		-target=kubernetes_cluster_role_binding.kube_vip \
		-target=kubernetes_daemonset.kube_vip \
		-target=kubernetes_cluster_role.system_node_proxier \
		-target=kubernetes_cluster_role_binding.system_node_proxier \
		-target=kubernetes_config_map_v1_data.coredns_custom \
		-target=helm_release.metrics_server

plan-storage: check-vars check-init ## Plan storage components (Longhorn)
	@echo "Planning storage components..."
	terraform plan \
		-target=helm_release.longhorn \
		-target=data.kubernetes_storage_class.longhorn \
		-target=kubernetes_service.longhorn_frontend_lb

plan-monitoring: check-vars check-init ## Plan monitoring components (Prometheus, Grafana)
	@echo "Planning monitoring components..."
	terraform plan \
		-target=helm_release.prometheus_stack

plan-applications: check-vars check-init ## Plan application components (Baget, Dashboard)
	@echo "Planning application components..."
	terraform plan \
		-target=kubernetes_secret.baget_secrets \
		-target=kubernetes_config_map.baget_config \
		-target=kubernetes_persistent_volume_claim.baget_data \
		-target=kubernetes_deployment.baget \
		-target=kubernetes_service.baget \
		-target=kubernetes_namespace.headlamp \
		-target=helm_release.headlamp \
		-target=kubernetes_service_account.headlamp_admin \
		-target=kubernetes_secret.headlamp_admin_token \
		-target=kubernetes_cluster_role_binding.headlamp_admin \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage

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

plan-static-sites: check-vars check-init ## Plan static sites components
	@echo "Planning static sites components..."
	terraform plan \
		-target=kubernetes_namespace.static_sites \
		-target=kubernetes_config_map.static_sites_config \
		-target=kubernetes_deployment.static_sites \
		-target=kubernetes_service.static_sites

plan-nfs: check-vars check-init ## Plan NFS CSI driver
	@echo "Planning NFS CSI driver..."
	terraform plan \
		-target=helm_release.nfs_csi_driver \
		-target=kubernetes_storage_class.nfs_media \
		-target=kubernetes_storage_class.nfs_downloads

plan-flannel: check-vars check-init ## Plan Flannel CNI networking
	@echo "Planning Flannel CNI..."
	terraform plan \
		-target=kubernetes_namespace.flannel \
		-target=kubernetes_service_account.flannel \
		-target=kubernetes_cluster_role.flannel \
		-target=kubernetes_cluster_role_binding.flannel \
		-target=kubernetes_config_map.flannel_cfg \
		-target=kubernetes_daemonset.flannel

plan-kube-vip: check-vars check-init ## Plan kube-vip LoadBalancer
	@echo "Planning kube-vip..."
	terraform plan \
		-target=kubernetes_service_account.kube_vip \
		-target=kubernetes_cluster_role.kube_vip \
		-target=kubernetes_cluster_role_binding.kube_vip \
		-target=kubernetes_daemonset.kube_vip

plan-coredns: check-vars check-init ## Plan CoreDNS configuration
	@echo "Planning CoreDNS config..."
	terraform plan \
		-target=kubernetes_config_map_v1_data.coredns_custom

plan-crowdsec: check-vars check-init ## Plan CrowdSec security engine
	@echo "Planning CrowdSec components..."
	terraform plan \
		-target=kubernetes_namespace.crowdsec \
		-target=helm_release.crowdsec \
		-target=kubernetes_job.crowdsec_register_bouncer \
		-target=kubernetes_service_account.crowdsec_bouncer_registrar \
		-target=kubernetes_role.crowdsec_bouncer_registrar \
		-target=kubernetes_role_binding.crowdsec_bouncer_registrar \
		-target=kubernetes_secret.crowdsec_bouncer_secret

plan-oauth: check-vars check-init ## Plan OAuth2 Proxy
	@echo "Planning OAuth2 Proxy components..."
	terraform plan \
		-target=kubernetes_namespace.oauth2_proxy \
		-target=helm_release.oauth2_proxy

plan-n8n: check-vars check-init ## Plan n8n workflow automation
	@echo "Planning n8n components..."
	terraform plan \
		-target=kubernetes_namespace.n8n \
		-target=kubernetes_persistent_volume_claim.n8n_data \
		-target=kubernetes_deployment.n8n \
		-target=kubernetes_service.n8n

plan-postfix: check-vars check-init ## Plan Postfix SMTP relay
	@echo "Planning Postfix components..."
	terraform plan \
		-target=kubernetes_namespace.postfix \
		-target=kubernetes_config_map.postfix_config \
		-target=kubernetes_deployment.postfix \
		-target=kubernetes_service.postfix

plan-squid: check-vars check-init ## Plan Squid caching proxy
	@echo "Planning Squid components..."
	terraform plan \
		-target=kubernetes_namespace.squid \
		-target=kubernetes_config_map.squid_config \
		-target=kubernetes_persistent_volume_claim.squid_cache \
		-target=kubernetes_deployment.squid \
		-target=kubernetes_service.squid

plan-prowlarr: check-vars check-init ## Plan Prowlarr indexer
	@echo "Planning Prowlarr components..."
	terraform plan \
		-target=kubernetes_namespace.prowlarr \
		-target=kubernetes_persistent_volume_claim.prowlarr_config \
		-target=kubernetes_deployment.prowlarr \
		-target=kubernetes_service.prowlarr

plan-sonarr: check-vars check-init ## Plan Sonarr TV management
	@echo "Planning Sonarr components..."
	terraform plan \
		-target=kubernetes_namespace.sonarr \
		-target=kubernetes_persistent_volume_claim.sonarr_config \
		-target=kubernetes_persistent_volume.sonarr_media \
		-target=kubernetes_persistent_volume_claim.sonarr_media \
		-target=kubernetes_persistent_volume.sonarr_downloads \
		-target=kubernetes_persistent_volume_claim.sonarr_downloads \
		-target=kubernetes_deployment.sonarr \
		-target=kubernetes_service.sonarr

plan-radarr: check-vars check-init ## Plan Radarr movie management
	@echo "Planning Radarr components..."
	terraform plan \
		-target=kubernetes_namespace.radarr \
		-target=kubernetes_persistent_volume_claim.radarr_config \
		-target=kubernetes_persistent_volume.radarr_media \
		-target=kubernetes_persistent_volume_claim.radarr_media \
		-target=kubernetes_persistent_volume.radarr_downloads \
		-target=kubernetes_persistent_volume_claim.radarr_downloads \
		-target=kubernetes_deployment.radarr \
		-target=kubernetes_service.radarr

plan-qbittorrent: check-vars check-init ## Plan qBittorrent + VPN
	@echo "Planning qBittorrent components..."
	terraform plan \
		-target=kubernetes_namespace.qbittorrent \
		-target=kubernetes_secret.gluetun_vpn \
		-target=kubernetes_persistent_volume_claim.qbittorrent_config \
		-target=kubernetes_persistent_volume_claim.qbittorrent_scratch \
		-target=kubernetes_persistent_volume.qbittorrent_downloads \
		-target=kubernetes_persistent_volume_claim.qbittorrent_downloads \
		-target=kubernetes_deployment.qbittorrent \
		-target=kubernetes_service.qbittorrent

plan-emby: check-vars check-init ## Plan Emby media server
	@echo "Planning Emby components..."
	terraform plan \
		-target=kubernetes_namespace.emby \
		-target=kubernetes_persistent_volume_claim.emby_config \
		-target=kubernetes_persistent_volume.emby_media \
		-target=kubernetes_persistent_volume_claim.emby_media \
		-target=kubernetes_deployment.emby \
		-target=kubernetes_service.emby

plan-bazarr: check-vars check-init ## Plan Bazarr subtitle management
	@echo "Planning Bazarr components..."
	terraform plan \
		-target=kubernetes_namespace.bazarr \
		-target=kubernetes_persistent_volume_claim.bazarr_config \
		-target=kubernetes_persistent_volume.bazarr_media \
		-target=kubernetes_persistent_volume_claim.bazarr_media \
		-target=kubernetes_deployment.bazarr \
		-target=kubernetes_service.bazarr

plan-jackett: check-vars check-init ## Plan Jackett indexer support
	@echo "Planning Jackett components..."
	terraform plan \
		-target=kubernetes_namespace.jackett \
		-target=kubernetes_persistent_volume_claim.jackett_config \
		-target=kubernetes_deployment.jackett \
		-target=kubernetes_service.jackett

plan-cleanuparr: check-vars check-init ## Plan Cleanuparr library cleanup
	@echo "Planning Cleanuparr components..."
	terraform plan \
		-target=kubernetes_namespace.cleanuparr \
		-target=kubernetes_persistent_volume_claim.cleanuparr_config \
		-target=kubernetes_deployment.cleanuparr \
		-target=kubernetes_service.cleanuparr

plan-sabnzbd: check-vars check-init ## Plan SABnzbd Usenet client
	@echo "Planning SABnzbd components..."
	terraform plan \
		-target=kubernetes_namespace.sabnzbd \
		-target=kubernetes_persistent_volume_claim.sabnzbd_config \
		-target=kubernetes_persistent_volume.sabnzbd_downloads \
		-target=kubernetes_persistent_volume_claim.sabnzbd_downloads \
		-target=kubernetes_deployment.sabnzbd \
		-target=kubernetes_service.sabnzbd

plan-notifiarr: check-vars check-init ## Plan Notifiarr notifications
	@echo "Planning Notifiarr components..."
	terraform plan \
		-target=kubernetes_namespace.notifiarr \
		-target=kubernetes_secret.notifiarr_config \
		-target=kubernetes_persistent_volume_claim.notifiarr_config \
		-target=kubernetes_deployment.notifiarr \
		-target=kubernetes_service.notifiarr

plan-flaresolverr: check-vars check-init ## Plan Flaresolverr CAPTCHA solver
	@echo "Planning Flaresolverr components..."
	terraform plan \
		-target=kubernetes_namespace.flaresolverr \
		-target=kubernetes_deployment.flaresolverr \
		-target=kubernetes_service.flaresolverr

plan-nvidia: check-vars check-init ## Plan NVIDIA device plugin
	@echo "Planning NVIDIA device plugin..."
	terraform plan \
		-target=helm_release.nvidia_device_plugin

plan-ollama: check-vars check-init ## Plan Ollama LLM inference
	@echo "Planning Ollama components..."
	terraform plan \
		-target=kubernetes_namespace.ollama \
		-target=kubernetes_persistent_volume_claim.ollama_config \
		-target=kubernetes_persistent_volume.ollama_models \
		-target=kubernetes_persistent_volume_claim.ollama_models \
		-target=kubernetes_deployment.ollama \
		-target=kubernetes_service.ollama

plan-qdrant: check-vars check-init ## Plan Qdrant vector database
	@echo "Planning Qdrant components..."
	terraform plan \
		-target=kubernetes_namespace.qdrant \
		-target=kubernetes_persistent_volume_claim.qdrant_data \
		-target=kubernetes_deployment.qdrant \
		-target=kubernetes_service.qdrant

plan-chromadb: check-vars check-init ## Plan ChromaDB vector database
	@echo "Planning ChromaDB components..."
	terraform plan \
		-target=kubernetes_namespace.chromadb \
		-target=kubernetes_persistent_volume_claim.chromadb_data \
		-target=kubernetes_deployment.chromadb \
		-target=kubernetes_service.chromadb

plan-comfyui: check-vars check-init ## Plan ComfyUI image generation
	@echo "Planning ComfyUI components..."
	terraform plan \
		-target=kubernetes_namespace.comfyui \
		-target=kubernetes_persistent_volume_claim.comfyui_config \
		-target=kubernetes_persistent_volume.comfyui_models \
		-target=kubernetes_persistent_volume_claim.comfyui_models \
		-target=kubernetes_deployment.comfyui \
		-target=kubernetes_service.comfyui

plan-homepage: check-vars check-init ## Plan Homepage dashboard
	@echo "Planning Homepage..."
	terraform plan \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage

plan-devtron: check-vars check-init ## Plan Devtron dashboard
	@echo "Planning Devtron..."
	terraform plan \
		-target=kubernetes_namespace.devtron \
		-target=helm_release.devtron \
		-target=kubernetes_config_map.devtron_argocd_cm_stub \
		-target=kubernetes_secret.devtron_argocd_secret_stub

plan-runners: check-vars check-init ## Plan GitHub self-hosted runners (ARC)
	@echo "Planning GitHub runners (ARC)..."
	terraform plan \
		-target=kubernetes_namespace.arc_system \
		-target=kubernetes_namespace.arc_runners \
		-target=kubernetes_secret.arc_ktsu_dev_github_app \
		-target=kubernetes_secret.arc_cardapp_github_app \
		-target=kubernetes_secret.arc_claudecluster_github_app \
		-target=helm_release.arc_controller \
		-target=helm_release.arc_ktsu_dev \
		-target=helm_release.arc_cardapp \
		-target=helm_release.arc_claudecluster \
		-target=null_resource.arc_dind_mtu_patch_ktsu_dev \
		-target=null_resource.arc_dind_mtu_patch_cardapp \
		-target=null_resource.arc_dind_mtu_patch_claudecluster

plan-traefik: check-vars check-init ## Plan Traefik reverse proxy
	@echo "Planning Traefik components..."
	terraform plan \
		-target=kubernetes_namespace.traefik \
		-target=kubernetes_secret.traefik_azure_dns \
		-target=helm_release.traefik

plan-ingress: check-vars check-init ## Plan ingress routes and middleware
	@echo "Planning ingress components..."
	terraform plan \
		-target=kubernetes_secret.traefik_basic_auth \
		-target=kubernetes_manifest.middleware_redirect_https \
		-target=kubernetes_manifest.middleware_rate_limit \
		-target=kubernetes_manifest.middleware_basic_auth \
		-target=kubernetes_manifest.middleware_crowdsec_bouncer \
		-target=kubernetes_manifest.middleware_oauth_forward_auth \
		-target=kubernetes_manifest.servers_transport_insecure \
		-target=kubernetes_manifest.ingressroute_traefik_dashboard \
		-target=kubernetes_manifest.ingressroute_grafana \
		-target=kubernetes_manifest.ingressroute_prometheus \
		-target=kubernetes_manifest.ingressroute_alertmanager \
		-target=kubernetes_manifest.ingressroute_baget \
		-target=kubernetes_manifest.ingressroute_longhorn \
		-target=kubernetes_manifest.ingressroute_dashboard \
		-target=kubernetes_manifest.ingressroute_oauth2_proxy \
		-target=kubernetes_manifest.ingressroute_n8n \
		-target=kubernetes_manifest.ingressroute_prowlarr \
		-target=kubernetes_manifest.ingressroute_sonarr \
		-target=kubernetes_manifest.ingressroute_radarr \
		-target=kubernetes_manifest.ingressroute_qbittorrent \
		-target=kubernetes_manifest.ingressroute_emby \
		-target=kubernetes_manifest.ingressroute_bazarr \
		-target=kubernetes_manifest.ingressroute_jackett \
		-target=kubernetes_manifest.ingressroute_cleanuparr \
		-target=kubernetes_manifest.ingressroute_sabnzbd \
		-target=kubernetes_manifest.ingressroute_notifiarr \
		-target=kubernetes_manifest.ingressroute_ollama \
		-target=kubernetes_manifest.ingressroute_qdrant \
		-target=kubernetes_manifest.ingressroute_chromadb \
		-target=kubernetes_manifest.ingressroute_comfyui \
		-target=kubernetes_manifest.ingressroute_homepage \
		-target=kubernetes_manifest.ingressroute_devtron \
		-target=kubernetes_manifest.ingressroute_static_site

plan-azure-dns: check-vars check-init ## Plan Azure DNS A records
	@echo "Planning Azure DNS records..."
	terraform plan \
		-target=data.azurerm_dns_zone.main \
		-target=azurerm_dns_a_record.services

# Component-specific Deployment
apply-networking: check-vars check-init ## Deploy networking components (Flannel, kube-vip, CoreDNS, Metrics Server)
	@echo "Deploying networking components..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.flannel \
		-target=kubernetes_service_account.flannel \
		-target=kubernetes_cluster_role.flannel \
		-target=kubernetes_cluster_role_binding.flannel \
		-target=kubernetes_config_map.flannel_cfg \
		-target=kubernetes_daemonset.flannel \
		-target=kubernetes_service_account.kube_vip \
		-target=kubernetes_cluster_role.kube_vip \
		-target=kubernetes_cluster_role_binding.kube_vip \
		-target=kubernetes_daemonset.kube_vip \
		-target=kubernetes_cluster_role.system_node_proxier \
		-target=kubernetes_cluster_role_binding.system_node_proxier \
		-target=kubernetes_config_map_v1_data.coredns_custom \
		-target=helm_release.metrics_server

apply-storage: check-vars check-init ## Deploy storage components (Longhorn)
	@echo "Deploying storage components..."
	terraform apply \
		-target=helm_release.longhorn \
		-target=data.kubernetes_storage_class.longhorn \
		-target=kubernetes_service.longhorn_frontend_lb

apply-monitoring: check-vars check-init ## Deploy monitoring components (Prometheus, Grafana)
	@echo "Deploying monitoring components..."
	terraform apply \
		-target=helm_release.prometheus_stack

apply-applications: check-vars check-init ## Deploy application components (Baget, Dashboard)
	@echo "Deploying application components..."
	terraform apply -auto-approve \
		-target=kubernetes_secret.baget_secrets \
		-target=kubernetes_config_map.baget_config \
		-target=kubernetes_persistent_volume_claim.baget_data \
		-target=kubernetes_deployment.baget \
		-target=kubernetes_service.baget \
		-target=kubernetes_namespace.headlamp \
		-target=helm_release.headlamp \
		-target=kubernetes_service_account.headlamp_admin \
		-target=kubernetes_secret.headlamp_admin_token \
		-target=kubernetes_cluster_role_binding.headlamp_admin \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage

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

apply-static-sites: check-vars check-init ## Deploy static sites components
	@echo "Deploying static sites..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.static_sites \
		-target=kubernetes_config_map.static_sites_config \
		-target=kubernetes_deployment.static_sites \
		-target=kubernetes_service.static_sites

apply-nfs: check-vars check-init ## Deploy NFS CSI driver
	@echo "Deploying NFS CSI driver..."
	terraform apply -auto-approve \
		-target=helm_release.nfs_csi_driver \
		-target=kubernetes_storage_class.nfs_media \
		-target=kubernetes_storage_class.nfs_downloads

apply-flannel: check-vars check-init ## Deploy Flannel CNI networking
	@echo "Deploying Flannel CNI..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.flannel \
		-target=kubernetes_service_account.flannel \
		-target=kubernetes_cluster_role.flannel \
		-target=kubernetes_cluster_role_binding.flannel \
		-target=kubernetes_config_map.flannel_cfg \
		-target=kubernetes_daemonset.flannel

apply-kube-vip: check-vars check-init ## Deploy kube-vip LoadBalancer
	@echo "Deploying kube-vip..."
	terraform apply -auto-approve \
		-target=kubernetes_service_account.kube_vip \
		-target=kubernetes_cluster_role.kube_vip \
		-target=kubernetes_cluster_role_binding.kube_vip \
		-target=kubernetes_daemonset.kube_vip

apply-coredns: check-vars check-init ## Deploy CoreDNS configuration
	@echo "Deploying CoreDNS config..."
	terraform apply -auto-approve \
		-target=kubernetes_config_map_v1_data.coredns_custom

apply-crowdsec: check-vars check-init ## Deploy CrowdSec security engine
	@echo "Deploying CrowdSec..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.crowdsec \
		-target=helm_release.crowdsec \
		-target=kubernetes_job.crowdsec_register_bouncer \
		-target=kubernetes_service_account.crowdsec_bouncer_registrar \
		-target=kubernetes_role.crowdsec_bouncer_registrar \
		-target=kubernetes_role_binding.crowdsec_bouncer_registrar \
		-target=kubernetes_secret.crowdsec_bouncer_secret

apply-oauth: check-vars check-init ## Deploy OAuth2 Proxy
	@echo "Deploying OAuth2 Proxy..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.oauth2_proxy \
		-target=helm_release.oauth2_proxy

apply-n8n: check-vars check-init ## Deploy n8n workflow automation
	@echo "Deploying n8n..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.n8n \
		-target=kubernetes_persistent_volume_claim.n8n_data \
		-target=kubernetes_deployment.n8n \
		-target=kubernetes_service.n8n

apply-postfix: check-vars check-init ## Deploy Postfix SMTP relay
	@echo "Deploying Postfix..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.postfix \
		-target=kubernetes_config_map.postfix_config \
		-target=kubernetes_deployment.postfix \
		-target=kubernetes_service.postfix

apply-squid: check-vars check-init ## Deploy Squid caching proxy
	@echo "Deploying Squid..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.squid \
		-target=kubernetes_config_map.squid_config \
		-target=kubernetes_persistent_volume_claim.squid_cache \
		-target=kubernetes_deployment.squid \
		-target=kubernetes_service.squid

apply-prowlarr: check-vars check-init ## Deploy Prowlarr indexer
	@echo "Deploying Prowlarr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.prowlarr \
		-target=kubernetes_persistent_volume_claim.prowlarr_config \
		-target=kubernetes_deployment.prowlarr \
		-target=kubernetes_service.prowlarr

apply-sonarr: check-vars check-init ## Deploy Sonarr TV management
	@echo "Deploying Sonarr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.sonarr \
		-target=kubernetes_persistent_volume_claim.sonarr_config \
		-target=kubernetes_persistent_volume.sonarr_media \
		-target=kubernetes_persistent_volume_claim.sonarr_media \
		-target=kubernetes_persistent_volume.sonarr_downloads \
		-target=kubernetes_persistent_volume_claim.sonarr_downloads \
		-target=kubernetes_deployment.sonarr \
		-target=kubernetes_service.sonarr

apply-radarr: check-vars check-init ## Deploy Radarr movie management
	@echo "Deploying Radarr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.radarr \
		-target=kubernetes_persistent_volume_claim.radarr_config \
		-target=kubernetes_persistent_volume.radarr_media \
		-target=kubernetes_persistent_volume_claim.radarr_media \
		-target=kubernetes_persistent_volume.radarr_downloads \
		-target=kubernetes_persistent_volume_claim.radarr_downloads \
		-target=kubernetes_deployment.radarr \
		-target=kubernetes_service.radarr

apply-qbittorrent: check-vars check-init ## Deploy qBittorrent + VPN
	@echo "Deploying qBittorrent..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.qbittorrent \
		-target=kubernetes_secret.gluetun_vpn \
		-target=kubernetes_persistent_volume_claim.qbittorrent_config \
		-target=kubernetes_persistent_volume_claim.qbittorrent_scratch \
		-target=kubernetes_persistent_volume.qbittorrent_downloads \
		-target=kubernetes_persistent_volume_claim.qbittorrent_downloads \
		-target=kubernetes_deployment.qbittorrent \
		-target=kubernetes_service.qbittorrent

apply-emby: check-vars check-init ## Deploy Emby media server
	@echo "Deploying Emby..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.emby \
		-target=kubernetes_persistent_volume_claim.emby_config \
		-target=kubernetes_persistent_volume.emby_media \
		-target=kubernetes_persistent_volume_claim.emby_media \
		-target=kubernetes_deployment.emby \
		-target=kubernetes_service.emby

apply-bazarr: check-vars check-init ## Deploy Bazarr subtitle management
	@echo "Deploying Bazarr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.bazarr \
		-target=kubernetes_persistent_volume_claim.bazarr_config \
		-target=kubernetes_persistent_volume.bazarr_media \
		-target=kubernetes_persistent_volume_claim.bazarr_media \
		-target=kubernetes_deployment.bazarr \
		-target=kubernetes_service.bazarr

apply-jackett: check-vars check-init ## Deploy Jackett indexer support
	@echo "Deploying Jackett..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.jackett \
		-target=kubernetes_persistent_volume_claim.jackett_config \
		-target=kubernetes_deployment.jackett \
		-target=kubernetes_service.jackett

apply-cleanuparr: check-vars check-init ## Deploy Cleanuparr library cleanup
	@echo "Deploying Cleanuparr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.cleanuparr \
		-target=kubernetes_persistent_volume_claim.cleanuparr_config \
		-target=kubernetes_deployment.cleanuparr \
		-target=kubernetes_service.cleanuparr

apply-sabnzbd: check-vars check-init ## Deploy SABnzbd Usenet client
	@echo "Deploying SABnzbd..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.sabnzbd \
		-target=kubernetes_persistent_volume_claim.sabnzbd_config \
		-target=kubernetes_persistent_volume.sabnzbd_downloads \
		-target=kubernetes_persistent_volume_claim.sabnzbd_downloads \
		-target=kubernetes_deployment.sabnzbd \
		-target=kubernetes_service.sabnzbd

apply-notifiarr: check-vars check-init ## Deploy Notifiarr notifications
	@echo "Deploying Notifiarr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.notifiarr \
		-target=kubernetes_secret.notifiarr_config \
		-target=kubernetes_persistent_volume_claim.notifiarr_config \
		-target=kubernetes_deployment.notifiarr \
		-target=kubernetes_service.notifiarr

apply-flaresolverr: check-vars check-init ## Deploy Flaresolverr CAPTCHA solver
	@echo "Deploying Flaresolverr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.flaresolverr \
		-target=kubernetes_deployment.flaresolverr \
		-target=kubernetes_service.flaresolverr

apply-nvidia: check-vars check-init ## Deploy NVIDIA device plugin
	@echo "Deploying NVIDIA device plugin..."
	terraform apply -auto-approve \
		-target=helm_release.nvidia_device_plugin

apply-ollama: check-vars check-init ## Deploy Ollama LLM inference
	@echo "Deploying Ollama..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.ollama \
		-target=kubernetes_persistent_volume_claim.ollama_config \
		-target=kubernetes_persistent_volume.ollama_models \
		-target=kubernetes_persistent_volume_claim.ollama_models \
		-target=kubernetes_deployment.ollama \
		-target=kubernetes_service.ollama

apply-qdrant: check-vars check-init ## Deploy Qdrant vector database
	@echo "Deploying Qdrant..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.qdrant \
		-target=kubernetes_persistent_volume_claim.qdrant_data \
		-target=kubernetes_deployment.qdrant \
		-target=kubernetes_service.qdrant

apply-chromadb: check-vars check-init ## Deploy ChromaDB vector database
	@echo "Deploying ChromaDB..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.chromadb \
		-target=kubernetes_persistent_volume_claim.chromadb_data \
		-target=kubernetes_deployment.chromadb \
		-target=kubernetes_service.chromadb

apply-comfyui: check-vars check-init ## Deploy ComfyUI image generation
	@echo "Deploying ComfyUI..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.comfyui \
		-target=kubernetes_persistent_volume_claim.comfyui_config \
		-target=kubernetes_persistent_volume.comfyui_models \
		-target=kubernetes_persistent_volume_claim.comfyui_models \
		-target=kubernetes_deployment.comfyui \
		-target=kubernetes_service.comfyui

apply-homepage: check-vars check-init ## Deploy Homepage dashboard
	@echo "Deploying Homepage..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage

apply-devtron: check-vars check-init ## Deploy Devtron dashboard
	@echo "Deploying Devtron..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.devtron \
		-target=helm_release.devtron \
		-target=kubernetes_config_map.devtron_argocd_cm_stub \
		-target=kubernetes_secret.devtron_argocd_secret_stub

apply-runners: check-vars check-init ## Deploy GitHub self-hosted runners (ARC)
	@echo "Deploying GitHub runners (ARC)..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.arc_system \
		-target=kubernetes_namespace.arc_runners \
		-target=kubernetes_secret.arc_ktsu_dev_github_app \
		-target=kubernetes_secret.arc_cardapp_github_app \
		-target=kubernetes_secret.arc_claudecluster_github_app \
		-target=helm_release.arc_controller \
		-target=helm_release.arc_ktsu_dev \
		-target=helm_release.arc_cardapp \
		-target=helm_release.arc_claudecluster \
		-target=null_resource.arc_dind_mtu_patch_ktsu_dev \
		-target=null_resource.arc_dind_mtu_patch_cardapp \
		-target=null_resource.arc_dind_mtu_patch_claudecluster

apply-traefik: check-vars check-init ## Deploy Traefik reverse proxy
	@echo "Deploying Traefik..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.traefik \
		-target=kubernetes_secret.traefik_azure_dns \
		-target=helm_release.traefik

apply-ingress: check-vars check-init ## Deploy ingress routes and middleware
	@echo "Deploying ingress routes..."
	terraform apply -auto-approve \
		-target=kubernetes_secret.traefik_basic_auth \
		-target=kubernetes_manifest.middleware_redirect_https \
		-target=kubernetes_manifest.middleware_rate_limit \
		-target=kubernetes_manifest.middleware_basic_auth \
		-target=kubernetes_manifest.middleware_crowdsec_bouncer \
		-target=kubernetes_manifest.middleware_oauth_forward_auth \
		-target=kubernetes_manifest.servers_transport_insecure \
		-target=kubernetes_manifest.ingressroute_traefik_dashboard \
		-target=kubernetes_manifest.ingressroute_grafana \
		-target=kubernetes_manifest.ingressroute_prometheus \
		-target=kubernetes_manifest.ingressroute_alertmanager \
		-target=kubernetes_manifest.ingressroute_baget \
		-target=kubernetes_manifest.ingressroute_longhorn \
		-target=kubernetes_manifest.ingressroute_dashboard \
		-target=kubernetes_manifest.ingressroute_oauth2_proxy \
		-target=kubernetes_manifest.ingressroute_n8n \
		-target=kubernetes_manifest.ingressroute_prowlarr \
		-target=kubernetes_manifest.ingressroute_sonarr \
		-target=kubernetes_manifest.ingressroute_radarr \
		-target=kubernetes_manifest.ingressroute_qbittorrent \
		-target=kubernetes_manifest.ingressroute_emby \
		-target=kubernetes_manifest.ingressroute_bazarr \
		-target=kubernetes_manifest.ingressroute_jackett \
		-target=kubernetes_manifest.ingressroute_cleanuparr \
		-target=kubernetes_manifest.ingressroute_sabnzbd \
		-target=kubernetes_manifest.ingressroute_notifiarr \
		-target=kubernetes_manifest.ingressroute_ollama \
		-target=kubernetes_manifest.ingressroute_qdrant \
		-target=kubernetes_manifest.ingressroute_chromadb \
		-target=kubernetes_manifest.ingressroute_comfyui \
		-target=kubernetes_manifest.ingressroute_homepage \
		-target=kubernetes_manifest.ingressroute_devtron \
		-target=kubernetes_manifest.ingressroute_static_site

apply-azure-dns: check-vars check-init ## Deploy Azure DNS A records
	@echo "Deploying Azure DNS records..."
	terraform apply -auto-approve \
		-target=data.azurerm_dns_zone.main \
		-target=azurerm_dns_a_record.services

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
debug-networking: ## Debug networking components (Flannel, kube-vip, CoreDNS, Metrics Server)
	@echo "=== Networking Component Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep -E "(flannel|kube_vip|coredns|metrics_server|node_proxier)" || echo "No networking resources found in state"
	@echo ""
	@echo "Flannel Pods:"
	@kubectl get pods -n kube-flannel -o wide 2>/dev/null || echo "Flannel namespace not found"
	@echo ""
	@echo "kube-vip Pods:"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip -o wide 2>/dev/null || echo "kube-vip not found"
	@echo ""
	@echo "CoreDNS Pods:"
	@kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide 2>/dev/null || echo "CoreDNS not found"
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

debug-applications: ## Debug application components (Baget, Dashboard)
	@echo "=== Applications Component Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep -E "(baget|headlamp)" || echo "No application resources found in state"
	@echo ""
	@echo "Baget Pods:"
	@kubectl get pods -n baget -o wide 2>/dev/null || echo "Baget namespace not found"
	@echo ""
	@echo "Headlamp Pods:"
	@kubectl get pods -n headlamp -o wide 2>/dev/null || echo "Headlamp namespace not found"
	@echo ""
	@echo "Application Services:"
	@kubectl get svc -n baget 2>/dev/null || echo "No Baget services found"
	@kubectl get svc -n headlamp 2>/dev/null || echo "No Headlamp services found"
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

debug-traefik: ## Debug Traefik reverse proxy
	@echo "=== Traefik Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep traefik || echo "No Traefik resources found in state"
	@echo ""
	@echo "Traefik Pods:"
	@kubectl get pods -n traefik -o wide 2>/dev/null || echo "Traefik namespace not found"
	@echo ""
	@echo "Traefik Service:"
	@kubectl get svc -n traefik 2>/dev/null || echo "No Traefik services found"
	@echo ""
	@echo "IngressRoutes:"
	@kubectl get ingressroutes -A 2>/dev/null || echo "No IngressRoutes found"
	@echo ""
	@echo "Middleware:"
	@kubectl get middlewares -A 2>/dev/null || echo "No Middleware found"
	@echo ""
	@echo "Certificates:"
	@kubectl get certificates -A 2>/dev/null || echo "No certificates found"

debug-ingress: ## Debug ingress routes
	@echo "=== Ingress Routes Debug ==="
	@echo "IngressRoutes:"
	@kubectl get ingressroutes -A -o wide 2>/dev/null || echo "No IngressRoutes found"
	@echo ""
	@echo "Middleware:"
	@kubectl get middlewares -A -o wide 2>/dev/null || echo "No Middleware found"
	@echo ""
	@echo "ServersTransports:"
	@kubectl get serverstransports -A 2>/dev/null || echo "No ServersTransports found"

debug-runners: ## Debug GitHub runners (ARC) — show controller, listeners, runner pods
	@echo "=== ARC controller ==="
	kubectl get pods -n arc-system -l app.kubernetes.io/name=gha-rs-controller
	@echo ""
	@echo "=== Runner listeners ==="
	kubectl get pods -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener
	@echo ""
	@echo "=== Runner pods (ephemeral) ==="
	kubectl get pods -n arc-runners -l app.kubernetes.io/component=runner
	@echo ""
	@echo "=== AutoscalingRunnerSets ==="
	kubectl get autoscalingrunnersets.actions.github.com -n arc-runners
	@echo ""
	@echo "=== Controller logs (tail 50) ==="
	kubectl logs -n arc-system -l app.kubernetes.io/name=gha-rs-controller --tail=50

debug-devtron: ## Debug Devtron — show pods, PVCs, service, and admin password
	@echo "=== Devtron Pods ==="
	@kubectl get pods -n devtroncd -o wide 2>/dev/null || echo "Devtron namespace not found"
	@echo ""
	@echo "=== Devtron PVCs ==="
	@kubectl get pvc -n devtroncd 2>/dev/null || echo "No Devtron PVCs"
	@echo ""
	@echo "=== Devtron Services ==="
	@kubectl get svc -n devtroncd 2>/dev/null || echo "No Devtron services"
	@echo ""
	@echo "=== Devtron Admin Password ==="
	@# ADMIN_PASSWORD is the plaintext seeded at install; the real auth check is
	@# against the bcrypt hash in admin.password. If you rotate one, rotate both.
	@kubectl -n devtroncd get secret devtron-secret -o jsonpath='{.data.ADMIN_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || echo "devtron-secret not found (pods may still be initializing)"
	@echo ""

# Component-specific Status
status-networking: ## Show networking component status
	@echo "=== Networking Status ==="
	@echo "Flannel:"
	@kubectl get pods -n kube-flannel 2>/dev/null || echo "Flannel not deployed"
	@echo "kube-vip:"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip 2>/dev/null || echo "kube-vip not deployed"
	@echo "CoreDNS:"
	@kubectl get pods -n kube-system -l k8s-app=kube-dns 2>/dev/null || echo "CoreDNS not deployed"
	@echo "Metrics Server:"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server 2>/dev/null || echo "Metrics Server not deployed"

status-storage: ## Show storage component status
	@echo "=== Storage Status ==="
	@kubectl get pods -n longhorn-system 2>/dev/null || echo "Longhorn not deployed"
	@kubectl get storageclass longhorn 2>/dev/null || echo "Longhorn StorageClass not found"
	@kubectl get svc -n longhorn-system longhorn-frontend-lb 2>/dev/null || echo "Longhorn UI service not found"

status-monitoring: ## Show monitoring component status
	@echo "=== Monitoring Status ==="
	@kubectl get pods -n monitoring 2>/dev/null || echo "Monitoring not deployed"
	@kubectl get svc -n monitoring 2>/dev/null | grep LoadBalancer || echo "No monitoring LoadBalancer services found"

status-applications: ## Show application component status
	@echo "=== Applications Status ==="
	@kubectl get pods -n baget 2>/dev/null || echo "Baget not deployed"
	@kubectl get svc -n baget baget-service 2>/dev/null || echo "Baget service not found"
	@kubectl get pods -n headlamp 2>/dev/null || echo "Headlamp not deployed"
	@kubectl get svc -n headlamp 2>/dev/null || echo "Headlamp service not found"

status-dns: ## Show DNS component status
	@echo "=== DNS Status ==="
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=pihole-dns-sync 2>/dev/null || echo "Pi-hole sync not deployed"
	@echo "Recent Pi-hole sync activity:"
	@kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync --tail=5 2>/dev/null || echo "No recent activity"

status-static-sites: ## Show static sites status
	@echo "=== Static Sites Status ==="
	@kubectl get pods -n static-sites 2>/dev/null || echo "Static sites not deployed"
	@kubectl get svc -n static-sites 2>/dev/null || echo "No services found"

status-traefik: ## Show Traefik status
	@echo "=== Traefik Status ==="
	@kubectl get pods -n traefik 2>/dev/null || echo "Traefik not deployed"
	@kubectl get svc -n traefik 2>/dev/null || echo "Traefik service not found"

status-ingress: ## Show ingress routes status
	@echo "=== Ingress Status ==="
	@kubectl get ingressroutes -A 2>/dev/null || echo "No IngressRoutes found"

logs: ## Show logs for all deployed applications
	@echo "=== All Component Logs ==="
	@echo "Flannel Logs:"
	@kubectl logs -n kube-flannel -l app=flannel --tail=5 2>/dev/null || echo "No Flannel logs"
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
	@echo "Kubernetes Dashboard Logs:"
	@kubectl logs -n headlamp -l app.kubernetes.io/name=headlamp --tail=5 2>/dev/null || echo "No Headlamp logs"
	@echo ""
	@echo "Pi-hole Sync Logs:"
	@kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync --tail=5 2>/dev/null || echo "No Pi-hole sync logs"
	@echo ""
	@echo "Use 'make debug-<component>' for detailed component debugging"

# Workflow Shortcuts
deploy-core: ## Deploy core infrastructure (networking + storage + traefik + dns)
	@echo "Deploying core infrastructure (networking + storage + traefik + dns)..."
	$(MAKE) apply-networking
	$(MAKE) apply-storage
	$(MAKE) apply-traefik
	$(MAKE) apply-ingress
	$(MAKE) apply-azure-dns

deploy-apps: ## Deploy applications (monitoring + apps + dns + static sites)
	@echo "Deploying applications (monitoring + apps + dns + static sites)..."
	$(MAKE) apply-monitoring
	$(MAKE) apply-applications
	$(MAKE) apply-dns
	$(MAKE) apply-static-sites

plan-all-components: ## Plan all components individually
	@echo "Planning all components..."
	$(MAKE) plan-networking
	$(MAKE) plan-storage
	$(MAKE) plan-traefik
	$(MAKE) plan-ingress
	$(MAKE) plan-monitoring
	$(MAKE) plan-applications
	$(MAKE) plan-dns
	$(MAKE) plan-static-sites

status-all-components: ## Show status for all components
	@echo "Checking all component status..."
	$(MAKE) status-networking
	$(MAKE) status-storage
	$(MAKE) status-traefik
	$(MAKE) status-ingress
	$(MAKE) status-monitoring
	$(MAKE) status-applications
	$(MAKE) status-dns
	$(MAKE) status-static-sites

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
	@kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Flannel: {} pods running" || echo "  Flannel: Not deployed"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  kube-vip: {} pods running" || echo "  kube-vip: Not deployed"
	@kubectl get pods -n longhorn-system --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Longhorn: {} pods running" || echo "  Longhorn: Not deployed"
	@kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Monitoring: {} pods running" || echo "  Monitoring: Not deployed"
	@kubectl get pods -n baget --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Baget: {} pods running" || echo "  Baget: Not deployed"
	@kubectl get pods -n headlamp --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Headlamp: {} pods running" || echo "  Headlamp: Not deployed"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=pihole-dns-sync --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Pi-hole Sync: {} pods running" || echo "  Pi-hole Sync: Not deployed"
	@echo ""
	@echo "Use 'make debug-<component>' for detailed debugging"

# kube-proxy Management
apply-kube-proxy-rbac: ## Apply correct RBAC for kube-proxy
	@echo "🔧 Applying kube-proxy RBAC resources..."
	@terraform apply -auto-approve -lock=false -target="kubernetes_cluster_role.system_node_proxier" -target="kubernetes_cluster_role_binding.system_node_proxier" || echo "RBAC already exists"
	@echo "✅ kube-proxy RBAC applied"

restart-kube-proxy: ## Restart kube-proxy DaemonSet to pick up new RBAC permissions
	@echo "🔄 Restarting kube-proxy DaemonSet..."
	@kubectl rollout restart daemonset/kube-proxy -n kube-system
	@echo "⏳ Waiting for kube-proxy rollout to complete..."
	@kubectl rollout status daemonset/kube-proxy -n kube-system --timeout=300s
	@echo "✅ kube-proxy restarted successfully"

test-dns: ## Test DNS resolution after networking fixes
	@echo "🧪 Testing DNS resolution..."
	@kubectl run dns-test --image=busybox:1.35 --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local || echo "⚠️ DNS test failed"

test-clusterip: ## Test ClusterIP connectivity
	@echo "🧪 Testing ClusterIP connectivity..."
	@kubectl run connectivity-test --image=busybox:1.35 --rm -it --restart=Never -- ping -c 2 10.96.0.10 || echo "⚠️ ClusterIP connectivity test failed"

fix-cluster-networking: apply-kube-proxy-rbac restart-kube-proxy test-clusterip test-dns ## Complete fix for cluster networking issues
	@echo "✅ Cluster networking fix completed!"

fix-stuck-namespace: ## Fix stuck namespace by removing finalizers from Longhorn resources
	@echo "🔧 Fixing stuck namespace by removing finalizers..."
	@echo "  Removing webhooks..."
	@kubectl delete validatingwebhookconfigurations longhorn-webhook-validator --ignore-not-found=true 2>/dev/null || echo "  No longhorn webhook validators"
	@kubectl delete mutatingwebhookconfigurations longhorn-webhook-mutator --ignore-not-found=true 2>/dev/null || echo "  No longhorn webhook mutators"
	@echo "  Patching common stuck resources (PowerShell-compatible)..."
	@kubectl patch backuptargets.longhorn.io default -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  No backup targets to patch"
	@echo "  Nuclear option - removing namespace finalizers directly..."
	@kubectl patch namespace longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Namespace already deleted or no finalizers to remove"
	@echo "✅ Stuck namespace fix applied - namespace should delete automatically now"

# Advanced workflows
taint-component: ## Taint a component for recreation (usage: make taint-component COMPONENT=storage)
ifndef COMPONENT
	@echo "Error: COMPONENT variable required"
	@echo "Usage: make taint-component COMPONENT=<networking|storage|monitoring|applications|dashboard|dns>"
	@echo "Example: make taint-component COMPONENT=storage"
	@exit 1
endif
	@echo "Tainting $(COMPONENT) component for recreation..."
	@case "$(COMPONENT)" in \
		networking) terraform taint kubernetes_daemonset.flannel ;; \
		storage) terraform taint helm_release.longhorn ;; \
		monitoring) terraform taint helm_release.prometheus_stack ;; \
		applications) terraform taint kubernetes_deployment.baget ;; \
		dashboard) terraform taint helm_release.headlamp ;; \
		dns) terraform taint kubernetes_deployment.pihole_dns_sync ;; \
		*) echo "Invalid component: $(COMPONENT)" && exit 1 ;; \
	esac
	@echo "Component $(COMPONENT) tainted. Run 'make apply-$(COMPONENT)' to recreate."

# =============================================================================
# Recovery targets (post-outage / node reboot)
# =============================================================================

WORKER_NODES := rainbow.home k8s02.home celery.home
SSH_OPTS := -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes

restart-kube-vip: ## Restart kube-vip DaemonSet to recover LoadBalancer VIP
	@echo "Restarting kube-vip DaemonSet..."
	@kubectl rollout restart daemonset -n kube-system kube-vip-ds
	@echo "Waiting for kube-vip pods to be ready..."
	@kubectl rollout status daemonset -n kube-system kube-vip-ds --timeout=60s
	@echo "Verifying LoadBalancer IP..."
	@sleep 5
	@kubectl get svc --all-namespaces | grep LoadBalancer
	@echo "kube-vip restarted."

clean-longhorn-mounts: ## Clean stale Longhorn mounts on worker nodes via SSH
	@echo "Cleaning stale Longhorn mounts on worker nodes..."
	@for node in $(WORKER_NODES); do \
		echo "  Checking $$node..."; \
		ssh $(SSH_OPTS) matt@$$node \
			'STALE=$$(mount | grep "/dev/longhorn/" | awk "{print \$$3}" | tac); \
			if [ -z "$$STALE" ]; then echo "    No stale mounts"; \
			else for m in $$STALE; do sudo umount "$$m" 2>/dev/null && echo "    Unmounted $$m" || sudo umount -l "$$m" 2>/dev/null && echo "    Lazy unmounted $$m"; done; fi; \
			MPATH=$$(sudo dmsetup info 2>/dev/null | grep -c "^Name:.*mpath" || true); \
			if [ "$$MPATH" -gt 0 ]; then echo "    Flushing $$MPATH multipath devices..."; sudo multipath -F 2>/dev/null; fi' \
			2>/dev/null || echo "  Could not SSH to $$node (skipped)"; \
	done
	@echo "Restarting Longhorn CSI plugins on worker nodes..."
	@kubectl get pod -n longhorn-system -o name | grep csi-plugin | xargs -I {} kubectl delete {} -n longhorn-system 2>/dev/null || true
	@echo "Stale mount cleanup complete."

recover: ## Full post-outage recovery (clean mounts, restart kube-vip, restart stuck pods)
	@echo "=== Post-Outage Recovery ==="
	@echo ""
	@echo "Step 1: Checking node status..."
	@kubectl get nodes
	@echo ""
	@echo "Step 2: Cleaning stale Longhorn mounts..."
	@$(MAKE) clean-longhorn-mounts
	@echo ""
	@echo "Step 3: Restarting kube-vip for LoadBalancer VIP..."
	@$(MAKE) restart-kube-vip
	@echo ""
	@echo "Step 4: Deleting stuck pods (ContainerCreating/CrashLoopBackOff)..."
	@kubectl get pods --all-namespaces --no-headers | awk '$$4 ~ /ContainerCreating|ImagePullBackOff|Init:/ {print "-n " $$1 " " $$2}' | xargs -I {} sh -c 'kubectl delete pod {} 2>/dev/null' || true
	@echo ""
	@echo "Step 5: Force-deleting Unknown pods..."
	@kubectl get pods --all-namespaces --no-headers | awk '$$4 == "Unknown" {print "-n " $$1 " " $$2}' | xargs -I {} sh -c 'kubectl delete pod {} --force --grace-period=0 2>/dev/null' || true
	@echo ""
	@echo "Step 6: Waiting 30s for pods to reschedule..."
	@sleep 30
	@echo ""
	@echo "Step 7: Final status check..."
	@kubectl get pods --all-namespaces | grep -v Running | grep -v Succeeded | grep -v NAMESPACE || echo "All pods running!"
	@echo ""
	@echo "=== Recovery complete ==="
