#!/bin/bash

# Script para validar que los logs están llegando a Loki
set -e

NAMESPACE=${1:-medi}
LOKI_URL="http://localhost:3100"

echo "🔍 Validando logs en Loki..."

# Función para hacer port-forward de Loki
start_loki_port_forward() {
    echo "🔗 Iniciando port-forward para Loki..."
    #kubectl port-forward -n $NAMESPACE svc/loki 3100:3100 &
    LOKI_PF_PID=$!
    sleep 5
    echo "✅ Loki disponible en $LOKI_URL"
}

# Función para detener port-forward
stop_loki_port_forward() {
    if [ ! -z "$LOKI_PF_PID" ]; then
        kill $LOKI_PF_PID 2>/dev/null || true
        echo "🔌 Port-forward de Loki detenido"
    fi
}

# Función para verificar que Loki está funcionando
check_loki_health() {
    echo "🏥 Verificando salud de Loki..."
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$LOKI_URL/ready" || echo "000")
    
    if [ "$response" = "200" ]; then
        echo "✅ Loki está funcionando correctamente"
        return 0
    else
        echo "❌ Loki no está respondiendo (HTTP $response)"
        return 1
    fi
}

# Función para obtener labels disponibles
get_loki_labels() {
    echo "🏷️  Obteniendo labels disponibles en Loki..."
    
    local labels=$(curl -s "$LOKI_URL/loki/api/v1/labels" | jq -r '.data[]' 2>/dev/null || echo "Error al obtener labels")
    
    if [ "$labels" != "Error al obtener labels" ]; then
        echo "📋 Labels encontrados:"
        echo "$labels"
    else
        echo "⚠️  No se pudieron obtener labels o no hay datos"
    fi
}

# Función para consultar logs recientes
query_recent_logs() {
    echo "📝 Consultando logs recientes..."
    
    # Consulta logs de los últimos 10 minutos
    local query='{job=~".+"}'
    local start_time=$(date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ')
    local end_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    echo "🔍 Consultando desde: $start_time hasta: $end_time"
    echo "📊 Query: $query"
    
    local response=$(curl -s "$LOKI_URL/loki/api/v1/query_range" \
        -G \
        --data-urlencode "query=$query" \
        --data-urlencode "start=$start_time" \
        --data-urlencode "end=$end_time" \
        --data-urlencode "limit=100")
    
    # Verificar si hay resultados
    local result_count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    
    if [ "$result_count" -gt "0" ]; then
        echo "✅ Encontrados $result_count streams de logs"
        echo "📄 Primeros logs:"
        echo "$response" | jq -r '.data.result[0].values[0:3][] | .[1]' 2>/dev/null || echo "Error al parsear logs"
    else
        echo "⚠️  No se encontraron logs en el rango de tiempo especificado"
        echo "🔍 Respuesta completa:"
        echo "$response" | jq . 2>/dev/null || echo "$response"
    fi
}

# Función para consultar logs específicos del microservicio
query_microservice_logs() {
    echo "🎯 Consultando logs específicos del microservicio..."
    
    # Consultas específicas para diferentes fuentes
    local queries=(
        '{app="go-microservice"}'
        '{container="go-microservice"}'
        '{service_name="go-microservice"}'
        '{job="go-microservice"}'
        '{namespace="'$NAMESPACE'"}'
    )
    
    for query in "${queries[@]}"; do
        echo "🔍 Probando query: $query"
        
        local response=$(curl -s "$LOKI_URL/loki/api/v1/query_range" \
            -G \
            --data-urlencode "query=$query" \
            --data-urlencode "start=$(date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ')" \
            --data-urlencode "end=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
            --data-urlencode "limit=10")
        
        local result_count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null || echo "0")
        
        if [ "$result_count" -gt "0" ]; then
            echo "✅ Encontrados logs con query: $query"
            echo "📄 Ejemplo de log:"
            echo "$response" | jq -r '.data.result[0].values[0][1]' 2>/dev/null || echo "Error al parsear"
            echo ""
        else
            echo "❌ No hay logs para: $query"
        fi
    done
}

# Función para enviar un log de prueba directamente a Loki
send_test_log() {
    echo "📤 Enviando log de prueba directamente a Loki..."
    
    local timestamp=$(date +%s)000000000  # Nanosegundos
    local test_log='{"streams": [{"stream": {"job": "test", "app": "test-script"}, "values": [["'$timestamp'", "Test log from validation script - '$(date)'"]]}]}'
    
    local response=$(curl -s -X POST "$LOKI_URL/loki/api/v1/push" \
        -H "Content-Type: application/json" \
        -d "$test_log" \
        -w "%{http_code}")
    
    if [[ "$response" == *"204"* ]]; then
        echo "✅ Log de prueba enviado correctamente"
        
        # Esperar un poco y verificar
        sleep 3
        echo "🔍 Verificando log de prueba..."
        
        local verify_response=$(curl -s "$LOKI_URL/loki/api/v1/query_range" \
            -G \
            --data-urlencode 'query={job="test"}' \
            --data-urlencode "start=$(date -u -v-1M '+%Y-%m-%dT%H:%M:%SZ')" \
            --data-urlencode "end=$(date -u '+%Y-%m-%dT%H:%M:%SZ')")
        
        local test_count=$(echo "$verify_response" | jq -r '.data.result | length' 2>/dev/null || echo "0")
        
        if [ "$test_count" -gt "0" ]; then
            echo "✅ Log de prueba confirmado en Loki"
        else
            echo "⚠️  Log de prueba no encontrado"
        fi
    else
        echo "❌ Error enviando log de prueba: $response"
    fi
}

# Función principal
main() {
    echo "🚀 Iniciando validación de logs en Loki..."
    
    # Verificar que kubectl funciona
    if ! kubectl get pods -n $NAMESPACE > /dev/null 2>&1; then
        echo "❌ No se puede acceder al namespace $NAMESPACE"
        exit 1
    fi
    
    # Verificar que Loki está desplegado
    if ! kubectl get deployment loki -n $NAMESPACE > /dev/null 2>&1; then
        echo "❌ Loki no está desplegado en el namespace $NAMESPACE"
        exit 1
    fi
    
    # Iniciar port-forward
    start_loki_port_forward
    
    # Trap para limpiar al salir
    trap stop_loki_port_forward EXIT
    
    # Ejecutar validaciones
    if check_loki_health; then
        get_loki_labels
        echo ""
        query_recent_logs
        echo ""
        query_microservice_logs
        echo ""
        send_test_log
    else
        echo "❌ No se puede continuar, Loki no está disponible"
        exit 1
    fi
    
    echo ""
    echo "🎉 Validación completada!"
    echo "🔗 Para acceso manual: kubectl port-forward -n $NAMESPACE svc/loki 3100:3100"
    echo "📊 Query UI: $LOKI_URL"
}

# Ejecutar si es llamado directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi