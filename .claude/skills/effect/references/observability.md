# Observability

Effect provides a comprehensive observability stack with integrated logging, metrics collection, and distributed tracing. These features are built into the core library with first-class OpenTelemetry support for production environments.

## Logging (Effect.log, Logger)

Effect's logging system provides structured, metadata-rich logs that go beyond simple console output.

### Basic Logging

```typescript
import { Effect } from "effect"

const program = Effect.gen(function* () {
  yield* Effect.log("Application started")
  yield* Effect.logDebug("Processing request")
  yield* Effect.logWarning("Rate limit approaching")
  yield* Effect.logError("Failed to connect")
})

Effect.runSync(program)
// timestamp=2024-07-16T10:02:28.453Z level=INFO fiber=#0 message="Application started"
```

Log functions by level:
- `Effect.log` / `Effect.logInfo` - General information
- `Effect.logDebug` - Debug details
- `Effect.logWarning` - Warnings
- `Effect.logError` - Errors
- `Effect.logFatal` - Fatal errors
- `Effect.logTrace` - Fine-grained tracing

### Log Levels

Control which logs appear using `Logger.withMinimumLogLevel`:

```typescript
import { Effect, Logger, LogLevel } from "effect"

const program = Effect.gen(function* () {
  yield* Effect.logDebug("Debug message")  // Won't appear
  yield* Effect.logInfo("Info message")    // Won't appear
  yield* Effect.logError("Error message")  // Will appear
})

// Only show Error level and above
Effect.runSync(Logger.withMinimumLogLevel(program, LogLevel.Error))
```

### Log Annotations

Add structured metadata to logs:

```typescript
import { Effect } from "effect"

const program = Effect.gen(function* () {
  yield* Effect.log("User action").pipe(
    Effect.annotateLogs({ userId: "123", action: "login" })
  )
})
// timestamp=... level=INFO fiber=#0 message="User action" userId=123 action=login
```

### Log Spans

Track timing with log spans:

```typescript
import { Effect } from "effect"

const program = Effect.gen(function* () {
  yield* Effect.sleep("100 millis")
  yield* Effect.log("Processing complete")
}).pipe(Effect.withLogSpan("processRequest"))
// timestamp=... level=INFO fiber=#0 message="Processing complete" processRequest=102ms
```

### Built-in Loggers

Effect provides several logger formats:

```typescript
import { Effect, Logger } from "effect"

const program = Effect.log("message").pipe(
  Effect.annotateLogs({ key: "value" })
)

// Default logfmt format
Effect.runFork(program)
// timestamp=... level=INFO fiber=#0 message=message key=value

// JSON format - great for log aggregation systems
Effect.runFork(program.pipe(Effect.provide(Logger.json)))
// {"message":"message","logLevel":"INFO","timestamp":"...","annotations":{"key":"value"},"fiberId":"#0"}

// Pretty format - colorized console output for development
Effect.runFork(program.pipe(Effect.provide(Logger.pretty)))
// [07:51:54.434] INFO (#0): message
//   key: value
```

### Custom Loggers

Create loggers that format or route logs as needed:

```typescript
import { Effect, Logger } from "effect"

// Create a custom logger
const customLogger = Logger.make(({ logLevel, message, annotations }) => {
  console.log(`[${logLevel.label}] ${message}`)
})

// Add alongside default logger
const withCustom = Logger.add(customLogger)

// Or replace the default logger entirely
const replaceDefault = Logger.replace(Logger.defaultLogger, customLogger)

const program = Effect.log("Hello").pipe(Effect.provide(replaceDefault))
Effect.runSync(program)
// [INFO] Hello
```

Logger options include:
- `logLevel` - The log level
- `message` - The log message
- `annotations` - Key-value annotations
- `spans` - Active log spans
- `date` - Timestamp
- `fiberId` - The fiber ID
- `cause` - Associated cause (for errors)

### Batched Logging

Group logs for efficient processing:

```typescript
import { Console, Effect, Logger } from "effect"

const LoggerLive = Logger.replaceScoped(
  Logger.defaultLogger,
  Logger.logfmtLogger.pipe(
    Logger.batched("500 millis", (messages) =>
      Console.log("BATCH", messages)
    )
  )
)

const program = Effect.gen(function* () {
  yield* Effect.log("one")
  yield* Effect.log("two")
  yield* Effect.log("three")
}).pipe(Effect.provide(LoggerLive))
```

## Metrics (Counter, Gauge, Histogram)

Effect provides built-in metric types for monitoring application behavior.

### Counter

Track cumulative values that only go up (or up/down):

```typescript
import { Effect, Metric } from "effect"

// Create a counter
const requestCounter = Metric.counter("http_requests_total", {
  description: "Total HTTP requests"
})

// Increment by 1
const handleRequest = Effect.gen(function* () {
  yield* Metric.increment(requestCounter)
  // ... handle request
})

// Increment by specific amount
const handleBatch = Effect.gen(function* () {
  yield* Metric.incrementBy(requestCounter, 10)
})
```

