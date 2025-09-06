#!/bin/bash
set -e

echo "🔨 Building Go microservice with OpenTelemetry instrumentation locally..."

# Build the Docker image locally
docker build -t go-microservice:otel-local .

echo "✅ Local build completed!"
echo "📝 Image built as: go-microservice:otel-local"
echo "🚀 Ready to deploy to Kubernetes with local image"