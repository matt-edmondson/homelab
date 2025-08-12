.PHONY: help init plan apply destroy validate format lint check-vars status clean

# Default target
help: ## Show this help message
	@echo "Kubernetes Homelab Terraform Management"
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize Terraform
	terraform init

plan: check-vars ## Plan Terraform deployment
	terraform plan

apply: check-vars ## Apply Terraform configuration
	terraform apply

destroy: check-vars ## Destroy Terraform infrastructure
	terraform destroy

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
	@echo "=== Terraform State ==="
	terraform state list 2>/dev/null || echo "No state found (not initialized or no resources)"
	@echo ""
	@echo "=== Kubernetes Pods ==="
	kubectl get pods --all-namespaces 2>/dev/null || echo "Cannot connect to Kubernetes cluster"
	@echo ""
	@echo "=== LoadBalancer Services ==="
	kubectl get services --all-namespaces | grep LoadBalancer 2>/dev/null || echo "No LoadBalancer services found"

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

# Generate secure credentials
generate-secrets: ## Generate secure passwords for terraform.tfvars
	@echo "Generating secure credentials..."
	@echo ""
	@echo "# Generated credentials - add to your terraform.tfvars file:"
	@echo "baget_api_key = \"$$(openssl rand -base64 32)\""
	@echo "grafana_admin_password = \"$$(openssl rand -base64 16)\""
	@echo ""
	@echo "Save these credentials securely!"

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

logs: ## Show logs for all deployed applications
	@echo "=== MetalLB Logs ==="
	kubectl logs -n metallb-system -l app=metallb --tail=10
	@echo ""
	@echo "=== Longhorn Logs ==="
	kubectl logs -n longhorn-system -l app=longhorn-manager --tail=10
	@echo ""
	@echo "=== Prometheus Logs ==="
	kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=10
	@echo ""
	@echo "=== Grafana Logs ==="
	kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=10
	@echo ""
	@echo "=== Baget Logs ==="
	kubectl logs -n baget -l app=baget --tail=10

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
