#!/bin/bash

# Script optimizado para verificar estado del deployment
set -e

NAMESPACE="medi"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🔍 Verificando estado del deployment..."

# Función para verificar namespace
check_namespace() {
    log_step "Verificando namespace..."
    if namespace_exists $NAMESPACE; then
        log_success "Namespace $NAMESPACE existe"
    else
        log_error "Namespace $NAMESPACE no encontrado"
        return 1
    fi
}

# Función para verificar Istio
check_istio() {
    log_step "Verificando Istio..."
    if kubectl get pods -n istio-system >/dev/null 2>&1; then
        local istio_pods=$(kubectl get pods -n istio-system --no-headers | grep Running | wc -l)
        local total_pods=$(kubectl get pods -n istio-system --no-headers | wc -l)
        log_info "Pods de Istio: $istio_pods/$total_pods corriendo"
        
        # Verificar addons específicos
        local addons=("prometheus" "grafana" "jaeger" "kiali")
        for addon in "${addons[@]}"; do
            if kubectl get pod -l app=$addon -n istio-system >/dev/null 2>&1; then
                log_success "$addon disponible"
            else
                log_warning "$addon no encontrado"
            fi
        done
    else
        log_error "Istio no está instalado"
        return 1
    fi
}

# Función para verificar microservicios
check_microservices() {
    log_step "Verificando microservicios..."
    
    local services=("product-service" "purchase-plan-service")
    local all_ready=true
    
    for service in "${services[@]}"; do
        if kubectl get deployment/$service -n $NAMESPACE >/dev/null 2>&1; then
            local ready=$(kubectl get deployment/$service -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            local desired=$(kubectl get deployment/$service -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
            
            if [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
                log_success "$service: $ready/$desired pods listos"
            else
                log_warning "$service: $ready/$desired pods listos"
                all_ready=false
            fi
        else
            log_error "$service no encontrado"
            all_ready=false
        fi
    done
    
    return $all_ready
}

# Función para verificar configuraciones de Istio
check_istio_configs() {
    log_step "Verificando configuraciones de Istio..."
    
    local configs=("gateway" "virtualservice" "telemetry")
    
    for config in "${configs[@]}"; do
        local count=$(kubectl get $config -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$count" -gt "0" ]; then
            log_success "$config: $count configurado(s)"
        else
            log_warning "$config: no configurado"
        fi
    done
}

# Función para verificar conectividad
check_connectivity() {
    log_step "Verificando conectividad..."
    
    # Verificar si hay port-forwards activos
    local pf_count=$(pgrep -f "kubectl port-forward" | wc -l || echo "0")
    if [ "$pf_count" -gt "0" ]; then
        log_info "Port forwards activos: $pf_count"
    else
        log_info "No hay port forwards activos"
        log_info "💡 Ejecuta 'make port-forward' para acceder a las UIs"
    fi
}

# Función principal
main() {
    check_namespace || exit 1
    check_istio
    check_microservices
    check_istio_configs
    check_connectivity
    
    # Mostrar resumen
    show_status_summary $NAMESPACE
    
    log_success "✅ Verificación de estado completada"
    log_info "💡 Comandos útiles:"
    log_info "  • make status - Estado detallado"
    log_info "  • make port-forward - Acceder a UIs"
    log_info "  • make test - Probar telemetría"
}

main "$@"