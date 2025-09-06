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
# 1. Instalar Istio
make install-istio

# 2. Desplegar todo
make deploy-all

# 3. Verificar deployment
make status

# 4. Acceder a las UIs
make port-forward

# 5. Cleanup
make cleanup
```

## Acceso a UIs

- **Grafana**: http://localhost:3000 (admin/admin)
- **Zipkin**: http://localhost:9411
- **Prometheus**: http://localhost:9090
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