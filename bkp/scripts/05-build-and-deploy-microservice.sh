#!/bin/bash
set -e

echo "🚀 Building and deploying Go microservice with OpenTelemetry..."

# Navigate to microservice directory
cd "$(dirname "$0")/../dummy-micro"

echo "🔨 Building Docker image locally..."
docker build -t go-microservice:otel-local .

echo "📦 Deploying to Kubernetes..."
cd ../k8s

# Apply the deployment
kubectl apply -f 02-deployment.yaml
kubectl apply -f 03-service.yaml

echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/go-microservice -n go-service-obs

echo "✅ Deployment completed!"
echo ""
echo "📊 Check the status:"
echo "kubectl get pods -n go-service-obs"
echo ""
echo "📝 View logs:"
echo "kubectl logs -n go-service-obs deployment/go-microservice --tail=20"
echo ""
echo "🧪 Test the service:"
echo "kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
echo "curl http://localhost:8080/v1/ping"