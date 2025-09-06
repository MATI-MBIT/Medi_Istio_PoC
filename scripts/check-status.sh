#!/bin/bash

# Status check script
set -e

NAMESPACE="medi"

echo "🔍 Checking deployment status..."
echo ""

# Check namespace
echo "📁 Namespace:"
kubectl get namespace $NAMESPACE 2>/dev/null || echo "❌ Namespace $NAMESPACE not found"
echo ""

# Check Istio installation
echo "🕸️  Istio:"
kubectl get pods -n istio-system 2>/dev/null | head -5 || echo "❌ Istio not installed"
echo ""

# Check pods in medi namespace
echo "🚀 Pods in $NAMESPACE:"
kubectl get pods -n $NAMESPACE -o wide 2>/dev/null || echo "❌ No pods in $NAMESPACE"
echo ""

# Check services
echo "🌐 Services in $NAMESPACE:"
kubectl get svc -n $NAMESPACE 2>/dev/null || echo "❌ No services in $NAMESPACE"
echo ""

# Check Istio configurations
echo "⚙️  Istio Configurations:"
echo "Gateways:"
kubectl get gateway -n $NAMESPACE 2>/dev/null || echo "❌ No gateways"
echo "VirtualServices:"
kubectl get virtualservice -n $NAMESPACE 2>/dev/null || echo "❌ No virtual services"
echo "DestinationRules:"
kubectl get destinationrule -n $NAMESPACE 2>/dev/null || echo "❌ No destination rules"
echo ""

# Check if port-forwards are running
echo "🔌 Port Forwards:"
ps aux | grep "kubectl port-forward" | grep -v grep || echo "❌ No port forwards running"
echo ""

echo "✅ Status check completed"