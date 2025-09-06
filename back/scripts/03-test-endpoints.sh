#!/bin/bash
set -e

echo "🧪 Testing Go Microservice endpoints with observability..."

# Setup port forwarding for Istio Gateway
echo "🌐 Setting up port forwarding..."
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &
GATEWAY_PID=$!

# Setup port forwarding for observability tools
kubectl port-forward -n go-service-obs svc/grafana 3000:3000 &
GRAFANA_PID=$!
kubectl port-forward -n go-service-obs svc/prometheus 9090:9090 &
PROMETHEUS_PID=$!
kubectl port-forward -n go-service-obs svc/jaeger-ui 16686:16686 &
JAEGER_PID=$!

sleep 10

echo "📡 Testing endpoints..."

# Test ping endpoint
echo ""
echo "🏓 Testing GET /v1/ping..."
for i in {1..5}; do
  curl -w "\nStatus: %{http_code} | Time: %{time_total}s\n" \
    "http://localhost:8080/v1/ping"
  sleep 1
done

echo ""
echo "💰 Testing POST /v1/purchase..."
for i in {1..5}; do
  curl -X POST \
    -H "Content-Type: application/json" \
    -d "{\"item\": \"product-$i\", \"quantity\": $i, \"price\": $(echo $i*10.99 | bc)}" \
    -w "\nStatus: %{http_code} | Time: %{time_total}s\n" \
    "http://localhost:8080/v1/purchase"
  sleep 2
done

echo ""
echo "✅ Endpoint testing completed!"
echo ""
echo "📊 Observability URLs:"
echo "Grafana: http://localhost:3000 (admin/admin123)"
echo "Prometheus: http://localhost:9090"
echo "Jaeger: http://localhost:16686"
echo ""
echo "🔍 Check the dashboards for real-time metrics and traces!"

# Cleanup function
cleanup() {
  echo "🧹 Cleaning up port forwards..."
  kill $GATEWAY_PID $GRAFANA_PID $PROMETHEUS_PID $JAEGER_PID 2>/dev/null || true
}

trap cleanup EXIT

# Keep running for observation
echo "Press Ctrl+C to stop port forwarding and exit..."
wait