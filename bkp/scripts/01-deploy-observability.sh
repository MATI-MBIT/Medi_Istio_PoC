#!/bin/bash
set -e

echo "🚀 Deploying Complete Observability Stack..."

# Create namespace
echo "📦 Creating namespace..."
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-serviceaccount.yaml

# Deploy observability components in order
echo "🔍 Deploying OpenTelemetry Collector..."
kubectl apply -f observability/01-opentelemetry/

echo "📈 Deploying Prometheus..."
kubectl apply -f observability/02-prometheus/

echo "📝 Deploying Loki..."
kubectl apply -f observability/03-loki/

echo "🔎 Deploying Jaeger..."
kubectl apply -f observability/04-jaeger/

echo "📊 Deploying Grafana..."
kubectl apply -f observability/05-grafana/

# Wait for all components to be ready
echo "⏳ Waiting for observability stack to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/otel-collector -n go-service-obs
kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n go-service-obs
kubectl wait --for=condition=available --timeout=300s deployment/loki -n go-service-obs
kubectl wait --for=condition=available --timeout=300s deployment/jaeger -n go-service-obs
kubectl wait --for=condition=available --timeout=300s deployment/grafana -n go-service-obs

echo "✅ Observability stack deployed successfully!"

# Show status
echo "📊 Observability Stack Status:"
kubectl get pods -n go-service-obs -l app=otel-collector
kubectl get pods -n go-service-obs -l app=prometheus
kubectl get pods -n go-service-obs -l app=loki
kubectl get pods -n go-service-obs -l app=jaeger
kubectl get pods -n go-service-obs -l app=grafana

echo ""
echo "🔗 Access URLs (use port-forward):"
echo "Grafana: kubectl port-forward -n go-service-obs svc/grafana 3000:3000"
echo "Prometheus: kubectl port-forward -n go-service-obs svc/prometheus 9090:9090"
echo "Jaeger: kubectl port-forward -n go-service-obs svc/jaeger-ui 16686:16686"