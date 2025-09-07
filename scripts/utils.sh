#!/bin/bash

# Utilidades comunes para scripts del proyecto
# Este archivo debe ser sourced, no ejecutado directamente

# Colores para output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Función para logging con colores
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "${YELLOW}🔄 $1${NC}"
}

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para verificar prerequisitos básicos
check_basic_prerequisites() {
    local missing=()
    
    if ! command_exists kubectl; then
        missing+=("kubectl")
    fi
    
    if ! command_exists istioctl; then
        missing+=("istioctl")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Faltan herramientas: ${missing[*]}"
        return 1
    fi
    
    # Verificar conectividad al cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "No se puede conectar al cluster de Kubernetes"
        return 1
    fi
    
    return 0
}

# Función para verificar si un namespace existe
namespace_exists() {
    kubectl get namespace "$1" >/dev/null 2>&1
}

# Función para verificar si un deployment está listo
deployment_ready() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-60s}
    
    kubectl wait --for=condition=available deployment/$deployment -n $namespace --timeout=$timeout >/dev/null 2>&1
}

# Función para verificar si un pod está corriendo
pod_running() {
    local namespace=$1
    local selector=$2
    
    kubectl get pods -n $namespace -l $selector --no-headers 2>/dev/null | grep -q Running
}

# Función para obtener el número de pods corriendo
count_running_pods() {
    local namespace=$1
    kubectl get pods -n $namespace --no-headers 2>/dev/null | grep -c Running || echo "0"
}

# Función para port forward con timeout
safe_port_forward() {
    local namespace=$1
    local service=$2
    local port=$3
    local timeout=${4:-5}
    
    timeout $timeout kubectl port-forward -n $namespace svc/$service $port:$port >/dev/null 2>&1 &
    local pid=$!
    sleep 2
    
    if kill -0 $pid 2>/dev/null; then
        echo $pid
        return 0
    else
        return 1
    fi
}

# Función para cleanup de procesos port-forward
cleanup_port_forwards() {
    local count=$(pgrep -f "kubectl port-forward" | wc -l)
    if [ $count -gt 0 ]; then
        log_step "Deteniendo $count procesos port-forward..."
        pkill -f "kubectl port-forward" 2>/dev/null || true
        sleep 2
        log_success "Port forwards detenidos"
    fi
}

# Función para cleanup completo de namespace
cleanup_namespace() {
    local namespace=$1
    local timeout=${2:-60s}
    
    if ! namespace_exists $namespace; then
        log_warning "Namespace $namespace no existe"
        return 0
    fi
    
    log_step "Eliminando namespace $namespace..."
    kubectl delete namespace $namespace --timeout=$timeout --ignore-not-found=true
    
    # Verificar que se eliminó
    local count=0
    while namespace_exists $namespace && [ $count -lt 30 ]; do
        echo "Esperando eliminación del namespace... ($count/30)"
        sleep 2
        ((count++))
    done
    
    if namespace_exists $namespace; then
        log_warning "Namespace $namespace aún existe, puede tardar más tiempo"
    else
        log_success "Namespace $namespace eliminado"
    fi
}

# Función para setup de trap para cleanup automático
setup_cleanup_trap() {
    trap 'cleanup_port_forwards; exit 0' EXIT INT TERM
}

# Función para verificar conectividad HTTP
check_http_endpoint() {
    local url=$1
    local timeout=${2:-5}
    
    timeout $timeout curl -sf "$url" >/dev/null 2>&1
}

# Función para mostrar resumen de estado
show_status_summary() {
    local namespace=$1
    
    echo ""
    log_info "=== Resumen de Estado ==="
    
    local total_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | wc -l || echo "0")
    local running_pods=$(count_running_pods $namespace)
    
    echo "Pods: $running_pods/$total_pods corriendo"
    
    local services=$(kubectl get svc -n $namespace --no-headers 2>/dev/null | wc -l || echo "0")
    echo "Servicios: $services"
    
    if kubectl get gateway -n $namespace >/dev/null 2>&1; then
        local gateways=$(kubectl get gateway -n $namespace --no-headers | wc -l)
        echo "Gateways: $gateways"
    fi
}

# Función para esperar que los pods estén listos
wait_for_pods() {
    local namespace=$1
    local timeout=${2:-300}
    local interval=10
    local elapsed=0
    
    log_step "Esperando que los pods estén listos..."
    
    while [ $elapsed -lt $timeout ]; do
        local ready_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | grep -c "Running\|Completed" || echo "0")
        local total_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ $total_pods -gt 0 ] && [ $ready_pods -eq $total_pods ]; then
            log_success "Todos los pods están listos ($ready_pods/$total_pods)"
            return 0
        fi
        
        echo "Pods listos: $ready_pods/$total_pods (esperando ${interval}s...)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_warning "Timeout esperando pods. Estado actual:"
    kubectl get pods -n $namespace
    return 1
}