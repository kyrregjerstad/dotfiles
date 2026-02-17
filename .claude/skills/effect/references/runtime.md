# Runtime

The Runtime is the execution engine that powers Effect programs. While you often interact with it implicitly through `Effect.runSync` and `Effect.runPromise`, understanding the Runtime gives you fine-grained control over how effects execute—essential for application architecture.

## The Runtime Object

A `Runtime<R>` encapsulates everything needed to execute effects:

```typescript
interface Runtime<R> {
  readonly context: Context<R>        // Services available to effects
  readonly runtimeFlags: RuntimeFlags // Execution behavior flags
  readonly fiberRefs: FiberRefs       // Fiber-local state defaults
}
```

The type parameter `R` represents the services this runtime provides. Effects requiring those services can run without additional dependencies.

### Default Runtime

Effect provides a default runtime with no services:

```typescript
import { Effect, Runtime } from "effect"

// These are equivalent:
Effect.runSync(Effect.succeed(42))
Runtime.runSync(Runtime.defaultRuntime)(Effect.succeed(42))
```

### Creating Custom Runtimes

Build custom runtimes by modifying the default:

```typescript
import { Context, Runtime, FiberRef } from "effect"

class Logger extends Context.Tag("Logger")<Logger, { log: (msg: string) => void }>() {}

// Add a service
const runtimeWithLogger = Runtime.defaultRuntime.pipe(
  Runtime.provideService(Logger, { log: console.log })
)

// Set a FiberRef default
const ref = FiberRef.unsafeMake(100)
const runtimeWithRef = Runtime.defaultRuntime.pipe(
  Runtime.setFiberRef(ref, 200)
)

// Run with the custom runtime
const result = Runtime.runSync(runtimeWithLogger)(Logger)
// { log: [Function] }
```

### Running Effects with Custom Runtimes

All run functions work with explicit runtimes:

```typescript
import { Effect, Runtime, Exit } from "effect"

const runtime = Runtime.defaultRuntime

// Sync execution
const a = Runtime.runSync(runtime)(Effect.succeed(1))

// Sync with exit
const b = Runtime.runSyncExit(runtime)(Effect.fail("error"))
// Exit.fail("error")

// Async execution
const c = await Runtime.runPromise(runtime)(Effect.succeed(1))

// Async with exit
const d = await Runtime.runPromiseExit(runtime)(Effect.fail("error"))
// Exit.fail("error")

// Fork a fiber
const fiber = Runtime.runFork(runtime)(Effect.succeed(1))
```

### AbortSignal Support

Cancel running effects with an `AbortSignal`:

```typescript
import { Effect, Runtime, Exit } from "effect"

const controller = new AbortController()

// Cancel after 100ms
setTimeout(() => controller.abort(), 100)

const exit = await Runtime.runPromiseExit(
  Runtime.defaultRuntime,
  Effect.sleep("10 seconds"),
  { signal: controller.signal }
)

Exit.isInterrupted(exit) // true
```

## ManagedRuntime for Applications

`ManagedRuntime` combines a Layer with a Runtime, managing service lifecycle automatically. This is the standard pattern for Effect applications.

### Basic Usage

```typescript
import { Effect, Layer, ManagedRuntime, Console } from "effect"

class Notifications extends Effect.Tag("Notifications")<
  Notifications,
  { notify: (msg: string) => Effect.Effect<void> }
>() {
  static Live = Layer.succeed(this, {
    notify: (msg) => Console.log(`Notification: ${msg}`)
  })
}

// Create a managed runtime from a layer
const AppRuntime = ManagedRuntime.make(Notifications.Live)

async function main() {
  // Run effects with pre-built services
  await AppRuntime.runPromise(
    Notifications.notify("Hello!")
  )

  // Clean up when done
  await AppRuntime.dispose()
}
```

### Lazy Construction

Layers are built lazily on first effect execution, not when calling `ManagedRuntime.make`:

```typescript
const runtime = ManagedRuntime.make(
  Layer.effectDiscard(Console.log("Building layer"))
)

// Nothing printed yet

await runtime.runPromise(Effect.void)
// "Building layer" - now it's constructed

await runtime.runPromise(Effect.void)
// Nothing - already cached
```

To eagerly build layers (e.g., on app startup):

```typescript
const runtime = ManagedRuntime.make(AppLayer)
await runtime.runPromise(Effect.void) // Force construction
```

### ManagedRuntime Methods

ManagedRuntime provides the same run methods as Runtime:

```typescript
const runtime = ManagedRuntime.make(AppLayer)

// All standard run methods
runtime.runSync(effect)
runtime.runSyncExit(effect)
runtime.runPromise(effect)
runtime.runPromiseExit(effect)
runtime.runFork(effect)
runtime.runCallback(effect, { onExit: (exit) => {} })

// Lifecycle
await runtime.dispose()       // Async cleanup
runtime.disposeEffect         // As an Effect
```

### Accessing the Runtime

ManagedRuntime itself is an Effect that yields the underlying Runtime:

```typescript
const managedRuntime = ManagedRuntime.make(AppLayer)

// Access the raw runtime
const program = Effect.gen(function* () {
  const runtime = yield* managedRuntime
  const ctx = runtime.context // Access context directly
  return ctx
})
```

Or use `runtimeEffect`:

```typescript
const runtime = yield* managedRuntime.runtimeEffect
```

## Layer Memoization

Understanding memoization is crucial when using runtimes.

### Memoization is by Reference

Layers are memoized by **reference**, not by service tag:

