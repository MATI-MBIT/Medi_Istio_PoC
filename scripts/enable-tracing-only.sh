#!/bin/bash

# Script para habilitar SOLO tracing sin afectar métricas
set -e

NAMESPACE=${1:-medi}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🎯 Habilitando SOLO tracing sin afectar métricas..."

# 1. Verificar que las métricas funcionan antes del cambio
verify_metrics_before() {
    log_step "Verificando que las métricas funcionan ANTES del cambio..."
    
    kubectl port-forward -n istio-system svc/prometheus 9090:9090 >/dev/null 2>&1 &
    local prom_pid=$!
    sleep 5
    
    local query="sum by (destination_service) (rate(istio_requests_total[5m]))"
    local result=$(curl -s "http://localhost:9090/api/v1/query" --data-urlencode "query=$query" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    
    if [ "$result" -gt "0" ]; then
        log_success "✅ Métricas funcionan correctamente ($result resultados)"
    else
        log_error "❌ Las métricas NO funcionan. No proceder."
        kill $prom_pid 2>/dev/null || true
        exit 1
    fi
    
    kill $prom_pid 2>/dev/null || true
}

# 2. Aplicar SOLO configuración de tracing
apply_tracing_only() {
    log_step "Aplicando configuración SOLO de tracing..."
    
    # Aplicar telemetría solo para tracing
    kubectl apply -f istio/05-telemetry.yaml -n $NAMESPACE
    
    # Aplicar configuración específica de Jaeger en istio-system
    kubectl apply -f istio/06-tracing-config.yaml -n istio-system
    
    log_success "Configuración de tracing aplicada"
}

# 3. Reiniciar SOLO los sidecars (no toda la configuración de Istio)
restart_sidecars() {
    log_step "Reiniciando sidecars para aplicar tracing..."
    
    # Reiniciar deployments para que los sidecars tomen la nueva configuración
    kubectl rollout restart deployment/product-service -n $NAMESPACE
    kubectl rollout restart deployment/purchase-plan-service -n $NAMESPACE
    
    # Esperar que estén listos
    kubectl rollout status deployment/product-service -n $NAMESPACE --timeout=120s
    kubectl rollout status deployment/purchase-plan-service -n $NAMESPACE --timeout=120s
    
    log_success "Sidecars reiniciados"
}

# 4. Verificar que las métricas siguen funcionando DESPUÉS
verify_metrics_after() {
    log_step "Verificando que las métricas siguen funcionando DESPUÉS..."
    
    sleep 30  # Esperar estabilización
    
    kubectl port-forward -n istio-system svc/prometheus 9090:9090 >/dev/null 2>&1 &
    local prom_pid=$!
    sleep 5
    
    # Probar la query original que mencionaste
    local original_query="label_join(sum by (destination_workload,destination_workload_namespace,destination_service) (rate(istio_requests_total{reporter=~\"source|waypoint\"}[5m])), \"destination_workload_var\", \".\", \"destination_workload\", \"destination_workload_namespace\")"
    local result=$(curl -s "http://localhost:9090/api/v1/query" --data-urlencode "query=$original_query" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    
    if [ "$result" -gt "0" ]; then
        log_success "✅ Métricas SIGUEN funcionando ($result resultados)"
    else
        log_warning "⚠️ Query original no funciona, probando alternativa..."
        
        local alt_query="sum by (destination_service) (rate(istio_requests_total[5m]))"
        local alt_result=$(curl -s "http://localhost:9090/api/v1/query" --data-urlencode "query=$alt_query" | jq -r '.data.result | length' 2>/dev/null || echo "0")
        
        if [ "$alt_result" -gt "0" ]; then
            log_success "✅ Métricas básicas funcionan ($alt_result resultados)"
        else
            log_error "❌ Las métricas se rompieron!"
        fi
    fi
    
    kill $prom_pid 2>/dev/null || true
}

# 5. Generar tráfico para testing
generate_test_traffic() {
    log_step "Generando tráfico para testing..."
    
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
    local gateway_pid=$!
    sleep 3
    
    # Generar tráfico con headers de tracing
    for i in {1..15}; do
        curl -H "x-request-id: tracing-test-$i" \
             -H "x-b3-traceid: $(openssl rand -hex 16)" \
             -H "x-b3-spanid: $(openssl rand -hex 8)" \
             -H "x-b3-sampled: 1" \
             -s "http://localhost:8080/health/products" >/dev/null &
        
        curl -H "x-request-id: tracing-test-plan-$i" \
             -H "x-b3-traceid: $(openssl rand -hex 16)" \
             -H "x-b3-spanid: $(openssl rand -hex 8)" \
             -H "x-b3-sampled: 1" \
             -s "http://localhost:8080/health/purchase-plan" >/dev/null &
    done
    
    wait
    kill $gateway_pid 2>/dev/null || true
    
    log_success "Tráfico de testing generado"
}

# 6. Verificar trazas en Jaeger
verify_jaeger_traces() {
    log_step "Verificando trazas en Jaeger..."
    
    sleep 15  # Esperar que las trazas se procesen
    
    kubectl port-forward -n istio-system svc/tracing 16686:16685 >/dev/null 2>&1 &
    local jaeger_pid=$!
    sleep 5
    
    # Verificar servicios
    local services=$(curl -s "http://localhost:16686/api/services" | jq -r '.data | length' 2>/dev/null || echo "0")
    log_info "Servicios en Jaeger: $services"
    
    # Verificar trazas
    local traces=$(curl -s "http://localhost:16686/api/traces?limit=50&lookback=1h" | jq '.data | length' 2>/dev/null || echo "0")
    log_info "Trazas encontradas: $traces"
    
    if [ "$traces" -gt "0" ]; then
        log_success "✅ ¡ÉXITO! Trazas llegando a Jaeger"
    else
        log_warning "⚠️ Aún no hay trazas, puede necesitar más tiempo"
    fi
    
    kill $jaeger_pid 2>/dev/null || true
}

# Función principal
main() {
    log_info "🚀 Iniciando habilitación de tracing sin afectar métricas..."
    
    verify_metrics_before
    apply_tracing_only
    restart_sidecars
    sleep 10  # Estabilización
    verify_metrics_after
    generate_test_traffic
    verify_jaeger_traces
    
    log_success "🎉 Proceso completado"
    log_info "📊 Resultados:"
    log_info "  • Métricas: Deben seguir funcionando"
    log_info "  • Trazas: Configuradas para Jaeger"
    log_info "💡 Accesos:"
    log_info "  • Prometheus: http://localhost:9090"
    log_info "  • Jaeger: http://localhost:16686"
}

main "$@"