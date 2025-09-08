.PHONY: help check install deploy status test cleanup port-forward

# Variables
NAMESPACE := medi
ISTIO_VERSION := 1.26.2
TIMEOUT := 300s

# Colors for output
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
BLUE := \033[34m
NC := \033[0m

help: ## Show available commands
	@echo "$(BLUE)Medi Istio PoC - Available Commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

# === PREREQUISITES ===
check: ## Check prerequisites and cluster status
	@echo "$(YELLOW)🔍 Checking prerequisites...$(NC)"
	@./scripts/pre-deploy-check.sh

# === INSTALLATION ===
install: check ## Install Istio with native addons configuration
	@echo "$(YELLOW)📦 Installing Istio $(ISTIO_VERSION)...$(NC)"
	@istioctl install --set values.defaultRevision=default \
		--set meshConfig.defaultConfig.tracing.sampling=10.0 \
		--set values.pilot.traceSampling=10.0 -y
	@kubectl label namespace default istio-injection=enabled --overwrite
	@echo "$(GREEN)✅ Istio installed successfully$(NC)"

# === DEPLOYMENT ===
deploy: install _create-namespace _deploy-stack _configure-telemetry ## Deploy complete stack
	@echo "$(GREEN)🎉 Complete deployment finished!$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  • Run 'make status' to check deployment"
	@echo "  • Run 'make port-forward' to access UIs"
	@echo "  • Run 'make test' to verify functionality"

_create-namespace:
	@echo "$(YELLOW)📁 Setting up namespace $(NAMESPACE)...$(NC)"
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl label namespace $(NAMESPACE) istio-injection=enabled --overwrite

_deploy-stack: _create-namespace
	@echo "$(YELLOW)🚀 Deploying application stack...$(NC)"
	@kubectl apply -f k8s/ -n $(NAMESPACE)
	@kubectl apply -f k8s/manifests/ -n $(NAMESPACE)
	@kubectl apply -f istio/01-gateway.yaml -n $(NAMESPACE)
	@kubectl apply -f istio/02-virtualservice.yaml -n $(NAMESPACE)
	@kubectl apply -f istio/04-peerauthentication.yaml -n $(NAMESPACE)
	@kubectl apply -f istio/05-telemetry.yaml -n $(NAMESPACE)
	@kubectl apply -f istio/06-tracing-config.yaml -n istio-system
	@echo "$(YELLOW)⏳ Waiting for pods to be ready...$(NC)"
	@kubectl wait --for=condition=ready pod -l app=product-service -n $(NAMESPACE) --timeout=$(TIMEOUT) || true
	@kubectl wait --for=condition=ready pod -l app=purchase-plan-service -n $(NAMESPACE) --timeout=$(TIMEOUT) || true
	@echo "$(YELLOW)⏳ Verificando addons de Istio...$(NC)"
	@kubectl wait --for=condition=ready pod -l app=prometheus -n istio-system --timeout=$(TIMEOUT) || true
	@kubectl wait --for=condition=ready pod -l app=grafana -n istio-system --timeout=$(TIMEOUT) || true
	@kubectl wait --for=condition=ready pod -l app=jaeger -n istio-system --timeout=$(TIMEOUT) || true
	@kubectl wait --for=condition=ready pod -l app=kiali -n istio-system --timeout=$(TIMEOUT) || true

_configure-telemetry:
	@echo "$(YELLOW)🔧 Configuring telemetry...$(NC)"
	@./scripts/configure-istio-telemetry.sh $(NAMESPACE)

# === STATUS & MONITORING ===
status: ## Show deployment status
	@echo "$(BLUE)=== Cluster Status ===$(NC)"
	@kubectl get nodes --no-headers | wc -l | xargs echo "Nodes:"
	@echo ""
	@echo "$(BLUE)=== Namespace $(NAMESPACE) Status ===$(NC)"
	@kubectl get pods -n $(NAMESPACE) -o wide
	@echo ""
	@echo "$(BLUE)=== Services ===$(NC)"
	@kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "$(BLUE)=== Istio Resources ===$(NC)"
	@kubectl get gateway,virtualservice,destinationrule -n $(NAMESPACE) 2>/dev/null || echo "No Istio resources found"

port-forward: ## Start port forwarding for all UIs
	@echo "$(GREEN)🌐 Starting port forwarding...$(NC)"
	@echo "$(BLUE)Available UIs (Istio Addons):$(NC)"
	@echo "  • Grafana:     http://localhost:3000 (admin/admin)"
	@echo "  • Jaeger:      http://localhost:16686"
	@echo "  • Prometheus:  http://localhost:9090"
	@echo "  • Kiali:       http://localhost:20001"
	@echo "  • Loki:        http://localhost:3100"
	@echo ""
	@echo "$(BLUE)Available Services (via Ingress Gateway):$(NC)"
	@echo "  • Go Microservice:     http://localhost:8080/v1/"
	@echo "  • Product Service:     http://localhost:8080/api/products/"
	@echo "  • Purchase Plan:       http://localhost:8080/api/purchase-plan/"
	@echo "  • Health Checks:"
	@echo "    - Products:          http://localhost:8080/health/products"
	@echo "    - Purchase Plan:     http://localhost:8080/health/purchase-plan"
	@echo ""
	@echo "$(YELLOW)Press Ctrl+C to stop all port forwards$(NC)"
	@echo ""
	@echo "$(GREEN)🚀 Starting port forwards...$(NC)"
	@kubectl port-forward -n istio-system svc/grafana 3000:3000 & \
	kubectl port-forward -n istio-system svc/prometheus 9090:9090 & \
	kubectl port-forward -n istio-system svc/loki 3100:3100 & \
	kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 & \
	@echo ""
	@echo "$(GREEN)✅ All services are now accessible:$(NC)"
	@echo ""
	@echo "$(BLUE)📊 Observability UIs:$(NC)"
	@echo "  🔍 Grafana:    http://localhost:3000 (admin/admin)"
	@echo "  🔍 Jaeger:     http://localhost:16686/jaeger/search"
	@echo "  🔍 Prometheus: http://localhost:9090"
	@echo "  🔍 Kiali:      http://localhost:20001"
	@echo "  🔍 Loki:       http://localhost:3100"
	@echo ""
	@echo "$(BLUE)🚀 Application Services:$(NC)"
	@echo "  � Product sService:  http://localhost:8080/api/products/"
	@echo "  � Purchcase Plan:    http://localhost:8080/api/purchase-plan/"
	@echo ""
	@echo "$(BLUE)🏥 Health Checks:$(NC)"
	@echo "  ✅ Products:         http://localhost:8080/health/products"
	@echo "  ✅ Purchase Plan:    http://localhost:8080/health/purchase-plan"
	@echo ""
	wait

# === TESTING ===
test: ## Run comprehensive tests
	@echo "$(YELLOW)🧪 Running tests...$(NC)"
	@./scripts/test-telemetry.sh $(NAMESPACE)

test-quick: ## Run quick endpoint tests
	@echo "$(YELLOW)⚡ Quick endpoint tests via Ingress Gateway...$(NC)"
	@echo "Testing product-service health via gateway:"
	@curl -sf http://localhost:8080/health/products && echo "$(GREEN)✅ Product Service Health OK$(NC)" || echo "$(RED)❌ Product Service Health failed$(NC)"
	@echo "Testing purchase-plan-service health via gateway:"
	@curl -sf http://localhost:8080/health/purchase-plan && echo "$(GREEN)✅ Purchase Plan Service Health OK$(NC)" || echo "$(RED)❌ Purchase Plan Service Health failed$(NC)"

# === CLEANUP ===
cleanup: stop-port-forwards ## Clean up namespace and resources
	@echo "$(YELLOW)🧹 Cleaning up namespace $(NAMESPACE)...$(NC)"
	@kubectl delete namespace $(NAMESPACE) --ignore-not-found=true --timeout=60s
	@echo "$(GREEN)✅ Namespace $(NAMESPACE) deleted$(NC)"
	@echo "$(BLUE)💡 To remove Istio completely: make cleanup-istio$(NC)"

cleanup-istio: ## Remove Istio completely
	@echo "$(YELLOW)🧹 Removing Istio completely...$(NC)"
	@istioctl uninstall --purge -y || echo "$(YELLOW)⚠️ Istio may not be installed$(NC)"
	@kubectl delete namespace istio-system --ignore-not-found=true --timeout=60s
	@echo "$(GREEN)✅ Istio removed completely$(NC)"

cleanup-all: cleanup cleanup-istio ## Remove everything (namespace + Istio)
	@echo "$(GREEN)🎉 Complete cleanup finished!$(NC)"

stop-port-forwards: ## Stop all kubectl port-forward processes
	@echo "$(YELLOW)🛑 Stopping port forwards...$(NC)"
	@pkill -f "kubectl port-forward" 2>/dev/null || echo "$(BLUE)ℹ️ No port forwards running$(NC)"
	@echo "$(GREEN)✅ Port forwards stopped$(NC)"

# === UTILITIES ===
logs: ## Show logs from all pods
	@echo "$(BLUE)=== Recent logs from all pods ===$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app=product-service --tail=20 --prefix=true || true
	@kubectl logs -n $(NAMESPACE) -l app=purchase-plan-service --tail=20 --prefix=true || true
	@kubectl logs -n $(NAMESPACE) -l app=otel-collector --tail=10 --prefix=true || true

restart: ## Restart application pods
	@echo "$(YELLOW)🔄 Restarting application pods...$(NC)"
	@kubectl rollout restart deployment/product-service -n $(NAMESPACE)
	@kubectl rollout restart deployment/purchase-plan-service -n $(NAMESPACE)
	@kubectl rollout status deployment/product-service -n $(NAMESPACE) --timeout=$(TIMEOUT)
	@kubectl rollout status deployment/purchase-plan-service -n $(NAMESPACE) --timeout=$(TIMEOUT)