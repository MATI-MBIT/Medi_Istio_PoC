#!/bin/bash

# Script para diagnosticar problemas de trazas en Jaeger
set -e

NAMESPACE=${1:-medi}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🔍 Diagnosticando trazas en Jaeger..."

# 1. Verificar que Jaeger está funcionando
check_jaeger_status() {
    log_step "Verificando estado de Jaeger..."
    
    if kubectl get svc tracing -n istio-system >/dev/null 2>&1; then
        local jaeger_pod=$(kubectl get pod -l app=jaeger -n istio-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "jaeger-pod-not-found")
        if [ "$jaeger_pod" != "jaeger-pod-not-found" ]; then
            local status=$(kubectl get pod $jaeger_pod -n istio-system -o jsonpath='{.status.phase}')
            log_info "Pod de Jaeger: $jaeger_pod - Estado: $status"
        else
            log_info "Servicio de tracing disponible (usando servicio 'tracing')"
        fi
        
        if [ "$status" = "Running" ]; then
            log_success "Jaeger está corriendo"
        else
            log_error "Jaeger no está corriendo correctamente"
            kubectl describe pod $jaeger_pod -n istio-system
            return 1
        fi
    else
        log_error "Jaeger no está instalado"
        return 1
    fi
}

# 2. Verificar configuración de telemetría de Istio
check_telemetry_config() {
    log_step "Verificando configuración de telemetría..."
    
    if kubectl get telemetry -n $NAMESPACE >/dev/null 2>&1; then
        log_success "Configuración de telemetría encontrada"
        kubectl get telemetry -n $NAMESPACE -o yaml
    else
        log_warning "No hay configuración de telemetría específica"
    fi
    
    # Verificar configuración global de Istio
    log_info "Configuración de tracing en Istio:"
    kubectl get configmap istio -n istio-system -o jsonpath='{.data.mesh}' | grep -A 5 -B 5 tracing || log_warning "No hay configuración de tracing"
}

# 3. Verificar sidecars de Istio en los pods
check_istio_sidecars() {
    log_step "Verificando sidecars de Istio..."
    
    local pods=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        local containers=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}')
        if echo "$containers" | grep -q "istio-proxy"; then
            log_success "$pod tiene sidecar de Istio"
            
            # Verificar configuración del proxy
            log_info "Configuración de tracing en $pod:"
            kubectl exec $pod -n $NAMESPACE -c istio-proxy -- curl -s localhost:15000/config_dump | jq '.configs[] | select(.["@type"] | contains("type.googleapis.com/envoy.config.trace")) | .tracing' 2>/dev/null || log_warning "No se pudo obtener configuración de tracing"
        else
            log_error "$pod NO tiene sidecar de Istio"
        fi
    done
}

# 4. Verificar que los servicios están enviando trazas
check_envoy_stats() {
    log_step "Verificando estadísticas de Envoy..."
    
    local pods=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        if kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}' | grep -q "istio-proxy"; then
            log_info "Estadísticas de tracing para $pod:"
            kubectl exec $pod -n $NAMESPACE -c istio-proxy -- curl -s localhost:15000/stats | grep tracing || log_warning "No hay estadísticas de tracing"
        fi
    done
}

# 5. Generar tráfico y verificar
generate_test_traffic() {
    log_step "Generando tráfico de prueba..."
    
    # Port forward del gateway
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
    local gateway_pid=$!
    sleep 3
    
    # Generar requests con headers de tracing
    for i in {1..5}; do
        log_info "Enviando request $i con headers de tracing..."
        curl -H "x-request-id: test-$i" \
             -H "x-b3-traceid: $(openssl rand -hex 16)" \
             -H "x-b3-spanid: $(openssl rand -hex 8)" \
             -H "x-b3-sampled: 1" \
             -s "http://localhost:8080/health/products" >/dev/null || log_warning "Request $i falló"
        sleep 1
    done
    
    kill $gateway_pid 2>/dev/null || true
    log_success "Tráfico de prueba generado"
}

# 6. Verificar trazas en Jaeger
check_jaeger_traces() {
    log_step "Verificando trazas en Jaeger..."
    
    kubectl port-forward -n istio-system svc/tracing 16686:16685 >/dev/null 2>&1 &
    local jaeger_pid=$!
    sleep 3
    
    # Verificar servicios disponibles
    log_info "Servicios disponibles en Jaeger:"
    curl -s "http://localhost:16686/api/services" | jq -r '.data[]' 2>/dev/null || log_warning "No se pudieron obtener servicios"
    
    # Buscar trazas recientes
    log_info "Buscando trazas recientes..."
    local traces=$(curl -s "http://localhost:16686/api/traces?limit=10&lookback=1h" | jq '.data | length' 2>/dev/null || echo "0")
    log_info "Trazas encontradas: $traces"
    
    if [ "$traces" -gt "0" ]; then
        log_success "¡Trazas encontradas en Jaeger!"
    else
        log_warning "No se encontraron trazas"
    fi
    
    kill $jaeger_pid 2>/dev/null || true
}

# 7. Verificar logs de Istio
check_istio_logs() {
    log_step "Verificando logs de Istio..."
    
    log_info "Logs de istiod:"
    kubectl logs -n istio-system -l app=istiod --tail=20 | grep -i tracing || log_info "No hay logs de tracing en istiod"
    
    log_info "Logs de sidecars (últimas líneas):"
    local pods=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
    for pod in $pods; do
        if kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}' | grep -q "istio-proxy"; then
            log_info "Logs de $pod (istio-proxy):"
            kubectl logs $pod -n $NAMESPACE -c istio-proxy --tail=5 | grep -i trace || log_info "No hay logs de tracing"
        fi
    done
}

# Función principal
main() {
    log_info "🚀 Iniciando diagnóstico de trazas..."
    
    check_jaeger_status || exit 1
    check_telemetry_config
    check_istio_sidecars
    check_envoy_stats
    generate_test_traffic
    sleep 10  # Esperar que las trazas se procesen
    check_jaeger_traces
    check_istio_logs
    
    log_success "🎉 Diagnóstico completado"
    log_info "💡 Recomendaciones:"
    log_info "  • Verifica que los pods tengan sidecars de Istio"
    log_info "  • Asegúrate de que la configuración de telemetría esté aplicada"
    log_info "  • Genera más tráfico con: make test"
    log_info "  • Accede a Jaeger: http://localhost:16686"
}

main "$@"