For monotonically increasing counters (can't go down):

```typescript
const monotonicCounter = Metric.counter("events_total", {
  incremental: true  // Only allows incrementing
})
```

### Gauge

Track values that can go up or down:

```typescript
import { Effect, Metric } from "effect"

const activeConnections = Metric.gauge("active_connections")

const program = Effect.gen(function* () {
  yield* Metric.set(activeConnections, 10)
  yield* Metric.set(activeConnections, 15)  // Value is now 15
  yield* Metric.set(activeConnections, 8)   // Value is now 8
})
```

### Timer

Measure durations automatically:

```typescript
import { Effect, Metric } from "effect"

const requestTimer = Metric.timer("http_request_duration")

const handleRequest = Effect.gen(function* () {
  yield* Effect.sleep("50 millis")  // Simulated work
  return "response"
}).pipe(Metric.trackDuration(requestTimer))
```

### Frequency

Track occurrences of distinct values:

```typescript
import { Effect, Metric } from "effect"

const statusCodes = Metric.frequency("http_status_codes")

const handleRequest = (statusCode: string) =>
  Metric.update(statusCodes, statusCode)

// Usage
Effect.runSync(handleRequest("200"))
Effect.runSync(handleRequest("404"))
Effect.runSync(handleRequest("200"))
// Tracks: { "200": 2, "404": 1 }
```

### Summary

Track distributions with quantiles:

```typescript
import { Effect, Metric } from "effect"

const responseSizes = Metric.summary({
  name: "response_size_bytes",
  maxAge: "1 days",
  maxSize: 1000,
  error: 0.01,
  quantiles: [0.5, 0.9, 0.99]  // p50, p90, p99
})

const recordSize = (size: number) =>
  Effect.succeed(size).pipe(Metric.trackSuccess(responseSizes))
```

### Metric Tags

Add dimensions to metrics for filtering and grouping:

```typescript
import { Effect, Metric } from "effect"

const counter = Metric.counter("requests")

const handleRequest = (endpoint: string, method: string) =>
  Metric.increment(counter).pipe(
    Effect.tagMetrics("endpoint", endpoint),
    Effect.tagMetrics("method", method)
  )

// These create separate time series:
// requests{endpoint="/users", method="GET"}
// requests{endpoint="/users", method="POST"}
```

## Tracing (spans, annotations)

Effect supports distributed tracing for understanding request flow across services.

### Creating Spans

Wrap operations in spans to track their execution:

```typescript
import { Effect } from "effect"

const fetchUser = (id: string) =>
  Effect.gen(function* () {
    yield* Effect.sleep("10 millis")
    return { id, name: "Alice" }
  }).pipe(Effect.withSpan("fetchUser"))

const fetchPosts = (userId: string) =>
  Effect.gen(function* () {
    yield* Effect.sleep("20 millis")
    return [{ id: 1, title: "Hello" }]
  }).pipe(Effect.withSpan("fetchPosts"))

const program = Effect.gen(function* () {
  const user = yield* fetchUser("123")
  const posts = yield* fetchPosts(user.id)
  return { user, posts }
}).pipe(Effect.withSpan("getUserWithPosts"))
// Creates: getUserWithPosts
//            ├── fetchUser
//            └── fetchPosts
```

### Span Attributes

Add metadata to spans:

```typescript
import { Effect } from "effect"

const fetchUser = (id: string) =>
  Effect.gen(function* () {
    return { id, name: "Alice" }
  }).pipe(
    Effect.withSpan("fetchUser", {
      attributes: { userId: id }
    })
  )
```

### Annotating Spans

Add annotations to all spans in a scope:

```typescript
import { Effect } from "effect"

const program = Effect.gen(function* () {
  yield* Effect.log("Processing")  // Span will have "requestId" annotation
}).pipe(
  Effect.withSpan("handleRequest"),
  Effect.annotateSpans("requestId", "abc-123")
)
```

### Span Kinds

Specify the type of span for better visualization:

```typescript
import { Effect } from "effect"

const dbQuery = Effect.gen(function* () {
  // query database
}).pipe(
  Effect.withSpan("sql.query", { kind: "client" })
)

const handleRequest = Effect.gen(function* () {
  // handle incoming request
}).pipe(
  Effect.withSpan("http.request", { kind: "server" })
)
```

## @effect/opentelemetry Integration

The `@effect/opentelemetry` package provides seamless integration with OpenTelemetry for production observability.

### Setup with Tracing

```typescript
import * as NodeSdk from "@effect/opentelemetry/NodeSdk"
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http"
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base"
import { Effect, Layer } from "effect"

const TracingLive = NodeSdk.layer(() => ({
  resource: {
    serviceName: "my-service"
  },
  spanProcessor: new BatchSpanProcessor(
    new OTLPTraceExporter({
      url: "http://localhost:4318/v1/traces"
    })
  )
}))

const program = Effect.gen(function* () {
  yield* Effect.log("Hello")
}).pipe(Effect.withSpan("main"))

program.pipe(
  Effect.provide(TracingLive),
  Effect.runFork
)
```

### Setup with Metrics

Export metrics to Prometheus or other backends:

```typescript
import * as NodeSdk from "@effect/opentelemetry/NodeSdk"
import { PrometheusExporter } from "@opentelemetry/exporter-prometheus"
import { Effect, Metric } from "effect"

const MetricsLive = NodeSdk.layer(() => ({
  resource: {
    serviceName: "my-service"
  },
  metricReader: new PrometheusExporter({ port: 9464 })
}))

const counter = Metric.counter("my_counter")

const program = Effect.gen(function* () {
  yield* Metric.increment(counter)
}).pipe(Effect.provide(MetricsLive))
```

### Combined Tracing and Metrics

```typescript
import * as NodeSdk from "@effect/opentelemetry/NodeSdk"
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http"
import { PrometheusExporter } from "@opentelemetry/exporter-prometheus"
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base"
import { Effect, Layer } from "effect"

const ObservabilityLive = NodeSdk.layer(() => ({
  resource: {
    serviceName: "my-service",
    version: "1.0.0"
  },
  spanProcessor: new BatchSpanProcessor(
    new OTLPTraceExporter({
      url: "http://localhost:4318/v1/traces"
    })
  ),
  metricReader: new PrometheusExporter({ port: 9464 })
}))
```

### Logs to OpenTelemetry

Send Effect logs to OpenTelemetry:

```typescript
import * as NodeSdk from "@effect/opentelemetry/NodeSdk"
import { SimpleLogRecordProcessor } from "@opentelemetry/sdk-logs"
import { OTLPLogExporter } from "@opentelemetry/exporter-logs-otlp-http"
import { Effect } from "effect"

const LoggingLive = NodeSdk.layer(() => ({
  resource: {
    serviceName: "my-service"
  },
  logRecordProcessor: [
    new SimpleLogRecordProcessor(
      new OTLPLogExporter({
        url: "http://localhost:4318/v1/logs"
      })
    )
  ]
}))

const program = Effect.gen(function* () {
  yield* Effect.log("This log goes to OpenTelemetry")
}).pipe(Effect.provide(LoggingLive))
```

### Configuration-based Setup

Load OpenTelemetry configuration from environment:

```typescript
import * as NodeSdk from "@effect/opentelemetry/NodeSdk"
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http"
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base"
import { Config, Effect, Layer, Redacted } from "effect"

const TracingLive = Layer.unwrapEffect(
  Effect.gen(function* () {
    const endpoint = yield* Config.option(
      Config.string("OTEL_EXPORTER_OTLP_ENDPOINT")
    )

    if (endpoint._tag === "None") {
      return Layer.empty  // No tracing configured
    }

    return NodeSdk.layer(() => ({
      resource: {
        serviceName: "my-service"
      },
      spanProcessor: new BatchSpanProcessor(
        new OTLPTraceExporter({
          url: `${endpoint.value}/v1/traces`
        })
      )
    }))
  })
)
```

### Full Example: Observable Service

```typescript
import * as NodeSdk from "@effect/opentelemetry/NodeSdk"
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http"
import { PrometheusExporter } from "@opentelemetry/exporter-prometheus"
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base"
import { Effect, Metric, Layer } from "effect"

// Define metrics
const requestCounter = Metric.counter("http_requests_total")
const requestDuration = Metric.timer("http_request_duration_ms")
const activeRequests = Metric.gauge("http_requests_active")

// Observable request handler
const handleRequest = (path: string) =>
  Effect.gen(function* () {
    yield* Metric.increment(requestCounter)
    yield* Metric.incrementBy(activeRequests, 1)

    yield* Effect.log("Handling request", { path })
    yield* Effect.sleep("50 millis")  // Simulated work

    yield* Metric.incrementBy(activeRequests, -1)
    return { status: 200, body: "OK" }
  }).pipe(
    Metric.trackDuration(requestDuration),
    Effect.withSpan("handleRequest", {
      attributes: { "http.path": path }
    }),
    Effect.tagMetrics("path", path)
  )

// Observability layer
const ObservabilityLive = NodeSdk.layer(() => ({
  resource: {
    serviceName: "api-server",
    version: "1.0.0"
  },
  spanProcessor: new BatchSpanProcessor(
    new OTLPTraceExporter()
  ),
  metricReader: new PrometheusExporter({ port: 9464 })
}))

// Run with observability
const main = Effect.gen(function* () {
  yield* handleRequest("/users")
  yield* handleRequest("/posts")
})

main.pipe(
  Effect.provide(ObservabilityLive),
  Effect.runFork
)
```

This setup gives you:
- Structured logs with context
- Distributed traces exported to your tracing backend
- Prometheus metrics at `http://localhost:9464/metrics`
- Automatic correlation between logs, traces, and metrics
