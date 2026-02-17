# Configuration

Effect's `Config` module provides type-safe configuration loading with validation, defaults, and transformations. By default, configuration is read from environment variables, but the source can be swapped using `ConfigProvider`.

## Config & ConfigProvider

### Config Primitives

The `Config` module provides primitives for common configuration types:

```ts
import { Config, Effect } from "effect"

const program = Effect.gen(function* () {
  // Strings
  const apiUrl = yield* Config.string("API_URL")

  // Numbers
  const port = yield* Config.integer("PORT")
  const ratio = yield* Config.number("RATIO")

  // Booleans
  const debug = yield* Config.boolean("DEBUG")

  // URLs (returns URL object)
  const endpoint = yield* Config.url("ENDPOINT")

  // Durations (parses "10 seconds", "5 minutes", etc.)
  const timeout = yield* Config.duration("TIMEOUT")

  // Literal values (constrained to specific strings)
  const env = yield* Config.literal("dev", "staging", "prod")("ENV")

  return { apiUrl, port, debug, endpoint, timeout, env }
})
```

Reading configuration is an effectful operation that may fail, so it uses `yield*`. Missing or invalid configuration adds `ConfigError` to the error channel.

### Defaults and Fallbacks

Use `Config.withDefault` or `Config.orElse` for optional configuration:

```ts
import { Config, Effect } from "effect"

const program = Effect.gen(function* () {
  // Simple default value
  const port = yield* Config.integer("PORT").pipe(
    Config.withDefault(3000)
  )

  // Fallback to another config
  const host = yield* Config.string("HOST").pipe(
    Config.orElse(() => Config.succeed("localhost"))
  )

  // Optional values (returns Option<T>)
  const debugMode = yield* Config.option(Config.boolean("DEBUG"))

  return { port, host, debugMode }
})
```

### Composing Configurations

Use `Config.all` to combine multiple configs into a structured object:

```ts
import { Config, Effect } from "effect"

const serverConfig = Config.all({
  host: Config.string("HOST").pipe(Config.withDefault("localhost")),
  port: Config.integer("PORT").pipe(Config.withDefault(3000)),
  debug: Config.boolean("DEBUG").pipe(Config.withDefault(false))
})

const program = Effect.gen(function* () {
  const config = yield* serverConfig
  console.log(`Server: ${config.host}:${config.port}`)
})
```

### Nested Configuration

Use `Config.nested` to read from prefixed environment variables:

```ts
import { Config, Effect } from "effect"

// Reads from DB_HOST, DB_PORT, DB_NAME
const dbConfig = Config.all({
  host: Config.string("HOST"),
  port: Config.integer("PORT"),
  name: Config.string("NAME")
}).pipe(Config.nested("DB"))

const program = Effect.gen(function* () {
  const db = yield* dbConfig
  console.log(`Database: ${db.host}:${db.port}/${db.name}`)
})
```

### Array Configuration

Read comma-separated values as arrays:

```ts
import { Config, Effect } from "effect"

// TAGS="foo,bar,baz" becomes ["foo", "bar", "baz"]
const tagsConfig = Config.array(Config.string(), "TAGS")

const program = Effect.gen(function* () {
  const tags = yield* tagsConfig
  console.log(`Tags: ${tags.join(", ")}`)
})
```

### Transforming Configuration

Use `Config.map` to transform values:

```ts
import { Config, Effect } from "effect"

const program = Effect.gen(function* () {
  const baseUrl = yield* Config.url("API_URL").pipe(
    Config.map((url) => url.toString().replace(/\/$/, ""))
  )
  return baseUrl
})
```

### Validation with Schema

Use `Schema.Config` for rich validation:

```ts
import { Config, Effect, Schema } from "effect"

const Port = Schema.NumberFromString.pipe(
  Schema.int(),
  Schema.between(1, 65535)
)

const Environment = Schema.Literal("development", "staging", "production")

const program = Effect.gen(function* () {
  const port = yield* Schema.Config("PORT", Port)
  const env = yield* Schema.Config("ENV", Environment)
  return { port, env }
})
```

Schema validation provides:
- Automatic type inference
- Rich error messages
- Reusable validation logic
- Support for branded types and transformations

### ConfigProvider

By default, Effect reads configuration from environment variables. Use `ConfigProvider` to change the source:

```ts
import { Config, ConfigProvider, Effect, Layer } from "effect"

const program = Effect.gen(function* () {
  const port = yield* Config.integer("PORT")
  const apiKey = yield* Config.string("API_KEY")
  return { port, apiKey }
})

// From a Map (useful for testing)
const testProvider = ConfigProvider.fromMap(
  new Map([
    ["PORT", "3000"],
    ["API_KEY", "test-key"]
  ])
)

// From JSON
const jsonProvider = ConfigProvider.fromJson({
  PORT: 8080,
  API_KEY: "prod-key"
})

// From env with prefix (reads APP_PORT, APP_API_KEY)
const prefixedProvider = ConfigProvider.fromEnv().pipe(
  ConfigProvider.nested("APP")
)

// Apply provider via Layer
const testConfigLayer = Layer.setConfigProvider(testProvider)

Effect.runPromise(
  program.pipe(Effect.provide(testConfigLayer))
)
```

### Recommended Pattern: Config as a Service

Create a config service with a layer for clean dependency injection:

