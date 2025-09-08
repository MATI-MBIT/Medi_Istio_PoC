#!/bin/bash

# Script para probar telemetría con microservicios actuales
set -e

NAMESPACE=${1:-medi}
GATEWAY_URL="http://localhost:8080"
REQUESTS=${2:-10}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🧪 Probando telemetría en namespace: $NAMESPACE"

# Función para verificar prerequisitos
check_prerequisites() {
    if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
        log_error "Namespace $NAMESPACE no existe"
        exit 1
    fi
    
    if ! kubectl get pods -n $NAMESPACE | grep -q Running; then
        log_error "No hay pods corriendo en $NAMESPACE"
        exit 1
    fi
    
    log_success "Prerequisites verificados"
}

# Función para setup de port forwarding
setup_port_forward() {
    log_step "Configurando acceso al gateway..."
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 > /dev/null 2>&1 &
    GATEWAY_PID=$!
    sleep 3
    
    # Verificar conectividad con endpoints actuales
    if curl -sf "$GATEWAY_URL/health/products" > /dev/null 2>&1; then
        log_success "Gateway responde correctamente"
        return 0
    else
        log_warning "Gateway no responde, continuando con pruebas internas..."
        kill $GATEWAY_PID 2>/dev/null || true
        return 1
    fi
}

# Función para generar tráfico con endpoints actuales
generate_traffic() {
    log_step "Generando $REQUESTS requests a microservicios..."
    
    local success=0
    local failed=0
    
    for i in $(seq 1 $REQUESTS); do
        printf "Request %d/%d: " $i $REQUESTS
        
        # Test health endpoints
        local health_ok=0
        if timeout 5 curl -sf "$GATEWAY_URL/health/products" > /dev/null 2>&1; then
            ((health_ok++))
        fi
        
        if timeout 5 curl -sf "$GATEWAY_URL/health/purchase-plan" > /dev/null 2>&1; then
            ((health_ok++))
        fi
        
        # Test API endpoints
        if timeout 5 curl -sf "$GATEWAY_URL/api/products/" > /dev/null 2>&1; then
            ((health_ok++))
        fi
        
        if timeout 5 curl -sf "$GATEWAY_URL/api/purchase-plan/" > /dev/null 2>&1; then
            ((health_ok++))
        fi
        
        if [ $health_ok -gt 2 ]; then
            echo "✅"
            ((success++))
        else
            echo "❌"
            ((failed++))
        fi
        
        sleep 0.5
    done
    
    log_info "📊 Resultados: $success exitosos, $failed fallidos"
}

# Función para verificar telemetría de Istio
check_istio_telemetry() {
    log_step "Verificando telemetría de Istio..."
    
    # Verificar pods de microservicios
    local running_pods=$(kubectl get pods -n $NAMESPACE --no-headers | grep Running | wc -l)
    log_info "Pods corriendo: $running_pods"
    
    # Verificar sidecars de Istio
    local pods_with_sidecars=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].spec.containers[*].name}' | grep -o istio-proxy | wc -l)
    log_info "Sidecars de Istio: $pods_with_sidecars"
    
    # Verificar Jaeger si está disponible
    if kubectl get svc tracing -n istio-system >/dev/null 2>&1; then
        check_jaeger_traces
    else
        log_warning "Jaeger no está disponible"
    fi
    
    # Verificar Prometheus
    if kubectl get pod -l app=prometheus -n istio-system >/dev/null 2>&1; then
        log_success "Prometheus está disponible"
    else
        log_warning "Prometheus no está disponible"
    fi
}

# Función para verificar trazas en Jaeger
check_jaeger_traces() {
    log_step "Verificando trazas en Jaeger..."
    
    kubectl port-forward -n istio-system svc/tracing 16686:16685 > /dev/null 2>&1 &
    local jaeger_pid=$!
    sleep 3
    
    local traces=$(timeout 10 curl -sf "http://localhost:16686/api/traces?service=istio-proxy&limit=10" 2>/dev/null | \
                   jq '.data | length' 2>/dev/null || echo "0")
    
    log_info "Trazas encontradas: $traces"
    if [ "$traces" -gt "0" ]; then
        log_success "Jaeger funcionando correctamente"
    else
        log_warning "Sin trazas en Jaeger (puede ser normal si es la primera ejecución)"
    fi
    
    kill $jaeger_pid 2>/dev/null || true
}

# Función de limpieza
cleanup() {
    log_step "Limpiando procesos..."
    kill $GATEWAY_PID 2>/dev/null || true
    pkill -f "kubectl port-forward" 2>/dev/null || true
}

# Función principal
main() {
    trap cleanup EXIT
    
    check_prerequisites
    
    if setup_port_forward; then
        generate_traffic
        sleep 5  # Tiempo para procesamiento de telemetría
    fi
    
    check_istio_telemetry
    
    log_success "🎉 Pruebas completadas!"
    log_info "💡 Para monitoreo continuo: make port-forward"
    log_info "🔍 Verifica las UIs de observabilidad:"
    log_info "  • Grafana: http://localhost:3000"
    log_info "  • Jaeger: http://localhost:16686"
    log_info "  • Prometheus: http://localhost:9090"
    log_info "  • Kiali: http://localhost:20001"
}

main "$@"