```typescript
// BAD: Creates two separate database connections
class ServiceA extends Effect.Service<ServiceA>()("ServiceA", {
  dependencies: [Database.Default("localhost:5432")]
}) {}

class ServiceB extends Effect.Service<ServiceB>()("ServiceB", {
  dependencies: [Database.Default("localhost:5432")] // Different reference!
}) {}
```

```typescript
// GOOD: Share the reference
const dbLayer = Database.Default("localhost:5432")

class ServiceA extends Effect.Service<ServiceA>()("ServiceA", {
  dependencies: [dbLayer]
}) {}

class ServiceB extends Effect.Service<ServiceB>()("ServiceB", {
  dependencies: [dbLayer] // Same reference
}) {}
```

### Effect.provide Creates New MemoMaps

When you use `Effect.provide` with a layer, it creates a new memoization scope:

```typescript
const runtime = ManagedRuntime.make(AppLayer)

// BAD: Creates new MemoMap, may rebuild layers
await Effect.runPromise(
  program.pipe(Effect.provide(AppLayer))
)

// GOOD: Reuses runtime's MemoMap
await runtime.runPromise(program)
```

### Sharing MemoMaps Across Runtimes

In frontend apps, you might need multiple runtimes to share layers:

```typescript
import { Effect, Layer, ManagedRuntime } from "effect"

// Create a shared MemoMap
const memoMap = Effect.runSync(Layer.makeMemoMap)

// Multiple runtimes share the same memoization
const runtime1 = ManagedRuntime.make(AppLayer, memoMap)
const runtime2 = ManagedRuntime.make(AppLayer, memoMap)

await runtime1.runPromise(Effect.void) // Builds layers
await runtime2.runPromise(Effect.void) // Reuses layers from runtime1!

await runtime1.dispose()
await runtime2.dispose()
```

## Application Patterns

### Backend Application

Typical server pattern with a single long-lived runtime:

```typescript
import { Effect, Layer, ManagedRuntime } from "effect"

// Compose all services
const AppLayer = Layer.mergeAll(
  DatabaseLive,
  HttpServerLive,
  LoggerLive
)

const runtime = ManagedRuntime.make(AppLayer)

// Warm up
await runtime.runPromise(Effect.void)

// Handle requests
async function handleRequest(req: Request) {
  return runtime.runPromiseExit(
    processRequest(req)
  )
}

// Graceful shutdown
process.on("SIGTERM", () => runtime.dispose())
```

### Frontend Application (React)

```typescript
// runtime.ts
import { ManagedRuntime, Layer } from "effect"

export const AppRuntime = ManagedRuntime.make(
  Layer.mergeAll(ApiClient.Live, AuthService.Live)
)

// RuntimeProvider.tsx
import { createContext, useContext, useEffect, useRef, ReactNode } from "react"

const RuntimeContext = createContext<typeof AppRuntime | null>(null)

export function RuntimeProvider({ children }: { children: ReactNode }) {
  const runtimeRef = useRef(AppRuntime)

  useEffect(() => {
    // Warm up on mount
    runtimeRef.current.runPromise(Effect.void)
    return () => { runtimeRef.current.dispose() }
  }, [])

  return (
    <RuntimeContext.Provider value={runtimeRef.current}>
      {children}
    </RuntimeContext.Provider>
  )
}

// Hook
export function useRunEffect() {
  const runtime = useContext(RuntimeContext)
  if (!runtime) throw new Error("Missing RuntimeProvider")

  return <A, E>(effect: Effect.Effect<A, E, AppServices>) =>
    runtime.runPromise(effect)
}
```

### Layer.toRuntime

For scoped runtime creation within an effect:

```typescript
import { Effect, Layer, Scope } from "effect"

const program = Effect.gen(function* () {
  const runtime = yield* Layer.toRuntime(AppLayer)

  // Use the runtime
  const result = Runtime.runSync(runtime)(someEffect)

  return result
})

// Runtime is automatically cleaned up when scope closes
await Effect.runPromise(Effect.scoped(program))
```

### Layer.launch

For long-running services that should stay alive until interrupted:

```typescript
import { Effect, Layer } from "effect"

const serverLayer = Layer.effectDiscard(
  Effect.gen(function* () {
    const server = yield* HttpServer.serve
    yield* Effect.log("Server started on port 3000")
    yield* Effect.never // Keep alive
  })
)

// Runs forever until interrupted
await Effect.runPromise(Layer.launch(serverLayer))
```

## Runtime Configuration

### FiberRefs

Set default values for fiber-local state:

```typescript
import { Runtime, FiberRef } from "effect"

const runtime = Runtime.defaultRuntime.pipe(
  Runtime.setFiberRef(FiberRef.currentLogLevel, LogLevel.Debug),
  Runtime.setFiberRef(FiberRef.currentRequestCacheEnabled, true)
)
```

### Runtime Flags

Control execution behavior:

```typescript
import { Runtime, RuntimeFlags } from "effect"

// Enable/disable interruption handling
const runtime = Runtime.defaultRuntime.pipe(
  Runtime.disableRuntimeFlag(RuntimeFlags.Interruption)
)
```

## Summary

| Concept | Use Case |
|---------|----------|
| `Runtime.defaultRuntime` | Simple scripts, quick tests |
| `Runtime.runSync/runPromise` | Execute with explicit runtime |
| `ManagedRuntime.make(layer)` | Application entry points |
| `runtime.dispose()` | Clean shutdown |
| `Layer.makeMemoMap` | Share services across runtimes |
| `Layer.toRuntime` | Scoped runtime within effects |
| `Layer.launch` | Long-running services |

Use `ManagedRuntime` for applications—it handles service lifecycle and memoization automatically. Reserve raw `Runtime` manipulation for advanced use cases like custom schedulers or runtime flags.
