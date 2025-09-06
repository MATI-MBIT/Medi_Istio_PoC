#!/bin/bash
set -e

echo "🔨 Building Go microservice with OpenTelemetry instrumentation..."

# Build the Docker image
docker build -t aira18/go-microservice:otel-latest .

echo "📤 Pushing to DockerHub..."
docker push aira18/go-microservice:otel-latest

echo "✅ Build and push completed!"
echo "📝 Update your Kubernetes deployment to use: aira18/go-microservice:otel-latest"