#!/bin/bash
set -e

echo "🚀 Building and deploying Go microservice with OpenTelemetry..."

# Navigate to microservice directory
cd "$(dirname "$0")/../dummy-micro"

 echo "🔨 Building Docker image locally..."
 docker build -t go-microservice:otel-local .

echo "📦 Deploying to Kubernetes..."
cd ..

echo "🚀 Deploying Go Microservice..."

# Deploy Kubernetes resources
echo "🔧 Deploying Kubernetes resources..."
kubectl apply -f k8s/01-serviceaccount.yaml
kubectl apply -f k8s/02-deployment.yaml
kubectl apply -f k8s/03-service.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for Go microservice to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/go-microservice -n go-service-obs

# Deploy Istio resources
echo "🌐 Deploying Istio resources..."
kubectl apply -f istio/

echo "✅ Go Microservice deployed successfully!"

# Show status
echo "📊 Deployment Status:"
kubectl get pods -n go-service-obs -l app=go-microservice
kubectl get svc -n go-service-obs -l app=go-microservice
kubectl get gateway -n go-service-obs
kubectl get virtualservice -n go-service-obs

echo ""
echo "🔗 Service URLs:"
echo "Health Check: http://localhost:8080/v1/ping"
echo "Purchase API: http://localhost:8080/v1/purchase"
echo ""
echo "Use port-forward to access the service:"
echo "kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"