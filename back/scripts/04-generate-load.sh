#!/bin/bash
set -e

echo "🚀 Generating load for observability testing..."

# Check if hey is installed
if ! command -v hey &> /dev/null; then
  echo "Installing hey load testing tool..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install hey
  else
    echo "Please install hey: https://github.com/rakyll/hey"
    exit 1
  fi
fi

# Setup port forwarding
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &
GATEWAY_PID=$!

sleep 5

echo "🔥 Starting load test..."

# Generate load on ping endpoint
echo "📡 Load testing /v1/ping..."
hey -n 1000 -c 10 -q 5 \
  http://localhost:8080/v1/ping &

# Generate load on purchase endpoint
echo "💰 Load testing /v1/purchase..."
hey -n 500 -c 5 -q 2 \
  -H "Content-Type: application/json" \
  -d '{"item": "load-test-product", "quantity": 1, "price": 19.99}' \
  -m POST \
  http://localhost:8080/v1/purchase &

echo "⏳ Load test running for 2 minutes..."
sleep 120

echo "✅ Load test completed!"
echo ""
echo "📊 Check Grafana dashboards for metrics:"
echo "kubectl port-forward -n go-service-obs svc/grafana 3000:3000"
echo "Then visit: http://localhost:3000"

# Cleanup
kill $GATEWAY_PID 2>/dev/null || true