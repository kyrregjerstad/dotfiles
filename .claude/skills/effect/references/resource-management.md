# Resource Management

Effect provides a structured approach to resource management through Scopes and the acquireRelease pattern. Unlike traditional try/finally blocks, Effect's resource management guarantees cleanup even during concurrent operations, integrates with the dependency system, and ensures resources are released in the correct order.

## Scopes

A `Scope` represents the lifetime of one or more resources. Think of it as a bucket where you register cleanup logic—when the scope closes, every registered finalizer runs.

### Key Properties of Scope Finalizers

1. **Finalizers receive the exit**: Check for success, failure, or interruption
2. **Finalizers run in reverse order**: Most recently acquired resource releases first

The reverse order matters for dependencies. If you open a network connection then fetch a file over it, the file must close before the connection drops.

### Why Scopes Over Simple Finalizers?

Effect already has finalizers like `Effect.onExit`, `Effect.ensuring`, and `Effect.onError`. Scopes solve a different problem: orchestrating cleanup across multiple effects with overlapping lifetimes.

Consider a request handler. Every child fiber working on that request might acquire database connections, open streams, or create other resources. Without scopes, each fiber's `Effect.onExit` runs independently—the parent could exit while a child still holds a connection. By extending all child effects into a single scope for the request, cleanup becomes deterministic: close the scope once, and all resources shut down in the correct order.

### Manual Scope Management

You can create and manage scopes directly:

```ts
import { Effect, Exit, Scope } from "effect"

const program = Effect.gen(function* () {
  const scope = yield* Scope.make()

  yield* Scope.addFinalizer(
    scope,
    Effect.log("closing network connection")
  )
  yield* Scope.addFinalizer(
    scope,
    Effect.log("closing remote file")
  )

  yield* Effect.log("doing work")

  yield* Scope.close(scope, Exit.void)
})

// Output:
// doing work
// closing remote file      ← Second finalizer runs first
// closing network connection
```

The problem: if the effect fails before `Scope.close`, finalizers never run and resources leak:

```ts
const leaky = Effect.gen(function* () {
  const scope = yield* Scope.make()
  yield* Scope.addFinalizer(scope, Effect.log("cleanup"))

  yield* Effect.fail("boom")  // Scope.close never reached!

  yield* Scope.close(scope, Exit.void)
})
// Finalizer never runs—resource leaked
```

### Effect.scoped

`Effect.scoped` eliminates this problem. It creates a scope, runs your effect, and guarantees the scope closes regardless of success, failure, or interruption:

```ts
const safe = Effect.gen(function* () {
  yield* Effect.addFinalizer(() => Effect.log("cleanup"))
  yield* Effect.fail("boom")
}).pipe(Effect.scoped)

// Output:
// cleanup  ← Always runs
```

`Effect.addFinalizer` adds a finalizer to the current scope (accessed implicitly). The `Effect.scoped` wrapper ensures that scope closes properly.

### Accessing the Current Scope

Inside a scoped workflow, access the scope with `Effect.scope`:

```ts
const program = Effect.gen(function* () {
  const scope = yield* Effect.scope  // Get current scope

  yield* Scope.addFinalizer(
    scope,
    Effect.log("cleanup via explicit scope reference")
  )
}).pipe(Effect.scoped)
```

This is rarely needed directly—prefer `Effect.addFinalizer` for conciseness.

## acquireRelease Pattern

`Effect.acquireRelease` bundles resource acquisition and cleanup into a single declaration:

```ts
const resource = Effect.acquireRelease(
  acquire,           // Effect that obtains the resource
  (resource, exit) => release(resource)  // Cleanup function
)
```

### Basic Usage

```ts
import { Effect } from "effect"

interface FileHandle {
  read: () => Promise<string>
  close: () => Promise<void>
}

declare const openFile: (path: string) => Effect.Effect<FileHandle>

const file = Effect.acquireRelease(
  openFile("/data/report.txt"),
  (handle) => Effect.promise(() => handle.close())
)
```

The returned effect requires a `Scope` and produces the `FileHandle`. Release is guaranteed when the scope closes.

### Using the Resource

Since `acquireRelease` adds a `Scope` requirement, wrap the usage with `Effect.scoped`:

```ts
const program = Effect.gen(function* () {
  const handle = yield* file
  const content = yield* Effect.promise(() => handle.read())
  return content
}).pipe(Effect.scoped)

// handle.close() automatically called when scope ends
```

### Exit-Aware Cleanup

The release function receives the `Exit` status, enabling conditional cleanup:

```ts
import { Exit } from "effect"

const connection = Effect.acquireRelease(
  openConnection,
  (conn, exit) =>
    Exit.isSuccess(exit)
      ? Effect.log("connection closed normally").pipe(
          Effect.andThen(conn.close())
        )
      : Effect.log("connection closed due to error").pipe(
          Effect.andThen(conn.rollback()),
          Effect.andThen(conn.close())
        )
)
```

### acquireUseRelease

When you need a resource for exactly one operation and don't want it lingering in scope, use `Effect.acquireUseRelease`:

```ts
const readReport = Effect.acquireUseRelease(
  openFile("/data/report.txt"),
  (handle) => Effect.promise(() => handle.read()),
  (handle) => Effect.promise(() => handle.close())
)
// Type: Effect<string, never, never>
// No Scope requirement—fully self-contained
```

The three parameters: acquire, use, release. The use function receives the resource and must return an Effect.

**When to use which:**

- `acquireRelease`: Resource used across multiple steps, passed around, or kept available in scope
- `acquireUseRelease`: Resource needed for one block of work, then immediately released

### Real-World Example: Database Layer

