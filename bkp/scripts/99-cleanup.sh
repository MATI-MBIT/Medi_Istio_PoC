#!/bin/bash
set -e

echo "🧹 Cleaning up Go Microservice Observability Stack..."

# Delete Istio resources
echo "🌐 Removing Istio resources..."
kubectl delete -f istio/ --ignore-not-found=true

# Delete Go microservice
echo "🔧 Removing Go microservice..."
kubectl delete -f k8s/02-deployment.yaml --ignore-not-found=true
kubectl delete -f k8s/03-service.yaml --ignore-not-found=true

# Delete observability stack
echo "📊 Removing observability components..."
kubectl delete -f observability/05-grafana/ --ignore-not-found=true
kubectl delete -f observability/04-jaeger/ --ignore-not-found=true
kubectl delete -f observability/03-loki/ --ignore-not-found=true
kubectl delete -f observability/02-prometheus/ --ignore-not-found=true
kubectl delete -f observability/01-opentelemetry/ --ignore-not-found=true

# Delete ServiceAccount and RBAC
echo "🔐 Removing ServiceAccount and RBAC..."
kubectl delete -f k8s/01-serviceaccount.yaml --ignore-not-found=true

# Delete namespace (this will remove everything in it)
echo "📦 Removing namespace..."
kubectl delete -f k8s/00-namespace.yaml --ignore-not-found=true

echo "✅ Cleanup completed!"
echo ""
echo "All resources have been removed from the cluster."