#!/bin/bash

# Script para configurar telemetría en Istio después de la instalación
set -e

NAMESPACE=${1:-medi}

echo "🔧 Configurando telemetría de Istio para namespace: $NAMESPACE"

# Verificar que Istio está instalado
if ! kubectl get namespace istio-system > /dev/null 2>&1; then
    echo "❌ Istio no está instalado. Ejecuta 'make install-istio' primero."
    exit 1
fi

# Verificar que el namespace existe
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
    echo "❌ Namespace $NAMESPACE no existe."
    exit 1
fi

# Verificar que los servicios necesarios están desplegados
echo "� Vernificando servicios necesarios..."
kubectl wait --for=condition=available deployment/otel-collector -n $NAMESPACE --timeout=60s || echo "⚠️ otel-collector no está listo"
kubectl wait --for=condition=available deployment/zipkin -n $NAMESPACE --timeout=60s || echo "⚠️ zipkin no está listo"

# Reiniciar pods para aplicar configuración de Istio
echo "🔄 Reiniciando pods para aplicar configuración de telemetría..."
kubectl rollout restart deployment/go-microservice -n $NAMESPACE
kubectl rollout status deployment/go-microservice -n $NAMESPACE --timeout=300s

echo "✅ Configuración de telemetría aplicada correctamente"
echo "📊 Verificando configuración..."

# Verificar que los pods están corriendo
kubectl get pods -n $NAMESPACE
echo ""
echo "🔍 Para verificar trazas, accede a:"
echo "  - Zipkin: kubectl port-forward -n $NAMESPACE svc/zipkin 9411:9411"
echo "  - Grafana: kubectl port-forward -n $NAMESPACE svc/grafana 3000:3000"
echo "  - Prometheus: kubectl port-forward -n $NAMESPACE svc/prometheus 9090:9090"