```ts
import { Effect, Layer } from "effect"
import { SqlClient, SqlError } from "@effect/sql"

class Database extends Effect.Service<Database>()("@app/Database", {
  scoped: Effect.gen(function* () {
    const pool = yield* createConnectionPool({
      host: "localhost",
      poolSize: 10
    })

    yield* Effect.addFinalizer(() =>
      Effect.gen(function* () {
        yield* Effect.log("Closing database pool...")
        yield* Effect.promise(() => pool.end())
      })
    )

    return {
      query: (sql: string) => Effect.tryPromise({
        try: () => pool.query(sql),
        catch: (cause) => new SqlError({ cause, message: "Query failed" })
      })
    }
  })
}) {}
```

Or using `acquireRelease` directly:

```ts
class Database extends Effect.Service<Database>()("@app/Database", {
  scoped: Effect.acquireRelease(
    createConnectionPool({ host: "localhost", poolSize: 10 }),
    (pool) => Effect.promise(() => pool.end())
  ).pipe(
    Effect.map((pool) => ({
      query: (sql: string) => Effect.tryPromise({
        try: () => pool.query(sql),
        catch: (cause) => new SqlError({ cause, message: "Query failed" })
      })
    }))
  )
}) {}
```

### Test Containers Example

A practical pattern for integration tests—wrap testcontainers in acquireRelease:

```ts
import { Effect, Layer } from "effect"
import { PostgreSqlContainer } from "@testcontainers/postgresql"

class PgContainer extends Effect.Service<PgContainer>()("@test/PgContainer", {
  scoped: Effect.acquireRelease(
    Effect.promise(() => new PostgreSqlContainer("postgres:alpine").start()),
    (container) => Effect.promise(() => container.stop())
  )
}) {}

// Usage in tests
const TestDatabaseLive = Layer.unwrapEffect(
  Effect.gen(function* () {
    const container = yield* PgContainer
    return Database.layer({
      url: container.getConnectionUri()
    })
  })
).pipe(Layer.provide(PgContainer.Default))
```

## Forking into Scopes

When forking fibers that should be tied to a scope's lifetime, use `Effect.forkScoped`:

```ts
const heartbeat = Effect.gen(function* () {
  yield* Effect.log("ping")
}).pipe(Effect.repeat({ schedule: Schedule.spaced("5 seconds") }))

const program = Effect.gen(function* () {
  yield* Effect.forkScoped(heartbeat)  // Fiber tied to current scope
  yield* doMainWork()
}).pipe(Effect.scoped)
// Heartbeat fiber automatically interrupted when scope closes
```

For explicit scope targeting, use `Effect.forkIn`:

```ts
const program = Effect.gen(function* () {
  const scope = yield* Scope.make()
  yield* Effect.forkIn(heartbeat, scope)  // Fork into specific scope

  yield* doWork()
  yield* Scope.close(scope, Exit.void)  // Manually control fiber lifetime
})
```

## Sequential vs Parallel Finalizers

By default, finalizers run sequentially in reverse order. For independent resources, run them in parallel:

```ts
const program = Effect.gen(function* () {
  // These finalizers can run in parallel
  yield* Effect.parallelFinalizers(
    Effect.acquireRelease(openResource1, closeResource1)
  )
  yield* Effect.parallelFinalizers(
    Effect.acquireRelease(openResource2, closeResource2)
  )
}).pipe(Effect.scoped)
```

Or mark individual resource groups as parallel:

```ts
const program = Effect.gen(function* () {
  const [r1, r2] = yield* Effect.all([resource1, resource2], {
    concurrentFinalizers: true
  })
  // r1 and r2 finalizers run in parallel at scope close
})
```

## Early Release

Sometimes you need to release a resource before scope end. Use `Effect.withEarlyRelease`:

```ts
const program = Effect.gen(function* () {
  // Get both the release function and the resource
  const [releaseFile, handle] = yield* Effect.withEarlyRelease(file)

  const content = yield* Effect.promise(() => handle.read())

  // Release early—before scope closes
  yield* releaseFile

  // Continue with other work...
  yield* processContent(content)
}).pipe(Effect.scoped)
```

## Finalizer Utilities

For simpler cleanup needs, Effect provides focused utilities:

```ts
// Always runs, no access to outcome
Effect.ensuring(Effect.log("cleanup"))

// Runs only on error, receives Cause
Effect.onError((cause) => Effect.log(`failed: ${cause}`))

// Runs only on interruption
Effect.onInterrupt(() => Effect.log("interrupted"))

// Always runs, receives Exit
Effect.onExit((exit) =>
  Exit.match(exit, {
    onSuccess: (value) => Effect.log(`succeeded with ${value}`),
    onFailure: (cause) => Effect.log(`failed with ${cause}`)
  })
)
```

Use these for single-effect cleanup. Use Scopes and `acquireRelease` for multi-step resource workflows.

## Scope Integration with Layers

`Layer.scoped` creates layers that participate in scope lifecycle:

```ts
const DatabaseLive = Layer.scoped(
  Database,
  Effect.gen(function* () {
    const conn = yield* openDatabaseConnection()

    yield* Effect.addFinalizer(() =>
      Effect.sync(() => conn.close())
    )

    return { query: (sql) => conn.execute(sql) }
  })
)
```

The finalizer runs when the layer's scope closes—typically at program shutdown or when a `ManagedRuntime` is disposed.

For background processes in layers, always use `Effect.forkScoped`:

```ts
const HealthChecker = Layer.scoped(
  HealthCheck,
  Effect.gen(function* () {
    yield* Effect.forkScoped(
      checkHealth().pipe(
        Effect.repeat({ schedule: Schedule.spaced("30 seconds") })
      )
    )

    return { status: () => Effect.succeed("ok") }
  })
)
```

The forked fiber automatically stops when the layer's scope closes.
