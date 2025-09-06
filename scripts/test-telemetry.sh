#!/bin/bash

# Script para probar que la telemetría está funcionando correctamente
set -e

NAMESPACE=${1:-medi}
GATEWAY_URL="http://localhost:8080"

echo "🧪 Probando telemetría en namespace: $NAMESPACE"

# Función para hacer requests y generar trazas
generate_traffic() {
    echo "📡 Generando tráfico para crear trazas..."
    
    for i in {1..10}; do
        echo "Request $i/10"
        
        # Test ping endpoint
        curl -s "$GATEWAY_URL/v1/ping" > /dev/null || echo "❌ Ping failed"
        
        # Test purchase endpoint
        curl -s -X POST "$GATEWAY_URL/v1/purchase" \
            -H "Content-Type: application/json" \
            -d '{"item":"test-item-'$i'","amount":'$(($i * 10))'}' > /dev/null || echo "❌ Purchase failed"
        
        sleep 1
    done
    
    echo "✅ Tráfico generado"
}

# Función para verificar que los servicios están corriendo
check_services() {
    echo "🔍 Verificando servicios..."
    
    # Verificar pods
    kubectl get pods -n $NAMESPACE
    
    # Verificar que el collector está recibiendo datos
    echo ""
    echo "📊 Verificando métricas del collector..."
    kubectl exec -n $NAMESPACE deployment/otel-collector -- wget -qO- http://localhost:8888/metrics | grep -E "(otelcol_receiver|otelcol_exporter)" | head -5
    
    # Verificar logs del collector
    echo ""
    echo "📝 Últimos logs del collector:"
    kubectl logs -n $NAMESPACE deployment/otel-collector --tail=10
}

# Función para verificar trazas en Zipkin
check_zipkin() {
    echo ""
    echo "🔍 Verificando trazas en Zipkin..."
    
    # Port forward temporal para verificar
    kubectl port-forward -n $NAMESPACE svc/zipkin 9411:9411 &
    PF_PID=$!
    sleep 5
    
    # Verificar que Zipkin tiene trazas
    TRACES=$(curl -s "http://localhost:9411/api/v2/traces?limit=10" | jq length 2>/dev/null || echo "0")
    echo "Número de trazas encontradas: $TRACES"
    
    if [ "$TRACES" -gt "0" ]; then
        echo "✅ Trazas encontradas en Zipkin"
    else
        echo "⚠️  No se encontraron trazas en Zipkin"
    fi
    
    # Terminar port forward
    kill $PF_PID 2>/dev/null || true
}

# Función principal
main() {
    echo "🚀 Iniciando pruebas de telemetría..."
    
    # Verificar que el gateway está disponible
    echo "🔗 Verificando acceso al gateway..."
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &
    GATEWAY_PID=$!
    sleep 5
    
    # Generar tráfico
    generate_traffic
    
    # Esperar un poco para que las trazas se procesen
    echo "⏳ Esperando procesamiento de trazas..."
    sleep 10
    
    # Verificar servicios
    check_services
    
    # Verificar trazas
    check_zipkin
    
    # Limpiar
    kill $GATEWAY_PID 2>/dev/null || true
    
    echo ""
    echo "🎉 Pruebas completadas!"
    echo "📊 Para acceder a las UIs, ejecuta: make port-forward"
}

# Ejecutar si es llamado directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi