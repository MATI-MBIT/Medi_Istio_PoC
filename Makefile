.PHONY: help install-istio create-namespace deploy-all status port-forward cleanup test

# Variables
NAMESPACE=medi
ISTIO_VERSION=1.26.2

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install-istio: ## Install Istio with demo profile
	@echo "Installing Istio $(ISTIO_VERSION)..."
	istioctl install --set values.defaultRevision=default \
		--set meshConfig.defaultConfig.tracing.zipkin.address=zipkin.medi.svc.cluster.local:9411 \
		--set values.pilot.traceSampling=100.0 -y
	kubectl label namespace default istio-injection=enabled --overwrite
	kubectl apply -f samples/addons

create-namespace: ## Create and label namespace
	@echo "Creating namespace $(NAMESPACE)..."
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace $(NAMESPACE) istio-injection=enabled --overwrite

deploy-monitoring: create-namespace ## Deploy monitoring stack
	@echo "Deploying monitoring stack..."
	kubectl apply -f monitoring/ -n $(NAMESPACE)
	@echo "Waiting for monitoring pods to be ready..."
	kubectl wait --for=condition=ready pod -l app=prometheus -n $(NAMESPACE) --timeout=300s
	kubectl wait --for=condition=ready pod -l app=grafana -n $(NAMESPACE) --timeout=300s

deploy-otel: create-namespace ## Deploy OpenTelemetry Collector
	@echo "Deploying OpenTelemetry Collector..."
	kubectl apply -f otel/ -n $(NAMESPACE)
	kubectl wait --for=condition=ready pod -l app=otel-collector -n $(NAMESPACE) --timeout=300s

deploy-app: create-namespace ## Deploy microservice
	@echo "Deploying microservice..."
	kubectl apply -f k8s/ -n $(NAMESPACE)
	kubectl wait --for=condition=ready pod -l app=go-microservice -n $(NAMESPACE) --timeout=300s

deploy-istio: create-namespace ## Deploy Istio configurations
	@echo "Deploying Istio configurations..."
	kubectl apply -f istio/ -n $(NAMESPACE)

deploy-all: install-istio deploy-monitoring deploy-otel deploy-app deploy-istio ## Deploy everything
	@echo "✅ All components deployed successfully!"
	@echo "Run 'make port-forward' to access UIs"

status: ## Check deployment status
	@echo "=== Namespace $(NAMESPACE) Status ==="
	kubectl get pods -n $(NAMESPACE)
	@echo ""
	@echo "=== Services ==="
	kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "=== Istio Gateway ==="
	kubectl get gateway -n $(NAMESPACE)

port-forward: ## Start port forwarding for UIs
	@echo "Starting port forwarding..."
	@echo "Grafana: http://localhost:3000"
	@echo "Zipkin: http://localhost:9411" 
	@echo "Loki: http://localhost:3100"
	@echo "Prometheus: http://localhost:9090"
	@echo "Microservice: http://localhost:8080"
	@echo ""
	@echo "Press Ctrl+C to stop all port forwards"
	kubectl port-forward -n $(NAMESPACE) svc/grafana 3000:3000 & \
	kubectl port-forward -n $(NAMESPACE) svc/zipkin 9411:9411 & \
	kubectl port-forward -n $(NAMESPACE) svc/prometheus 9090:9090 & \
	kubectl port-forward -n $(NAMESPACE) svc/loki 3100:3100 & \
	kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 & \
	wait

test: ## Run basic tests
	@echo "Testing microservice endpoints..."
	@echo "Testing ping endpoint:"
	curl -s http://localhost:8080/v1/ping || echo "❌ Ping failed"
	@echo ""
	@echo "Testing purchase endpoint:"
	curl -s -X POST http://localhost:8080/v1/purchase \
		-H "Content-Type: application/json" \
		-d '{"item":"test-item","amount":99.99}' || echo "❌ Purchase failed"

cleanup: ## Clean up all resources
	@echo "Cleaning up..."
	kubectl delete namespace $(NAMESPACE) --ignore-not-found=true
	@echo "istioctl uninstall --purge -y"
	@echo "kubectl delete namespace istio-system --ignore-not-found=true"