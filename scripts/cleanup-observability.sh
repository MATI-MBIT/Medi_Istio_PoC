#!/bin/bash

# Script para limpiar y reiniciar servicios de observabilidad nativos de Istio
# Uso: ./cleanup-observability.sh [namespace]

set -euo pipefail

NAMESPACE=${1:-medi}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🧹 Limpiando observabilidad en namespace: $NAMESPACE"

# Función para limpiar datos de Prometheus (istio-system)
cleanup_prometheus() {
    log_info "🔄 Reiniciando Prometheus para limpiar datos..."
    kubectl delete pod -l app=prometheus -n istio-system --ignore-not-found=true
    kubectl wait --for=condition=ready pod -l app=prometheus -n istio-system --timeout=120s
    log_success "✅ Prometheus reiniciado"
}

# Función para limpiar datos de Jaeger
cleanup_jaeger() {
    log_info "🔄 Reiniciando Jaeger para limpiar trazas..."
    kubectl delete pod -l app=jaeger -n istio-system --ignore-not-found=true
    kubectl wait --for=condition=ready pod -l app=jaeger -n istio-system --timeout=120s
    log_success "✅ Jaeger reiniciado"
}

# Función para reiniciar Loki (istio-system)
restart_loki() {
    log_info "🔄 Reiniciando Loki..."
    kubectl delete pod -l app=loki -n istio-system --ignore-not-found=true
    kubectl wait --for=condition=ready pod -l app=loki -n istio-system --timeout=120s
    log_success "✅ Loki reiniciado"
}

# Función para reiniciar microservicios
restart_microservices() {
    log_info "🔄 Reiniciando microservicios..."
    
    # Reiniciar todos los deployments de microservicios
    for service in product-service purchase-plan-service; do
        if kubectl get deployment $service -n $NAMESPACE >/dev/null 2>&1; then
            log_info "Reiniciando $service..."
            kubectl rollout restart deployment/$service -n $NAMESPACE
            kubectl rollout status deployment/$service -n $NAMESPACE --timeout=120s
            log_success "✅ $service reiniciado"
        else
            log_warning "⚠️ Deployment $service no encontrado"
        fi
    done
}

# Función para verificar métricas de Istio
verify_istio_metrics() {
    log_info "🔍 Verificando métricas de Istio..."
    
    # Esperar un poco para que las métricas se generen
    sleep 30
    
    # Verificar si Prometheus está recibiendo métricas de Istio
    log_info "Verificando conectividad con Prometheus..."
    kubectl port-forward -n istio-system svc/prometheus 9090:9090 &
    PF_PID=$!
    sleep 5
    
    # Verificar targets de Prometheus
    if curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job | contains("envoy")) | .health' | grep -q "up"; then
        log_success "✅ Métricas de Envoy detectadas en Prometheus"
    else
        log_warning "⚠️ Métricas de Envoy no están siendo scrapeadas"
    fi
    
    # Verificar métricas específicas de Istio
    if curl -s "http://localhost:9090/api/v1/query?query=istio_requests_total" | jq -r '.data.result | length' | grep -v "0"; then
        log_success "✅ Métricas de Istio disponibles"
    else
        log_warning "⚠️ Métricas de Istio no disponibles"
    fi
    
    kill $PF_PID 2>/dev/null || true
}

# Función principal
main() {
    log_info "🚀 Iniciando limpieza de observabilidad..."
    
    # Verificar que el namespace existe
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        log_error "❌ Namespace $NAMESPACE no existe"
        exit 1
    fi
    
    # Ejecutar limpieza
    cleanup_prometheus
    cleanup_jaeger
    restart_loki
    restart_microservices
    
    log_info "⏳ Esperando estabilización del sistema..."
    sleep 60
    
    # Verificar métricas
    verify_istio_metrics
    
    log_success "🎉 Limpieza de observabilidad completada"
    log_info "💡 Recomendaciones:"
    log_info "  • Ejecuta 'make test' para generar tráfico y métricas"
    log_info "  • Verifica Prometheus en http://localhost:9090"
    log_info "  • Verifica Jaeger en http://localhost:16686"
    log_info "  • Verifica Grafana en http://localhost:3000"
    log_info "  • Verifica Kiali en http://localhost:20001"
}

# Ejecutar función principal
main "$@"