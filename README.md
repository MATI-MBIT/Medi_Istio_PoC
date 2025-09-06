# Istio + OpenTelemetry PoC

Prueba de concepto completa con Kubernetes, Istio y OpenTelemetry para observabilidad.

## Prerequisitos

- Minikube con Docker driver
- kubectl
- istioctl (v1.26.2)
- make

## Arquitectura

- **Microservicio**: `docker.io/aira18/go-microservice:latest`
- **Service Mesh**: Istio con mTLS permissive
- **Observabilidad**: OpenTelemetry Collector
- **Monitoreo**: Prometheus + Loki + Zipkin + Grafana
- **Namespace**: `medi`

## Endpoints del Microservicio

- `GET /v1/ping` → "pong"
- `POST /v1/purchase` → Procesa compra y retorna JSON

## Quick Start

```bash
# 1. Desplegar todo
make deploy-all

# 2. Verificar deployment
make status

# 3. Acceder a las UIs
make port-forward

# 4. Cleanup
make cleanup
```

## Acceso a UIs

- **Grafana**: http://localhost:3000 (admin/admin)
- **Zipkin**: http://localhost:9411
- **Prometheus**: http://localhost:9090
- **Loki**: http://localhost:3100/log_level
- **Microservicio**: http://localhost:8080

## Testing

```bash
# Test ping
curl http://localhost:8080/v1/ping

# Test purchase
curl -X POST http://localhost:8080/v1/purchase \
  -H "Content-Type: application/json" \
  -d '{"item":"test","amount":100}'
```