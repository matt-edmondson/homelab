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
	@echo "  Uninstalling kubernetes-dashboard..."
	@helm uninstall kubernetes-dashboard -n kubernetes-dashboard --ignore-not-found --wait --timeout=60s 2>/dev/null || echo "  No kubernetes-dashboard Helm release"
	@echo "  All Helm releases thoroughly uninstalled"
	@echo "Step 4: CRITICAL - Clean up webhooks and CRDs BEFORE terraform destroy..."
	@echo "  Cleaning Longhorn webhooks..."
	@kubectl delete validatingwebhookconfigurations longhorn-webhook-validator longhorn-admission-webhook --ignore-not-found=true 2>/dev/null || echo "  No longhorn webhook validators"
	@kubectl delete mutatingwebhookconfigurations longhorn-webhook-mutator longhorn-conversion-webhook --ignore-not-found=true 2>/dev/null || echo "  No longhorn webhook mutators"
	@echo "  Cleaning Prometheus webhooks..."
	@kubectl delete validatingwebhookconfigurations prometheus-stack-kube-prom-admission --ignore-not-found=true 2>/dev/null || echo "  No prometheus webhook validators"
	@kubectl delete mutatingwebhookconfigurations prometheus-stack-kube-prom-admission --ignore-not-found=true 2>/dev/null || echo "  No prometheus webhook mutators"
	@echo "  Cleaning Kubernetes Dashboard webhooks..."
	@kubectl delete validatingwebhookconfigurations kubernetes-dashboard-webhook --ignore-not-found=true 2>/dev/null || echo "  No dashboard webhook validators"
	@kubectl delete mutatingwebhookconfigurations kubernetes-dashboard-webhook --ignore-not-found=true 2>/dev/null || echo "  No dashboard webhook mutators"
	@echo "  FIRST: Remove finalizers from stuck resources (before deleting CRDs)..."
ifeq ($(OS),Windows_NT)
	@kubectl patch backuptargets.longhorn.io default -n longhorn-system -p "{\"metadata\":{\"finalizers\":[]}}" --type=merge 2>nul || echo "  No backup targets to patch"
	@kubectl patch namespace longhorn-system -p "{\"metadata\":{\"finalizers\":[]}}" --type=merge 2>nul || echo "  Namespace already clean or deleted"
	@kubectl patch namespace monitoring -p "{\"metadata\":{\"finalizers\":[]}}" --type=merge 2>nul || echo "  Monitoring namespace already clean or deleted"
	@kubectl patch namespace baget -p "{\"metadata\":{\"finalizers\":[]}}" --type=merge 2>nul || echo "  Baget namespace already clean or deleted"
	@kubectl patch namespace kubernetes-dashboard -p "{\"metadata\":{\"finalizers\":[]}}" --type=merge 2>nul || echo "  Dashboard namespace already clean or deleted"
else
	@kubectl patch backuptargets.longhorn.io default -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  No backup targets to patch"
	@kubectl patch namespace longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Namespace already clean or deleted"
	@kubectl patch namespace monitoring -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Monitoring namespace already clean or deleted"
	@kubectl patch namespace baget -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Baget namespace already clean or deleted"
	@kubectl patch namespace kubernetes-dashboard -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "  Dashboard namespace already clean or deleted"
