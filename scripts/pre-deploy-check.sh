#!/bin/bash

# Script optimizado para verificar prerequisitos
set -e

# Cargar utilidades
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log_info "Verificando prerequisitos para el despliegue..."

# Verificar herramientas básicas
if ! check_basic_prerequisites; then
    log_error "Faltan prerequisitos básicos"
    exit 1
fi

# Verificar versiones
KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo "unknown")
ISTIO_VERSION=$(istioctl version --short --remote=false 2>/dev/null || echo "unknown")

echo "📋 Versiones detectadas:"
echo "  • kubectl: $KUBECTL_VERSION"
echo "  • istioctl: $ISTIO_VERSION"

# Verificar cluster info
CLUSTER_INFO=$(kubectl cluster-info 2>/dev/null | head -1 | grep -o 'https://[^[:space:]]*' || echo "unknown")
echo "  • cluster: $CLUSTER_INFO"

# Verificar recursos del cluster
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
echo "  • nodos: $NODES"

# Verificar Docker (opcional)
if command_exists docker && docker info >/dev/null 2>&1; then
    log_info "Docker está disponible"
else
    log_warning "Docker no está disponible (puede no ser necesario)"
fi

# Verificar si Istio ya está instalado
if kubectl get namespace istio-system >/dev/null 2>&1; then
    log_warning "Istio ya está instalado"
    ISTIO_PODS=$(kubectl get pods -n istio-system --no-headers 2>/dev/null | grep -c Running || echo "0")
    echo "  • Pods de Istio corriendo: $ISTIO_PODS"
fi

log_success "Prerequisitos verificados correctamente"
log_info "Puedes proceder con 'make deploy'"