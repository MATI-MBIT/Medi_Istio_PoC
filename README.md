# Medi Istio PoC - Optimized

Prueba de concepto optimizada con Kubernetes, Istio y OpenTelemetry para observabilidad completa.

## 🚀 Quick Start

```bash
# Verificar prerequisitos
make check

# Desplegar stack completo
make deploy

# Verificar estado
make status

# Acceder a UIs
make port-forward

# Ejecutar pruebas
make test
```

## 📋 Prerequisitos

- **Kubernetes cluster** (minikube, kind, etc.)
- **kubectl** (configurado y conectado)
- **istioctl** v1.26.2+
- **make**
- **curl** (para testing)

## 🏗️ Arquitectura

| Componente | Descripción |
|------------|-------------|
| **Microservicio** | `docker.io/aira18/go-microservice:latest` |
| **Service Mesh** | Istio con mTLS permissive |
| **Telemetría** | OpenTelemetry Collector |
| **Métricas** | Prometheus |
| **Logs** | Loki |
| **Trazas** | Zipkin |
| **Dashboards** | Grafana |
| **Namespace** | `medi` |

## 🎯 Endpoints

- `GET /v1/ping` → Health check
- `POST /v1/purchase` → Procesar compra

## 📊 Acceso a UIs

| Servicio | URL | Credenciales |
|----------|-----|--------------|
| **Grafana** | http://localhost:3000 | admin/admin |
| **Zipkin** | http://localhost:9411 | - |
| **Prometheus** | http://localhost:9090 | - |
| **Loki** | http://localhost:3100 | - |
| **Microservicio** | http://localhost:8080 | - |

## 🛠️ Comandos Disponibles

```bash
make help          # Mostrar todos los comandos
make check          # Verificar prerequisitos
make deploy         # Desplegar stack completo
make status         # Ver estado del deployment
make port-forward   # Iniciar port forwarding
make test           # Ejecutar pruebas completas
make test-quick     # Pruebas rápidas de endpoints
make logs           # Ver logs de todos los pods
make restart        # Reiniciar pods de aplicación
make cleanup        # Limpiar todos los recursos
```

## 🧪 Testing

### Pruebas Automáticas
```bash
# Pruebas completas con telemetría
make test

# Pruebas rápidas de endpoints
make test-quick
```

### Pruebas Manuales
```bash
# Health check
curl http://localhost:8080/v1/ping

# Procesar compra
curl -X POST http://localhost:8080/v1/purchase \
  -H "Content-Type: application/json" \
  -d '{"item":"laptop","amount":999.99}'
```

## 🔧 Optimizaciones Implementadas

### Makefile
- ✅ **Comandos consolidados**: Menos targets, más funcionalidad
- ✅ **Colores en output**: Mejor experiencia visual
- ✅ **Manejo de errores**: Continuación inteligente en fallos
- ✅ **Timeouts configurables**: Evita esperas infinitas
- ✅ **Targets privados**: Organización interna limpia

### Scripts
- ✅ **Utilidades compartidas**: `scripts/utils.sh` elimina duplicación
- ✅ **Logging consistente**: Colores y formato unificado
- ✅ **Verificaciones robustas**: Mejor manejo de prerequisitos
- ✅ **Cleanup automático**: Gestión de procesos background
- ✅ **Timeouts inteligentes**: Evita bloqueos

### Flujo de Trabajo
- ✅ **Verificación previa**: `make check` antes de deploy
- ✅ **Deploy unificado**: Un comando para todo el stack
- ✅ **Testing integrado**: Verificación automática post-deploy
- ✅ **Monitoreo simplificado**: Estado consolidado

## 🐛 Troubleshooting

### Pods no inician
```bash
make status          # Ver estado actual
make logs           # Ver logs de error
kubectl describe pods -n medi  # Detalles de pods
```

### Port forwarding falla
```bash
# Verificar servicios
kubectl get svc -n medi

# Reiniciar port forwards
pkill -f "kubectl port-forward"
make port-forward
```

### Telemetría no funciona
```bash
# Verificar collector
kubectl logs -n medi deployment/otel-collector

# Reiniciar aplicación
make restart

# Ejecutar pruebas
make test
```

## 🧹 Cleanup

```bash
# Limpiar namespace medi
make cleanup

# Limpiar Istio completamente (opcional)
istioctl uninstall --purge -y
kubectl delete namespace istio-system
```