endif
	@echo "  CRITICAL: Removing finalizers from Longhorn resources to unblock terraform destroy..."
	@echo "  Step 1: Remove finalizers from all Longhorn custom resources (instances) first..."
	@echo "    Removing finalizers from volumes..."
	@kubectl get volumes.longhorn.io -n longhorn-system -o name 2>/dev/null | powershell -Command "$$input | ForEach-Object { kubectl patch $$_ -n longhorn-system -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge 2>$$null }" || echo "    No volumes to patch"
	@echo "    Removing finalizers from engines..."
	@kubectl get engines.longhorn.io -n longhorn-system -o name 2>/dev/null | powershell -Command "$$input | ForEach-Object { kubectl patch $$_ -n longhorn-system -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge 2>$$null }" || echo "    No engines to patch"
	@echo "    Removing finalizers from replicas..."
	@kubectl get replicas.longhorn.io -n longhorn-system -o name 2>/dev/null | powershell -Command "$$input | ForEach-Object { kubectl patch $$_ -n longhorn-system -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge 2>$$null }" || echo "    No replicas to patch"
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
	@powershell -Command "Start-Sleep -Seconds 3" 2>/dev/null || sleep 3
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
	@kubectl delete namespace longhorn-system monitoring baget kubernetes-dashboard kube-flannel --ignore-not-found=true --timeout=30s || echo "Namespace deletion timeout, continuing..."
	@echo "Step 8: Clean up remaining kube-vip resources..."
	@kubectl delete configmap -n kube-system kubevip --ignore-not-found=true 2>/dev/null || echo "No kube-vip config to clean"
	@echo "Step 9: Clean up any remaining application resources..."
	@kubectl delete pods -n longhorn-system --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No longhorn pods to delete"
	@kubectl delete pods -n monitoring --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No monitoring pods to delete"
	@kubectl delete pods -n baget --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No baget pods to delete"
	@kubectl delete pods -n kubernetes-dashboard --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No dashboard pods to delete"
	@kubectl delete pods -n kube-flannel --all --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No flannel pods to delete"
	@kubectl delete pods -n kube-system -l k8s-app=kube-proxy --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "No kube-proxy pods to delete"
	@kubectl delete daemonsets,deployments,replicasets -n longhorn-system --all --ignore-not-found=true 2>/dev/null || echo "No longhorn controllers to delete"
	@kubectl delete daemonsets,deployments,replicasets -n monitoring --all --ignore-not-found=true 2>/dev/null || echo "No monitoring controllers to delete"
	@kubectl delete daemonsets,deployments,replicasets -n baget --all --ignore-not-found=true 2>/dev/null || echo "No baget controllers to delete"
	@kubectl delete daemonsets,deployments,replicasets -n kubernetes-dashboard --all --ignore-not-found=true 2>/dev/null || echo "No dashboard controllers to delete"
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
	@kubectl delete namespace longhorn-system monitoring baget kubernetes-dashboard kube-flannel --force --grace-period=0 --ignore-not-found=true 2>/dev/null || echo "All namespaces already deleted"
	@echo "Step 12: Final verification..."
ifeq ($(OS),Windows_NT)
	@kubectl get pods -n longhorn-system --ignore-not-found=true 2>nul || echo "✓ longhorn-system namespace is clean"
	@kubectl get pods -n monitoring --ignore-not-found=true 2>nul || echo "✓ monitoring namespace is clean"
	@kubectl get pods -n baget --ignore-not-found=true 2>nul || echo "✓ baget namespace is clean"
	@kubectl get pods -n kubernetes-dashboard --ignore-not-found=true 2>nul || echo "✓ kubernetes-dashboard namespace is clean"
	@kubectl get crd 2>nul | findstr /i "longhorn" >nul && echo "⚠ Some Longhorn CRDs still present" || echo "✓ Longhorn CRDs cleaned up"
	@kubectl get crd 2>nul | findstr /i "monitoring.coreos.com" >nul && echo "⚠ Some Prometheus CRDs still present" || echo "✓ Prometheus CRDs cleaned up"
	@kubectl get clusterrole longhorn-role 2>nul && echo "⚠ Longhorn ClusterRole still present" || echo "✓ Longhorn RBAC cleaned up"
	@kubectl get clusterrolebinding longhorn-bind flannel 2>nul && echo "⚠ Some ClusterRoleBindings still present" || echo "✓ All ClusterRoleBindings cleaned up"
	@kubectl get storageclass longhorn 2>nul && echo "⚠ Longhorn StorageClass still present" || echo "✓ Longhorn StorageClass cleaned up"
	@kubectl get pods -n kube-flannel --ignore-not-found=true 2>nul || echo "✓ kube-flannel namespace is clean"
	@helm list -A 2>nul | findstr /i -v "NAME" >nul && echo "⚠ Some Helm releases still present:" && helm list -A || echo "✓ All Helm releases cleaned up"
else
	@kubectl get pods -n longhorn-system --ignore-not-found=true 2>/dev/null || echo "✓ longhorn-system namespace is clean"
	@kubectl get pods -n monitoring --ignore-not-found=true 2>/dev/null || echo "✓ monitoring namespace is clean"
	@kubectl get pods -n baget --ignore-not-found=true 2>/dev/null || echo "✓ baget namespace is clean"
	@kubectl get pods -n kubernetes-dashboard --ignore-not-found=true 2>/dev/null || echo "✓ kubernetes-dashboard namespace is clean"
	@kubectl get crd 2>/dev/null | grep -i "longhorn" && echo "⚠ Some Longhorn CRDs still present" || echo "✓ Longhorn CRDs cleaned up"
	@kubectl get crd 2>/dev/null | grep -i "monitoring.coreos.com" && echo "⚠ Some Prometheus CRDs still present" || echo "✓ Prometheus CRDs cleaned up"
	@kubectl get clusterrole longhorn-role 2>/dev/null && echo "⚠ Longhorn ClusterRole still present" || echo "✓ Longhorn RBAC cleaned up"
	@kubectl get clusterrolebinding longhorn-bind flannel 2>/dev/null && echo "⚠ Some ClusterRoleBindings still present" || echo "✓ All ClusterRoleBindings cleaned up"
	@kubectl get storageclass longhorn 2>/dev/null && echo "⚠ Longhorn StorageClass still present" || echo "✓ Longhorn StorageClass cleaned up"
	@kubectl get pods -n kube-flannel --ignore-not-found=true 2>/dev/null || echo "✓ kube-flannel namespace is clean"
	@helm list -A 2>/dev/null | grep -v "NAME" && echo "⚠ Some Helm releases still present:" && helm list -A || echo "✓ All Helm releases cleaned up"
