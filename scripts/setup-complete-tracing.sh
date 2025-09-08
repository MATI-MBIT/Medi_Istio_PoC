#!/bin/bash

# Script para configurar tracing completo (Gateway + Sidecars)
set -e

NAMESPACE=${1:-medi}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🌐 Configurando tracing completo (Gateway + Microservicios)..."

# 1. Aplicar configuración de tracing para microservicios
apply_microservices_tracing() {
    log_step "Aplicando configuración de tracing para microservicios..."
    
    kubectl apply -f istio/05-telemetry.yaml -n $NAMESPACE
    kubectl apply -f istio/06-tracing-filter.yaml
    
    log_success "Tracing de microservicios configurado"
}

# 2. Aplicar configuración de tracing para Ingress Gateway
apply_gateway_tracing() {
    log_step "Aplicando configuración de tracing para Ingress Gateway..."
    
    kubectl apply -f istio/07-gateway-tracing.yaml
    
    log_success "Tracing de Gateway configurado"
}

# 3. Reiniciar Ingress Gateway
restart_gateway() {
    log_step "Reiniciando Ingress Gateway..."
    
    kubectl rollout restart deployment/istio-ingressgateway -n istio-system
    kubectl rollout status deployment/istio-ingressgateway -n istio-system --timeout=120s
    
    log_success "Ingress Gateway reiniciado"
}

# 4. Reiniciar sidecars de microservicios
restart_microservices() {
    log_step "Reiniciando microservicios..."
    
    kubectl rollout restart deployment/product-service -n $NAMESPACE
    kubectl rollout restart deployment/purchase-plan-service -n $NAMESPACE
    
    kubectl rollout status deployment/product-service -n $NAMESPACE --timeout=120s
    kubectl rollout status deployment/purchase-plan-service -n $NAMESPACE --timeout=120s
    
    log_success "Microservicios reiniciados"
}

# 5. Generar tráfico para probar tracing completo
generate_end_to_end_traffic() {
    log_step "Generando tráfico end-to-end para probar tracing completo..."
    
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
    local gateway_pid=$!
    sleep 3
    
    log_info "Generando requests que deberían crear trazas completas..."
    
    # Requests que van desde Gateway → Product Service
    for i in {1..10}; do
        curl -H "x-request-id: e2e-products-$i" \
             -H "x-trace-id: $(openssl rand -hex 16)" \
             -s "http://localhost:8080/api/products/" >/dev/null &
    done
    
    # Requests que van desde Gateway → Purchase Plan Service
    for i in {1..10}; do
        curl -H "x-request-id: e2e-purchase-$i" \
             -H "x-trace-id: $(openssl rand -hex 16)" \
             -s "http://localhost:8080/api/purchase-plan/" >/dev/null &
    done
    
    # Requests de health (deberían ser filtradas)
    log_info "Generando health checks (deberían ser filtradas)..."
    for i in {1..5}; do
        curl -H "x-request-id: health-filtered-$i" \
             -s "http://localhost:8080/health/products" >/dev/null &
        curl -H "x-request-id: health-plan-filtered-$i" \
             -s "http://localhost:8080/health/purchase-plan" >/dev/null &
    done
    
    wait
    kill $gateway_pid 2>/dev/null || true
    
    log_success "Tráfico end-to-end generado (20 API + 10 health requests)"
}

# 6. Verificar trazas completas en Jaeger
verify_complete_traces() {
    log_step "Verificando trazas completas en Jaeger..."
    
    sleep 30  # Esperar procesamiento
    
    kubectl port-forward -n istio-system svc/tracing 16686:16685 >/dev/null 2>&1 &
    local jaeger_pid=$!
    sleep 5
    
    # Verificar servicios disponibles
    log_info "Servicios disponibles en Jaeger:"
    local services_response=$(curl -s "http://localhost:16686/api/services")
    local services=$(echo "$services_response" | jq -r '.data[]' 2>/dev/null || echo "Error obteniendo servicios")
    echo "$services"
    
    # Buscar trazas que incluyan el gateway
    log_info "Buscando trazas que incluyan el Ingress Gateway..."
    local gateway_traces=$(curl -s "http://localhost:16686/api/traces?service=istio-ingressgateway&limit=20" | jq '.data | length' 2>/dev/null || echo "0")
    log_info "Trazas del Gateway encontradas: $gateway_traces"
    
    # Buscar trazas de microservicios
    local product_traces=$(curl -s "http://localhost:16686/api/traces?service=product-service&limit=20" | jq '.data | length' 2>/dev/null || echo "0")
    local plan_traces=$(curl -s "http://localhost:16686/api/traces?service=purchase-plan-service&limit=20" | jq '.data | length' 2>/dev/null || echo "0")
    
    log_info "Trazas de product-service: $product_traces"
    log_info "Trazas de purchase-plan-service: $plan_traces"
    
    # Buscar trazas end-to-end (que incluyan múltiples servicios)
    local all_traces_response=$(curl -s "http://localhost:16686/api/traces?limit=50&lookback=1h")
    local total_traces=$(echo "$all_traces_response" | jq '.data | length' 2>/dev/null || echo "0")
    
    log_info "Total de trazas encontradas: $total_traces"
    
    if [ "$total_traces" -gt "0" ]; then
        # Contar trazas que tienen múltiples spans (end-to-end)
        local e2e_traces=$(echo "$all_traces_response" | jq '[.data[] | select(.spans | length > 1)] | length' 2>/dev/null || echo "0")
        log_info "Trazas end-to-end (múltiples spans): $e2e_traces"
        
        if [ "$e2e_traces" -gt "0" ]; then
            log_success "✅ ¡Trazas end-to-end funcionando!"
        fi
        
        # Verificar que no hay trazas de health
        local health_traces=$(echo "$all_traces_response" | jq '[.data[] | select(.spans[] | .operationName | contains("health"))] | length' 2>/dev/null || echo "0")
        log_info "Trazas de health (deberían ser 0): $health_traces"
        
        if [ "$health_traces" -eq "0" ]; then
            log_success "✅ Health checks filtrados correctamente"
        fi
    else
        log_warning "⚠️ No hay trazas aún, puede necesitar más tiempo"
    fi
    
    kill $jaeger_pid 2>/dev/null || true
}

# 7. Mostrar configuración aplicada
show_tracing_config() {
    log_step "Mostrando configuración de tracing aplicada..."
    
    log_info "Configuraciones de Telemetry:"
    kubectl get telemetry -n $NAMESPACE
    kubectl get telemetry -n istio-system
    
    log_info "EnvoyFilters aplicados:"
    kubectl get envoyfilter -n istio-system
    
    log_info "Estado del Ingress Gateway:"
    kubectl get pods -n istio-system -l app=istio-proxy,istio=ingressgateway
}

# Función principal
main() {
    log_info "🚀 Iniciando configuración de tracing completo..."
    
    apply_microservices_tracing
    apply_gateway_tracing
    restart_gateway
    sleep 10  # Esperar que el gateway se estabilice
    restart_microservices
    sleep 10  # Esperar que los microservicios se estabilicen
    generate_end_to_end_traffic
    verify_complete_traces
    show_tracing_config
    
    log_success "🎉 Configuración de tracing completo terminada"
    log_info "🌐 Flujo de trazas configurado:"
    log_info "  Internet → Ingress Gateway → Microservicios → Jaeger"
    log_info "💡 Accesos:"
    log_info "  • Jaeger UI: http://localhost:16686"
    log_info "  • Buscar por servicios: istio-ingressgateway, product-service, purchase-plan-service"
    log_info "  • Health checks: Filtrados automáticamente"
}

main "$@"