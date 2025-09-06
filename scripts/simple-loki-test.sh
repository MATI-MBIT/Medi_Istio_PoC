#!/bin/bash

# Script simple para probar Loki con comandos curl básicos
set -e

NAMESPACE=${1:-medi}
LOKI_URL="http://localhost:3100"

echo "🔍 Prueba simple de Loki..."

# Iniciar port-forward en background
echo "🔗 Iniciando port-forward para Loki..."
kubectl port-forward -n $NAMESPACE svc/loki 3100:3100 &
PF_PID=$!
sleep 5

# Función para limpiar al salir
cleanup() {
    if [ ! -z "$PF_PID" ]; then
        kill $PF_PID 2>/dev/null || true
        echo "🔌 Port-forward detenido"
    fi
}
trap cleanup EXIT

echo "✅ Loki disponible en $LOKI_URL"

# 1. Verificar que Loki está funcionando
echo ""
echo "1️⃣ Verificando salud de Loki..."
curl -s "$LOKI_URL/ready" && echo "✅ Loki está listo" || echo "❌ Loki no responde"

# 2. Obtener labels disponibles
echo ""
echo "2️⃣ Obteniendo labels disponibles..."
curl -s "$LOKI_URL/loki/api/v1/labels" | jq . 2>/dev/null || echo "No se pudo parsear JSON"

# 3. Enviar un log de prueba
echo ""
echo "3️⃣ Enviando log de prueba..."
TIMESTAMP=$(date +%s)000000000
TEST_LOG='{
  "streams": [
    {
      "stream": {
        "job": "test-manual",
        "app": "curl-test"
      },
      "values": [
        ["'$TIMESTAMP'", "Log de prueba manual desde curl - '$(date)'"]
      ]
    }
  ]
}'

curl -X POST "$LOKI_URL/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d "$TEST_LOG" \
  && echo "✅ Log enviado" || echo "❌ Error enviando log"

# 4. Esperar y consultar el log enviado
echo ""
echo "4️⃣ Esperando 3 segundos y consultando logs..."
sleep 3

# Consulta simple - últimos 5 minutos
START_TIME=$(date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ')
END_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

echo "🔍 Consultando desde: $START_TIME hasta: $END_TIME"

curl -s "$LOKI_URL/loki/api/v1/query_range" \
  -G \
  --data-urlencode 'query={job="test-manual"}' \
  --data-urlencode "start=$START_TIME" \
  --data-urlencode "end=$END_TIME" \
  | jq . 2>/dev/null || echo "Error parseando respuesta"

# 5. Consultar todos los logs disponibles
echo ""
echo "5️⃣ Consultando TODOS los logs disponibles..."
curl -s "$LOKI_URL/loki/api/v1/query_range" \
  -G \
  --data-urlencode 'query={job=~".+"}' \
  --data-urlencode "start=$START_TIME" \
  --data-urlencode "end=$END_TIME" \
  --data-urlencode "limit=50" \
  | jq '.data.result | length' 2>/dev/null && echo " streams encontrados" || echo "Error consultando"

echo ""
echo "🎉 Prueba completada!"
echo ""
echo "📋 Comandos útiles para probar manualmente:"
echo ""
echo "# 1. Port-forward:"
echo "kubectl port-forward -n $NAMESPACE svc/loki 3100:3100"
echo ""
echo "# 2. Verificar salud:"
echo "curl $LOKI_URL/ready"
echo ""
echo "# 3. Ver labels:"
echo "curl '$LOKI_URL/loki/api/v1/labels' | jq ."
echo ""
echo "# 4. Consultar logs (últimos 5 min):"
echo "curl -G '$LOKI_URL/loki/api/v1/query_range' \\"
echo "  --data-urlencode 'query={job=~\".+\"}' \\"
echo "  --data-urlencode 'start=$(date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ')' \\"
echo "  --data-urlencode 'end=$(date -u '+%Y-%m-%dT%H:%M:%SZ')' | jq ."