module github.com/yourusername/go-microservice

go 1.21

require (
	go.opentelemetry.io/otel v1.19.0
	go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc v0.42.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.19.0
	go.opentelemetry.io/otel/sdk v1.19.0
	go.opentelemetry.io/otel/sdk/metric v1.19.0
	go.opentelemetry.io/otel/sdk/resource v1.19.0
	go.opentelemetry.io/otel/semconv/v1.17.0 v1.17.0
	go.uber.org/zap v1.26.0
	google.golang.org/grpc v1.58.3
)
