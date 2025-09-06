# Go Microservice with OpenTelemetry

A Go microservice with full observability instrumentation that sends metrics, traces, and logs to an OpenTelemetry collector.

## Features

- **Endpoints:**
  1. `GET /v1/ping` - Returns "pong"
  2. `POST /v1/purchase` - Returns a dummy purchase JSON response

- **Observability:**
  - **Metrics**: HTTP request counters and duration histograms sent via OTLP
  - **Traces**: Distributed tracing with automatic span creation
  - **Logs**: Structured JSON logs with trace correlation

## Configuration

The microservice uses environment variables for configuration:

- `OTEL_EXPORTER_OTLP_ENDPOINT`: OpenTelemetry collector endpoint (default: `otel-collector.go-service-obs.svc.cluster.local:4317`)
- `OTEL_SERVICE_NAME`: Service name for telemetry (default: `go-microservice`)
- `OTEL_SERVICE_VERSION`: Service version (default: `v1.0.0`)
- `PORT`: HTTP server port (default: `8080`)

## Building and Running

### Prerequisites
- Docker installed on your system
- Go 1.21+ (optional, only needed for local development without Docker)
- OpenTelemetry collector running and accessible

### Local Development

1. Build and run locally:
   ```bash
   go mod tidy
   go run main.go
   ```

2. Build Docker image locally:
   ```bash
   ./build-and-push.sh
   ```

### Kubernetes Deployment

1. Build and deploy to Kubernetes:
   ```bash
   # From the project root
   ./scripts/05-build-and-deploy-microservice.sh
   ```

2. Or manually:
   ```bash
   cd dummy-micro
   docker build -t go-microservice:otel-local .
   cd ../k8s
   kubectl apply -f 02-deployment.yaml
   ```

## API Endpoints

### Ping
- **URL**: `/v1/ping`
- **Method**: `GET`
- **Response**:
  ```
  pong
  ```

### Purchase
- **URL**: `/v1/purchase`
- **Method**: `POST`
- **Response**:
  ```json
  {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "item": "Sample Product",
    "amount": 99.99,
    "status": "completed",
    "message": "Purchase processed successfully"
  }
  ```
