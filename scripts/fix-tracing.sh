#!/bin/bash

# Script para solucionar problemas de tracing con Jaeger
set -e

NAMESPACE=${1:-medi}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🔧 Solucionando problemas de tracing..."

# 1. Reinstalar Istio con configuración correcta de tracing
reinstall_istio() {
    log_step "Reinstalando Istio con configuración de tracing..."
    
    # Reinstalar con configuración correcta
    istioctl install --set values.defaultRevision=default \
        --set meshConfig.defaultConfig.tracing.sampling=100.0 \
        --set values.pilot.traceSampling=100.0 \
        --set meshConfig.defaultConfig.tracing.zipkin.address=jaeger-collector.istio-system.svc.cluster.local:9411 \
        --set meshConfig.extensionProviders[0].name=jaeger \
        --set meshConfig.extensionProviders[0].zipkin.service=jaeger-collector.istio-system.svc.cluster.local \
        --set meshConfig.extensionProviders[0].zipkin.port=9411 \
        --set meshConfig.defaultProviders.tracing[0]=jaeger -y
    
    log_success "Istio reinstalado con configuración de tracing"
}

# 2. Aplicar configuración de telemetría
apply_telemetry_config() {
    log_step "Aplicando configuración de telemetría..."
    
    kubectl apply -f istio/05-telemetry.yaml -n $NAMESPACE
    
    log_success "Configuración de telemetría aplicada"
}

# 3. Reiniciar pods para aplicar nueva configuración
restart_pods() {
    log_step "Reiniciando pods para aplicar nueva configuración..."
    
    # Reiniciar deployments
    kubectl rollout restart deployment/product-service -n $NAMESPACE
    kubectl rollout restart deployment/purchase-plan-service -n $NAMESPACE
    
    # Esperar que estén listos
    kubectl rollout status deployment/product-service -n $NAMESPACE --timeout=120s
    kubectl rollout status deployment/purchase-plan-service -n $NAMESPACE --timeout=120s
    
    log_success "Pods reiniciados"
}

# 4. Verificar configuración de tracing en Envoy
verify_envoy_config() {
    log_step "Verificando configuración de tracing en Envoy..."
    
    local pods=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        if kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}' | grep -q "istio-proxy"; then
            log_info "Verificando configuración de $pod..."
            
            # Verificar que el tracing esté configurado
            local tracing_config=$(kubectl exec $pod -n $NAMESPACE -c istio-proxy -- curl -s localhost:15000/config_dump | jq '.configs[] | select(.["@type"] | contains("type.googleapis.com/envoy.config.trace")) | .tracing' 2>/dev/null || echo "null")
            
            if [ "$tracing_config" != "null" ] && [ "$tracing_config" != "" ]; then
                log_success "$pod tiene configuración de tracing"
            else
                log_warning "$pod NO tiene configuración de tracing"
            fi
        fi
    done
}

# 5. Generar tráfico de prueba intensivo
generate_intensive_traffic() {
    log_step "Generando tráfico intensivo para testing..."
    
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
    local gateway_pid=$!
    sleep 3
    
    # Generar muchas requests
    for i in {1..20}; do
        curl -H "x-request-id: intensive-test-$i" \
             -H "x-b3-traceid: $(openssl rand -hex 16)" \
             -H "x-b3-spanid: $(openssl rand -hex 8)" \
             -H "x-b3-sampled: 1" \
             -s "http://localhost:8080/health/products" >/dev/null &
        
        curl -H "x-request-id: intensive-test-plan-$i" \
             -H "x-b3-traceid: $(openssl rand -hex 16)" \
             -H "x-b3-spanid: $(openssl rand -hex 8)" \
             -H "x-b3-sampled: 1" \
             -s "http://localhost:8080/health/purchase-plan" >/dev/null &
    done
    
    wait
    kill $gateway_pid 2>/dev/null || true
    
    log_success "Tráfico intensivo generado (40 requests)"
}

# 6. Verificar trazas en Jaeger después del fix
verify_jaeger_fix() {
    log_step "Verificando trazas en Jaeger después del fix..."
    
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
        log_success "¡ÉXITO! Trazas encontradas en Jaeger"
        
        # Mostrar algunos servicios encontrados
        log_info "Servicios disponibles:"
        curl -s "http://localhost:16686/api/services" | jq -r '.data[]' 2>/dev/null || log_warning "No se pudieron listar servicios"
    else
        log_error "Aún no hay trazas en Jaeger"
    fi
    
    kill $jaeger_pid 2>/dev/null || true
}

# Función principal
main() {
    log_info "🚀 Iniciando solución de problemas de tracing..."
    
    reinstall_istio
    apply_telemetry_config
    restart_pods
    sleep 10  # Esperar que los pods se estabilicen
    verify_envoy_config
    generate_intensive_traffic
    verify_jaeger_fix
    
    log_success "🎉 Proceso de solución completado"
    log_info "💡 Próximos pasos:"
    log_info "  • Accede a Jaeger: http://localhost:16686"
    log_info "  • Ejecuta: make port-forward"
    log_info "  • Genera más tráfico: make test"
}

main "$@"