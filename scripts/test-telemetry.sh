#!/bin/bash

# Script optimizado para pruebas de telemetría
set -e

NAMESPACE=${1:-medi}
GATEWAY_URL="http://localhost:8080"
REQUESTS=${2:-5}

echo "🧪 Probando telemetría en namespace: $NAMESPACE"

# Función para verificar prerequisitos
check_prerequisites() {
    if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
        echo "❌ Namespace $NAMESPACE no existe"
        exit 1
    fi
    
    if ! kubectl get pods -n $NAMESPACE | grep -q Running; then
        echo "❌ No hay pods corriendo en $NAMESPACE"
        exit 1
    fi
}

# Función para setup de port forwarding
setup_port_forward() {
    echo "🔗 Configurando acceso al gateway..."
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 > /dev/null 2>&1 &
    GATEWAY_PID=$!
    sleep 3
    
    # Verificar conectividad
    if ! curl -sf "$GATEWAY_URL/v1/ping" > /dev/null; then
        echo "⚠️ Gateway no responde, continuando con pruebas internas..."
        kill $GATEWAY_PID 2>/dev/null || true
        return 1
    fi
    return 0
}

# Función optimizada para generar tráfico
generate_traffic() {
    echo "📡 Generando $REQUESTS requests..."
    
    local success=0
    local failed=0
    
    for i in $(seq 1 $REQUESTS); do
        printf "Request %d/%d: " $i $REQUESTS
        
        # Test endpoints con timeout
        if timeout 5 curl -sf "$GATEWAY_URL/v1/ping" > /dev/null && \
           timeout 5 curl -sf -X POST "$GATEWAY_URL/v1/purchase" \
               -H "Content-Type: application/json" \
               -d "{\"item\":\"test-$i\",\"amount\":$(($i * 10))}" > /dev/null; then
            echo "✅"
            ((success++))
        else
            echo "❌"
            ((failed++))
        fi
        
        sleep 0.5
    done
    
    echo "📊 Resultados: $success exitosos, $failed fallidos"
}

# Función para verificar telemetría
check_telemetry() {
    echo "🔍 Verificando telemetría..."
    
    # Verificar pods
    local running_pods=$(kubectl get pods -n $NAMESPACE --no-headers | grep Running | wc -l)
    echo "Pods corriendo: $running_pods"
    
    # Verificar collector si existe
    if kubectl get deployment/otel-collector -n $NAMESPACE > /dev/null 2>&1; then
        echo "📊 Verificando collector..."
        kubectl exec -n $NAMESPACE deployment/otel-collector -- \
            timeout 5 wget -qO- http://localhost:8888/metrics 2>/dev/null | \
            grep -c "otelcol_" || echo "0 métricas del collector"
    fi
    
    # Verificar Zipkin si está disponible
    if kubectl get svc/zipkin -n $NAMESPACE > /dev/null 2>&1; then
        check_zipkin_traces
    fi
}

# Función optimizada para verificar trazas
check_zipkin_traces() {
    echo "🔍 Verificando trazas en Zipkin..."
    
    kubectl port-forward -n $NAMESPACE svc/zipkin 9411:9411 > /dev/null 2>&1 &
    local zipkin_pid=$!
    sleep 3
    
    local traces=$(timeout 10 curl -sf "http://localhost:9411/api/v2/traces?limit=10" 2>/dev/null | \
                   jq length 2>/dev/null || echo "0")
    
    echo "Trazas encontradas: $traces"
    [ "$traces" -gt "0" ] && echo "✅ Zipkin funcionando" || echo "⚠️ Sin trazas en Zipkin"
    
    kill $zipkin_pid 2>/dev/null || true
}

# Función de limpieza
cleanup() {
    echo "🧹 Limpiando procesos..."
    kill $GATEWAY_PID 2>/dev/null || true
    pkill -f "kubectl port-forward" 2>/dev/null || true
}

# Función principal
main() {
    trap cleanup EXIT
    
    check_prerequisites
    
    if setup_port_forward; then
        generate_traffic
        sleep 5  # Tiempo para procesamiento
    fi
    
    check_telemetry
    
    echo ""
    echo "🎉 Pruebas completadas!"
    echo "💡 Para monitoreo continuo: make port-forward"
}

main "$@"