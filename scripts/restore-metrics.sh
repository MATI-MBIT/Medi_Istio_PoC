#!/bin/bash

# Script para restaurar las métricas de Prometheus
set -e

NAMESPACE=${1:-medi}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🔧 Restaurando configuración de métricas..."

# 1. Reinstalar Istio con configuración básica (que funcionaba antes)
restore_istio_config() {
    log_step "Reinstalando Istio con configuración básica..."
    
    # Configuración mínima que no interfiere con métricas
    istioctl install --set values.defaultRevision=default \
        --set meshConfig.defaultConfig.tracing.sampling=10.0 \
        --set values.pilot.traceSampling=10.0 -y
    
    log_success "Istio reinstalado con configuración básica"
}

# 2. Aplicar configuración de telemetría simplificada
apply_simple_telemetry() {
    log_step "Aplicando configuración de telemetría simplificada..."
    
    # Eliminar configuración anterior si existe
    kubectl delete telemetry default -n $NAMESPACE --ignore-not-found=true
    
    # Aplicar nueva configuración
    kubectl apply -f istio/05-telemetry.yaml -n $NAMESPACE
    
    log_success "Configuración de telemetría aplicada"
}

# 3. Reiniciar pods para aplicar cambios
restart_pods() {
    log_step "Reiniciando pods para aplicar cambios..."
    
    kubectl rollout restart deployment/product-service -n $NAMESPACE
    kubectl rollout restart deployment/purchase-plan-service -n $NAMESPACE
    
    # Esperar que estén listos
    kubectl rollout status deployment/product-service -n $NAMESPACE --timeout=120s
    kubectl rollout status deployment/purchase-plan-service -n $NAMESPACE --timeout=120s
    
    log_success "Pods reiniciados"
}

# 4. Generar tráfico para restaurar métricas
generate_traffic() {
    log_step "Generando tráfico para restaurar métricas..."
    
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
    local gateway_pid=$!
    sleep 3
    
    # Generar requests a ambos servicios
    for i in {1..10}; do
        curl -s "http://localhost:8080/health/products" >/dev/null &
        curl -s "http://localhost:8080/health/purchase-plan" >/dev/null &
        curl -s "http://localhost:8080/api/products/" >/dev/null &
        curl -s "http://localhost:8080/api/purchase-plan/" >/dev/null &
    done
    
    wait
    kill $gateway_pid 2>/dev/null || true
    
    log_success "Tráfico generado"
}

# 5. Verificar métricas en Prometheus
verify_metrics() {
    log_step "Verificando métricas en Prometheus..."
    
    sleep 30  # Esperar que las métricas se procesen
    
    kubectl port-forward -n istio-system svc/prometheus 9090:9090 >/dev/null 2>&1 &
    local prom_pid=$!
    sleep 5
    
    # Verificar la query original
    local original_query="label_join(sum by (destination_workload,destination_workload_namespace,destination_service) (rate(istio_requests_total{reporter=~\"source|waypoint\"}[5m])), \"destination_workload_var\", \".\", \"destination_workload\", \"destination_workload_namespace\")"
    
    log_info "Probando query original..."
    local result=$(curl -s "http://localhost:9090/api/v1/query" --data-urlencode "query=$original_query" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    
    if [ "$result" -gt "0" ]; then
        log_success "✅ Query original funciona! ($result resultados)"
    else
        log_warning "Query original aún no funciona, probando alternativas..."
        
        # Probar query sin filtro de reporter
        local alt_query="sum by (destination_service) (rate(istio_requests_total[5m]))"
        local alt_result=$(curl -s "http://localhost:9090/api/v1/query" --data-urlencode "query=$alt_query" | jq -r '.data.result | length' 2>/dev/null || echo "0")
        
        if [ "$alt_result" -gt "0" ]; then
            log_success "✅ Query alternativa funciona! ($alt_result resultados)"
            log_info "Usa esta query: $alt_query"
        else
            log_error "Las métricas aún no están disponibles"
        fi
    fi
    
    kill $prom_pid 2>/dev/null || true
}

# Función principal
main() {
    log_info "🚀 Iniciando restauración de métricas..."
    
    restore_istio_config
    apply_simple_telemetry
    restart_pods
    sleep 10  # Esperar estabilización
    generate_traffic
    verify_metrics
    
    log_success "🎉 Proceso de restauración completado"
    log_info "💡 Próximos pasos:"
    log_info "  • Verifica Prometheus: http://localhost:9090"
    log_info "  • Prueba la query original en Grafana"
    log_info "  • Genera más tráfico: make test"
}

main "$@"