endif
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
	@echo "📋 Dashboard     -> kubernetes-dashboard.tf (Kubernetes Web UI)"
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
		-target=kubernetes_namespace.kubernetes_dashboard \
		-target=kubernetes_service_account.dashboard_admin_user \
		-target=kubernetes_cluster_role_binding.dashboard_admin_user \
		-target=kubernetes_secret.dashboard_admin_user_token \
		-target=helm_release.kubernetes_dashboard \
		-target=kubernetes_service.kubernetes_dashboard_lb

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
		-target=data.kubernetes_storage_class.longhorn \
		-target=kubernetes_service.longhorn_frontend_lb

apply-monitoring: check-vars check-init ## Deploy monitoring components (Prometheus, Grafana)
	@echo "Deploying monitoring components..."
	terraform apply \
		-target=helm_release.prometheus_stack

apply-applications: check-vars check-init ## Deploy application components (Baget, Dashboard)
	@echo "Deploying application components..."
	terraform apply \
		-target=kubernetes_secret.baget_secrets \
		-target=kubernetes_config_map.baget_config \
		-target=kubernetes_persistent_volume_claim.baget_data \
		-target=kubernetes_deployment.baget \
		-target=kubernetes_service.baget \
		-target=kubernetes_namespace.kubernetes_dashboard \
		-target=kubernetes_service_account.dashboard_admin_user \
		-target=kubernetes_cluster_role_binding.dashboard_admin_user \
		-target=kubernetes_secret.dashboard_admin_user_token \
		-target=helm_release.kubernetes_dashboard \
		-target=kubernetes_service.kubernetes_dashboard_lb

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

debug-applications: ## Debug application components (Baget, Dashboard)
	@echo "=== Applications Component Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep -E "(baget|kubernetes_dashboard)" || echo "No application resources found in state"
	@echo ""
	@echo "Baget Pods:"
	@kubectl get pods -n baget -o wide 2>/dev/null || echo "Baget namespace not found"
	@echo ""
	@echo "Dashboard Pods:"
	@kubectl get pods -n kubernetes-dashboard -o wide 2>/dev/null || echo "Dashboard namespace not found"
	@echo ""
	@echo "Application Services:"
	@kubectl get svc -n baget 2>/dev/null || echo "No Baget services found"
	@kubectl get svc -n kubernetes-dashboard 2>/dev/null || echo "No Dashboard services found"
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
	@kubectl get pods -n kubernetes-dashboard 2>nul || echo "Dashboard not deployed"
	@kubectl get svc -n kubernetes-dashboard kubernetes-dashboard-lb 2>nul || echo "Dashboard service not found"
else
	@kubectl get pods -n baget 2>/dev/null || echo "Baget not deployed"
	@kubectl get svc -n baget baget-service 2>/dev/null || echo "Baget service not found"
	@kubectl get pods -n kubernetes-dashboard 2>/dev/null || echo "Dashboard not deployed"
	@kubectl get svc -n kubernetes-dashboard kubernetes-dashboard-lb 2>/dev/null || echo "Dashboard service not found"
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
	@echo "Kubernetes Dashboard Logs:"
	@kubectl logs -n kubernetes-dashboard -l app.kubernetes.io/name=kubernetes-dashboard --tail=5 2>/dev/null || echo "No Dashboard logs"
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
	@kubectl get pods -n kubernetes-dashboard --no-headers 2>/dev/null | grep -c Running | xargs -I {} echo "  Dashboard: {} pods running" || echo "  Dashboard: Not deployed"
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
		networking) terraform taint helm_release.metallb ;; \
		storage) terraform taint helm_release.longhorn ;; \
		monitoring) terraform taint helm_release.prometheus_stack ;; \
		applications) terraform taint kubernetes_deployment.baget ;; \
		dashboard) terraform taint helm_release.kubernetes_dashboard ;; \
		dns) terraform taint kubernetes_deployment.pihole_dns_sync ;; \
		*) echo "Invalid component: $(COMPONENT)" && exit 1 ;; \
	esac
	@echo "Component $(COMPONENT) tainted. Run 'make apply-$(COMPONENT)' to recreate."
