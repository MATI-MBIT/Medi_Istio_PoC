package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

type PurchaseResponse struct {
	ID      string  `json:"id"`
	Item    string  `json:"item"`
	Amount  float64 `json:"amount"`
	Status  string  `json:"status"`
	Message string  `json:"message"`
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

var (
	logger           *zap.Logger
	tracer           trace.Tracer
	meter            metric.Meter
	httpRequestsTotal metric.Int64Counter
	httpDuration     metric.Float64Histogram
)

func initLogger() {
	config := zap.NewProductionConfig()
	config.EncoderConfig.TimeKey = "timestamp"
	config.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
	
	var err error
	logger, err = config.Build()
	if err != nil {
		panic(fmt.Sprintf("Failed to initialize logger: %v", err))
	}
}

func initResource() *resource.Resource {
	serviceName := getEnv("OTEL_SERVICE_NAME", "go-microservice")
	serviceVersion := getEnv("OTEL_SERVICE_VERSION", "v1.0.0")
	
	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			"http://opentelemetry.io/schemas/1.17.0",
			attribute.String("service.name", serviceName),
			attribute.String("service.version", serviceVersion),
			attribute.String("deployment.environment", "production"),
		),
	)
	if err != nil {
		logger.Fatal("Failed to create resource", zap.Error(err))
	}
	return res
}

func initTracing(ctx context.Context, res *resource.Resource) func() {
	otlpEndpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector.go-service-obs.svc.cluster.local:4317")
	
	conn, err := grpc.DialContext(ctx, otlpEndpoint,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	)
	if err != nil {
		logger.Fatal("Failed to create gRPC connection to collector", zap.Error(err))
	}

	traceExporter, err := otlptracegrpc.New(ctx, otlptracegrpc.WithGRPCConn(conn))
	if err != nil {
		logger.Fatal("Failed to create trace exporter", zap.Error(err))
	}

	bsp := sdktrace.NewBatchSpanProcessor(traceExporter)
	tracerProvider := sdktrace.NewTracerProvider(
		sdktrace.WithSampler(sdktrace.TraceIDRatioBased(0.1)),
		sdktrace.WithResource(res),
		sdktrace.WithSpanProcessor(bsp),
	)

	otel.SetTracerProvider(tracerProvider)
	otel.SetTextMapPropagator(propagation.TraceContext{})

	tracer = otel.Tracer("go-microservice")

	return func() {
		if err := tracerProvider.Shutdown(ctx); err != nil {
			logger.Error("Error shutting down tracer provider", zap.Error(err))
		}
	}
}

func initMetrics(ctx context.Context, res *resource.Resource) func() {
	otlpEndpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector.go-service-obs.svc.cluster.local:4317")
	
	conn, err := grpc.DialContext(ctx, otlpEndpoint,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	)
	if err != nil {
		logger.Fatal("Failed to create gRPC connection to collector", zap.Error(err))
	}

	metricExporter, err := otlpmetricgrpc.New(ctx, otlpmetricgrpc.WithGRPCConn(conn))
	if err != nil {
		logger.Fatal("Failed to create metric exporter", zap.Error(err))
	}

	meterProvider := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter,
			sdkmetric.WithInterval(30*time.Second))),
	)

	otel.SetMeterProvider(meterProvider)
	meter = otel.Meter("go-microservice")

	// Create metrics
	httpRequestsTotal, err = meter.Int64Counter(
		"http_requests_total",
		metric.WithDescription("Total number of HTTP requests"),
	)
	if err != nil {
		logger.Fatal("Failed to create http_requests_total counter", zap.Error(err))
	}

	httpDuration, err = meter.Float64Histogram(
		"http_request_duration_seconds",
		metric.WithDescription("Duration of HTTP requests"),
		metric.WithUnit("s"),
	)
	if err != nil {
		logger.Fatal("Failed to create http_request_duration_seconds histogram", zap.Error(err))
	}

	return func() {
		if err := meterProvider.Shutdown(ctx); err != nil {
			logger.Error("Error shutting down meter provider", zap.Error(err))
		}
	}
}

func instrumentationMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		
		// Create span
		ctx, span := tracer.Start(r.Context(), fmt.Sprintf("%s %s", r.Method, r.URL.Path))
		defer span.End()

		// Add span attributes
		span.SetAttributes(
			attribute.String("http.method", r.Method),
			attribute.String("http.url", r.URL.String()),
			attribute.String("http.scheme", r.URL.Scheme),
			attribute.String("http.host", r.Host),
			attribute.String("http.user_agent", r.UserAgent()),
		)

		// Wrap response writer to capture status code
		rw := &responseWriter{ResponseWriter: w, statusCode: 200}
		
		// Execute handler with context
		next.ServeHTTP(rw, r.WithContext(ctx))
		
		// Calculate duration
		duration := time.Since(start).Seconds()
		
		// Add more span attributes
		span.SetAttributes(
			attribute.Int("http.status_code", rw.statusCode),
			attribute.Float64("http.duration", duration),
		)

		// Record metrics
		httpRequestsTotal.Add(ctx, 1,
			metric.WithAttributes(
				attribute.String("method", r.Method),
				attribute.String("endpoint", r.URL.Path),
				attribute.String("status", strconv.Itoa(rw.statusCode)),
			),
		)

		httpDuration.Record(ctx, duration,
			metric.WithAttributes(
				attribute.String("method", r.Method),
				attribute.String("endpoint", r.URL.Path),
			),
		)

		// Structured logging with trace context
		traceID := span.SpanContext().TraceID().String()
		spanID := span.SpanContext().SpanID().String()
		
		logger.Info("HTTP request",
			zap.String("method", r.Method),
			zap.String("path", r.URL.Path),
			zap.Int("status", rw.statusCode),
			zap.Float64("duration", duration),
			zap.String("trace_id", traceID),
			zap.String("span_id", spanID),
			zap.String("user_agent", r.UserAgent()),
		)
	})
}

func pingHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	_, span := tracer.Start(ctx, "ping_handler")
	defer span.End()

	if r.Method != http.MethodGet {
		span.SetAttributes(attribute.String("error", "method_not_allowed"))
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	logger.Info("Ping endpoint called", 
		zap.String("trace_id", span.SpanContext().TraceID().String()))
	
	w.Header().Set("Content-Type", "text/plain")
	w.Write([]byte("pong\n"))
}

func purchaseHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	_, span := tracer.Start(ctx, "purchase_handler")
	defer span.End()

	if r.Method != http.MethodPost {
		span.SetAttributes(attribute.String("error", "method_not_allowed"))
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	response := PurchaseResponse{
		ID:      "123e4567-e89b-12d3-a456-426614174000",
		Item:    "Sample Product",
		Amount:  99.99,
		Status:  "completed",
		Message: "Purchase processed successfully",
	}

	span.SetAttributes(
		attribute.String("purchase.id", response.ID),
		attribute.String("purchase.item", response.Item),
		attribute.Float64("purchase.amount", response.Amount),
		attribute.String("purchase.status", response.Status),
	)

	logger.Info("Purchase processed",
		zap.String("purchase_id", response.ID),
		zap.Float64("amount", response.Amount),
		zap.String("trace_id", span.SpanContext().TraceID().String()))

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	// Initialize logger first
	initLogger()
	defer logger.Sync()

	ctx := context.Background()
	
	// Initialize resource
	res := initResource()
	
	// Initialize tracing
	shutdownTracing := initTracing(ctx, res)
	defer shutdownTracing()
	
	// Initialize metrics
	shutdownMetrics := initMetrics(ctx, res)
	defer shutdownMetrics()

	logger.Info("OpenTelemetry initialized successfully")

	// Setup HTTP routes
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/ping", pingHandler)
	mux.HandleFunc("/v1/purchase", purchaseHandler)

	// Apply instrumentation middleware
	handler := instrumentationMiddleware(mux)

	port := getEnv("PORT", "8080")
	logger.Info("Server starting", zap.String("port", port))
	
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		logger.Fatal("Server failed to start", zap.Error(err))
	}
}
