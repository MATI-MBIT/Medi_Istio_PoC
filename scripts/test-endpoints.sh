#!/bin/bash

# Test script for microservice endpoints
set -e

GATEWAY_URL="http://localhost:8080"

echo "🧪 Testing microservice endpoints..."
echo "Gateway URL: $GATEWAY_URL"
echo ""

# Test ping endpoint
echo "1. Testing GET /v1/ping"
response=$(curl -s -w "\n%{http_code}" "$GATEWAY_URL/v1/ping")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" = "200" ]; then
    echo "✅ Ping successful: $body"
else
    echo "❌ Ping failed with code: $http_code"
fi

echo ""

# Test purchase endpoint
echo "2. Testing POST /v1/purchase"
purchase_data='{"item":"test-product","amount":99.99}'
response=$(curl -s -w "\n%{http_code}" -X POST "$GATEWAY_URL/v1/purchase" \
    -H "Content-Type: application/json" \
    -d "$purchase_data")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" = "200" ]; then
    echo "✅ Purchase successful:"
    echo "$body" | jq '.' 2>/dev/null || echo "$body"
else
    echo "❌ Purchase failed with code: $http_code"
    echo "Response: $body"
fi

echo ""

# Generate some load for testing
echo "3. Generating test load (10 requests)..."
for i in {1..10}; do
    curl -s "$GATEWAY_URL/v1/ping" > /dev/null &
    curl -s -X POST "$GATEWAY_URL/v1/purchase" \
        -H "Content-Type: application/json" \
        -d '{"item":"load-test-'$i'","amount":'$((RANDOM % 100))'}' > /dev/null &
done

wait
echo "✅ Load test completed"

echo ""
echo "🔍 Check the following UIs:"
echo "- Grafana: http://localhost:3000 (admin/admin)"
echo "- Zipkin: http://localhost:9411"
echo "- Prometheus: http://localhost:9090"