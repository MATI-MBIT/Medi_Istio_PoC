#!/bin/bash

# Script optimizado para configurar telemetría en Istio
set -e

NAMESPACE=${1:-medi}
TIMEOUT=60s

echo "🔧 Configurando telemetría de Istio para namespace: $NAMESPACE"

# Función para verificar prerequisitos
check_prerequisites() {
    if ! kubectl get namespace istio-system > /dev/null 2>&1; then
        echo "❌ Istio no está instalado"
        exit 1
    fi
    
    if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
        echo "❌ Namespace $NAMESPACE no existe"
        exit 1
    fi
}

# Función para esperar servicios
wait_for_services() {
    echo "⏳ Esperando servicios de telemetría..."
    
    local services=("otel-collector" "zipkin")
    for service in "${services[@]}"; do
        if kubectl get deployment/$service -n $NAMESPACE > /dev/null 2>&1; then
            kubectl wait --for=condition=available deployment/$service -n $NAMESPACE --timeout=$TIMEOUT || \
                echo "⚠️ $service no está completamente listo, continuando..."
        fi
    done
}

# Función para reiniciar aplicación
restart_application() {
    echo "🔄 Aplicando configuración de telemetría..."
    if kubectl get deployment/go-microservice -n $NAMESPACE > /dev/null 2>&1; then
        kubectl rollout restart deployment/go-microservice -n $NAMESPACE
        kubectl rollout status deployment/go-microservice -n $NAMESPACE --timeout=300s
    fi
}

# Función principal
main() {
    check_prerequisites
    wait_for_services
    restart_application
    
    echo "✅ Configuración de telemetría aplicada"
    echo "📊 Estado actual:"
    kubectl get pods -n $NAMESPACE --no-headers | grep -E "(Running|Ready)" | wc -l | xargs echo "Pods listos:"
}

main "$@"