```ts
import { Config, Context, Effect, Layer, Redacted } from "effect"

class AppConfig extends Context.Tag("AppConfig")<
  AppConfig,
  {
    readonly port: number
    readonly apiKey: Redacted.Redacted
    readonly baseUrl: string
  }
>() {
  // Production layer - reads from environment
  static readonly Live = Layer.effect(
    AppConfig,
    Effect.gen(function* () {
      return {
        port: yield* Config.integer("PORT").pipe(Config.withDefault(3000)),
        apiKey: yield* Config.redacted("API_KEY"),
        baseUrl: yield* Config.string("BASE_URL").pipe(
          Config.withDefault("https://api.example.com")
        )
      }
    })
  )

  // Test layer - hardcoded values
  static readonly Test = Layer.succeed(AppConfig, {
    port: 3000,
    apiKey: Redacted.make("test-key"),
    baseUrl: "http://localhost:3000"
  })
}

// Usage
const program = Effect.gen(function* () {
  const config = yield* AppConfig
  console.log(`Starting on port ${config.port}`)
})

// Production
program.pipe(Effect.provide(AppConfig.Live))

// Tests - just swap the layer
program.pipe(Effect.provide(AppConfig.Test))
```

This pattern:
- Separates config loading from business logic
- Makes testing easy by swapping layers
- Catches config errors early at startup
- Provides full type safety

## Handling Secrets (Redacted)

Use `Config.redacted` for sensitive values like API keys, passwords, and tokens:

```ts
import { Config, Effect, Redacted } from "effect"

const program = Effect.gen(function* () {
  // Type is Redacted<string>, not string
  const apiKey = yield* Config.redacted("API_KEY")
  const dbPassword = yield* Config.redacted("DB_PASSWORD")

  // Redacted values are hidden when logged
  console.log(apiKey) // Output: <redacted>

  // Must explicitly unwrap to use the value
  const headers = {
    Authorization: `Bearer ${Redacted.value(apiKey)}`
  }

  return headers
})
```

### Why Redacted Matters

`Redacted` provides compile-time protection against accidental secret exposure:

```ts
import { Config, Effect, Redacted } from "effect"

const sendToAnalytics = (data: string) => {
  // Imagine this sends data somewhere...
}

const program = Effect.gen(function* () {
  const secret = yield* Config.redacted("SECRET")

  // ❌ Type error: Redacted<string> is not assignable to string
  sendToAnalytics(secret)

  // ✅ Must be explicit about extracting the value
  sendToAnalytics(Redacted.value(secret))
})
```

### Creating Redacted Values

You can create `Redacted` values directly:

```ts
import { Redacted } from "effect"

// Create from a string
const secret = Redacted.make("my-secret-value")

// Extract when needed
const value = Redacted.value(secret) // "my-secret-value"

// Safe to log
console.log(secret) // <redacted>
console.log(`Secret: ${secret}`) // Secret: <redacted>
```

### Redacted in Service Definitions

When defining config services, use `Redacted` types for secrets:

```ts
import { Config, Context, Effect, Layer, Redacted, Schema } from "effect"

class DatabaseConfig extends Context.Tag("DatabaseConfig")<
  DatabaseConfig,
  {
    readonly host: string
    readonly port: number
    readonly database: string
    readonly password: Redacted.Redacted
  }
>() {
  static readonly Live = Layer.effect(
    DatabaseConfig,
    Effect.gen(function* () {
      return {
        host: yield* Config.string("DB_HOST"),
        port: yield* Config.integer("DB_PORT").pipe(Config.withDefault(5432)),
        database: yield* Config.string("DB_NAME"),
        password: yield* Config.redacted("DB_PASSWORD")
      }
    })
  )
}

// Or with Schema for redacted values
const configWithSchema = Effect.gen(function* () {
  const password = yield* Schema.Config(
    "DB_PASSWORD",
    Schema.Redacted(Schema.String)
  )
  return password
})
```

### Complete Example: Environment Variables Service

```ts
import * as Config from "effect/Config"
import * as Effect from "effect/Effect"

class EnvVars extends Effect.Service<EnvVars>()("EnvVars", {
  accessors: true,
  effect: Effect.gen(function* () {
    return {
      // Server
      PORT: yield* Config.integer("PORT").pipe(Config.withDefault(3000)),
      ENV: yield* Config.literal("dev", "prod", "staging")("ENV").pipe(
        Config.withDefault("dev")
      ),
      APP_URL: yield* Config.url("APP_URL").pipe(
        Config.map((url) => url.toString()),
        Config.withDefault("http://localhost:5173")
      ),

      // Database
      DATABASE_URL: yield* Config.redacted("DATABASE_URL"),

      // Observability
      OTLP_URL: yield* Config.url("OTLP_URL").pipe(
        Config.withDefault("http://localhost:4318/v1/traces")
      )
    } as const
  })
}) {}

// Usage with accessors
const program = Effect.gen(function* () {
  const port = yield* EnvVars.PORT
  const env = yield* EnvVars.ENV
  console.log(`Running in ${env} on port ${port}`)
})

program.pipe(Effect.provide(EnvVars.Default))
```

### Testing with Configuration

In tests, provide configuration values directly without needing `ConfigProvider`:

```ts
import { Context, Effect, Layer, Redacted } from "effect"
import { it } from "@effect/vitest"

class ApiConfig extends Context.Tag("ApiConfig")<
  ApiConfig,
  { readonly apiKey: Redacted.Redacted; readonly baseUrl: string }
>() {}

const fetchUser = (id: string) =>
  Effect.gen(function* () {
    const config = yield* ApiConfig
    // ... fetch logic using config.baseUrl and config.apiKey
    return { id, name: "Test User" }
  })

it.effect("fetches user with test config", () =>
  Effect.gen(function* () {
    const result = yield* fetchUser("123")
    expect(result.name).toBe("Test User")
  }).pipe(
    Effect.provide(
      Layer.succeed(ApiConfig, {
        apiKey: Redacted.make("test-key"),
        baseUrl: "http://localhost:3000"
      })
    )
  )
)
```
