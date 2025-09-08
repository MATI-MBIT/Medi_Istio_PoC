#!/bin/bash

# Script para configurar telemetría de Istio con addons nativos
set -e

NAMESPACE=${1:-medi}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🔧 Configurando telemetría de Istio para namespace: $NAMESPACE"

# Función para verificar prerequisitos
check_prerequisites() {
    if ! kubectl get namespace istio-system > /dev/null 2>&1; then
        log_error "Istio no está instalado"
        exit 1
    fi
    
    if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
        log_error "Namespace $NAMESPACE no existe"
        exit 1
    fi
    
    log_success "Prerequisites verificados"
}

# Función para verificar addons de Istio
check_istio_addons() {
    log_info "Verificando addons de Istio..."
    
    local addons=("prometheus" "grafana" "jaeger" "kiali")
    local missing=()
    
    for addon in "${addons[@]}"; do
        if kubectl get pod -l app=$addon -n istio-system >/dev/null 2>&1; then
            log_success "$addon está disponible"
        else
            missing+=($addon)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_warning "Addons faltantes: ${missing[*]}"
        log_info "Instala con: istioctl install --set values.pilot.env.EXTERNAL_ISTIOD=false"
    fi
}

# Función para verificar microservicios
check_microservices() {
    log_info "Verificando microservicios..."
    
    local services=("product-service" "purchase-plan-service")
    
    for service in "${services[@]}"; do
        if kubectl get deployment/$service -n $NAMESPACE >/dev/null 2>&1; then
            local ready=$(kubectl get deployment/$service -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            local desired=$(kubectl get deployment/$service -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
            log_info "$service: $ready/$desired pods listos"
        else
            log_warning "$service no encontrado"
        fi
    done
}

# Función principal
main() {
    check_prerequisites
    check_istio_addons
    check_microservices
    
    log_success "Configuración de telemetría verificada"
    log_info "💡 Usa 'make port-forward' para acceder a las UIs"
}

main "$@"