#!/bin/bash

# Script para diagnosticar métricas de Prometheus
set -e

NAMESPACE=${1:-medi}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "🔍 Diagnosticando métricas de Prometheus..."

# Función para verificar métricas disponibles
check_available_metrics() {
    log_step "Verificando métricas disponibles en Prometheus..."
    
    kubectl port-forward -n istio-system svc/prometheus 9090:9090 >/dev/null 2>&1 &
    local prom_pid=$!
    sleep 5
    
    log_info "Buscando métricas de Istio..."
    
    # Verificar métricas de istio_requests_total
    local istio_requests=$(curl -s "http://localhost:9090/api/v1/label/__name__/values" | jq -r '.data[]' | grep -c "istio_requests" || echo "0")
    log_info "Métricas istio_requests encontradas: $istio_requests"
    
    # Listar todas las métricas de Istio disponibles
    log_info "Métricas de Istio disponibles:"
    curl -s "http://localhost:9090/api/v1/label/__name__/values" | jq -r '.data[]' | grep "istio" | head -10
    
    # Verificar métricas específicas
    log_info "Verificando métrica istio_requests_total..."
    local requests_total=$(curl -s "http://localhost:9090/api/v1/query?query=istio_requests_total" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    log_info "Resultados para istio_requests_total: $requests_total"
    
    if [ "$requests_total" -eq "0" ]; then
        log_warning "No hay datos para istio_requests_total"
        
        # Buscar métricas alternativas
        log_info "Buscando métricas alternativas..."
        curl -s "http://localhost:9090/api/v1/label/__name__/values" | jq -r '.data[]' | grep -E "(request|http)" | head -5
    fi
    
    kill $prom_pid 2>/dev/null || true
}

# Función para verificar labels disponibles
check_available_labels() {
    log_step "Verificando labels disponibles..."
    
    kubectl port-forward -n istio-system svc/prometheus 9090:9090 >/dev/null 2>&1 &
    local prom_pid=$!
    sleep 5
    
    # Verificar labels de istio_requests_total si existe
    log_info "Labels disponibles para istio_requests_total:"
    curl -s "http://localhost:9090/api/v1/series?match[]=istio_requests_total" | jq -r '.data[0] | keys[]' 2>/dev/null | head -10 || log_warning "No se pudieron obtener labels"
    
    # Verificar si existen los labels específicos de la query
    local labels_to_check=("destination_workload" "destination_workload_namespace" "destination_service" "reporter")
    
    for label in "${labels_to_check[@]}"; do
        local label_values=$(curl -s "http://localhost:9090/api/v1/label/$label/values" | jq -r '.data | length' 2>/dev/null || echo "0")
        if [ "$label_values" -gt "0" ]; then
            log_success "Label '$label' disponible con $label_values valores"
        else
            log_warning "Label '$label' NO disponible"
        fi
    done
    
    kill $prom_pid 2>/dev/null || true
}

# Función para probar queries alternativas
test_alternative_queries() {
    log_step "Probando queries alternativas..."
    
    kubectl port-forward -n istio-system svc/prometheus 9090:9090 >/dev/null 2>&1 &
    local prom_pid=$!
    sleep 5
    
    # Queries alternativas para probar
    local queries=(
        "istio_requests_total"
        "istio_request_total"
        "envoy_http_inbound_0_0_0_0_8080_http_requests_total"
        "envoy_cluster_upstream_rq_total"
        "up{job=~\".*envoy.*\"}"
        "up{job=~\".*istio.*\"}"
    )
    
    for query in "${queries[@]}"; do
        log_info "Probando query: $query"
        local result=$(curl -s "http://localhost:9090/api/v1/query?query=$query" | jq -r '.data.result | length' 2>/dev/null || echo "0")
        if [ "$result" -gt "0" ]; then
            log_success "✅ Query funciona: $query ($result resultados)"
        else
            log_warning "❌ Query sin resultados: $query"
        fi
    done
    
    kill $prom_pid 2>/dev/null || true
}

# Función para generar query corregida
generate_fixed_query() {
    log_step "Generando query corregida..."
    
    kubectl port-forward -n istio-system svc/prometheus 9090:9090 >/dev/null 2>&1 &
    local prom_pid=$!
    sleep 5
    
    # Verificar qué métricas de requests están disponibles
    local available_metrics=$(curl -s "http://localhost:9090/api/v1/label/__name__/values" | jq -r '.data[]' | grep -E "(istio.*request|envoy.*request)" | head -3)
    
    log_info "Métricas de requests disponibles:"
    echo "$available_metrics"
    
    # Generar queries alternativas basadas en lo que está disponible
    log_info "Queries alternativas sugeridas:"
    
    echo "# Query básica para requests totales:"
    echo "sum(rate(istio_requests_total[\$__rate_interval]))"
    echo ""
    
    echo "# Query por servicio (si destination_service_name está disponible):"
    echo "sum by (destination_service_name) (rate(istio_requests_total[\$__rate_interval]))"
    echo ""
    
    echo "# Query por workload (si destination_app está disponible):"
    echo "sum by (destination_app) (rate(istio_requests_total[\$__rate_interval]))"
    echo ""
    
    echo "# Query usando Envoy metrics como fallback:"
    echo "sum by (cluster_name) (rate(envoy_cluster_upstream_rq_total[\$__rate_interval]))"
    
    kill $prom_pid 2>/dev/null || true
}

# Función para verificar configuración de Istio
check_istio_metrics_config() {
    log_step "Verificando configuración de métricas de Istio..."
    
    # Verificar telemetría configurada
    if kubectl get telemetry -n $NAMESPACE >/dev/null 2>&1; then
        log_info "Configuración de telemetría:"
        kubectl get telemetry -n $NAMESPACE -o yaml | grep -A 10 -B 5 "metrics" || log_info "No hay configuración específica de métricas"
    else
        log_warning "No hay configuración de telemetría en $NAMESPACE"
    fi
    
    # Verificar configuración global de Istio
    log_info "Configuración global de métricas en Istio:"
    kubectl get configmap istio -n istio-system -o jsonpath='{.data.mesh}' | grep -A 10 -B 5 "defaultProviders" || log_info "No hay configuración de providers por defecto"
}

# Función principal
main() {
    log_info "🚀 Iniciando diagnóstico de métricas de Prometheus..."
    
    check_available_metrics
    echo ""
    check_available_labels
    echo ""
    test_alternative_queries
    echo ""
    check_istio_metrics_config
    echo ""
    generate_fixed_query
    
    log_success "🎉 Diagnóstico completado"
    log_info "💡 Recomendaciones:"
    log_info "  • Usa las queries alternativas sugeridas"
    log_info "  • Verifica que los sidecars de Istio estén inyectados"
    log_info "  • Genera tráfico con: make test"
    log_info "  • Accede a Prometheus: http://localhost:9090"
}

main "$@"