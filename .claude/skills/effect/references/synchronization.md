# Synchronization Primitives

Effect provides low-level primitives for coordinating between fibers. These are the building blocks for more complex concurrent patterns.

## Deferred - Single-Value Fiber Synchronization

A `Deferred<A, E>` is a synchronization primitive that can be set exactly once. Multiple fibers can wait on it, and all will resume when the value is set.

### Creating and Using Deferred

```typescript
import { Deferred, Effect } from "effect"

const program = Effect.gen(function* () {
  // Create an empty Deferred
  const deferred = yield* Deferred.make<number, string>()

  // Complete it with a value
  yield* Deferred.succeed(deferred, 42)

  // Retrieve the value (blocks until set)
  const value = yield* Deferred.await(deferred)
  console.log(value) // 42
})
```

### Deferred is Also an Effect

`Deferred` implements the `Effect` interface, so you can yield it directly:

```typescript
const program = Effect.gen(function* () {
  const deferred = yield* Deferred.make<number>()
  yield* Deferred.succeed(deferred, 100)

  // Yielding deferred directly is equivalent to Deferred.await
  const result = yield* deferred
  console.log(result) // 100
})
```

### Completion Methods

Deferred can only be completed once. Subsequent completions return `false`:

```typescript
const program = Effect.gen(function* () {
  const deferred = yield* Deferred.make<number, string>()

  // First completion succeeds
  const first = yield* Deferred.succeed(deferred, 1)
  console.log(first) // true

  // Second completion is ignored
  const second = yield* Deferred.succeed(deferred, 2)
  console.log(second) // false

  const value = yield* Deferred.await(deferred)
  console.log(value) // 1 (first value wins)
})
```

**Completion options:**

| Method | Description |
|--------|-------------|
| `Deferred.succeed(d, value)` | Complete with success value |
| `Deferred.fail(d, error)` | Complete with typed error |
| `Deferred.die(d, defect)` | Complete with defect (untyped error) |
| `Deferred.interrupt(d)` | Complete with interruption |
| `Deferred.done(d, exit)` | Complete with Exit value |
| `Deferred.complete(d, effect)` | Run effect, memoize result |
| `Deferred.completeWith(d, effect)` | Run effect on each await |

### complete vs completeWith

The difference matters when multiple fibers await the same Deferred:

```typescript
// complete: runs effect ONCE, memoizes result
const program1 = Effect.gen(function* () {
  const deferred = yield* Deferred.make<number>()
  const counter = yield* Ref.make(0)

  yield* Deferred.complete(deferred, Ref.updateAndGet(counter, (n) => n + 1))

  const a = yield* Deferred.await(deferred) // 1
  const b = yield* Deferred.await(deferred) // 1 (memoized)
})

// completeWith: runs effect on EACH await
const program2 = Effect.gen(function* () {
  const deferred = yield* Deferred.make<number>()
  const counter = yield* Ref.make(0)

  yield* Deferred.completeWith(deferred, Ref.updateAndGet(counter, (n) => n + 1))

  const a = yield* Deferred.await(deferred) // 1
  const b = yield* Deferred.await(deferred) // 2 (re-executed)
})
```

Use `completeWith` for performance when you don't need memoization.

### Checking State

```typescript
const program = Effect.gen(function* () {
  const deferred = yield* Deferred.make<number>()

  // Check if completed
  const done1 = yield* Deferred.isDone(deferred)
  console.log(done1) // false

  yield* Deferred.succeed(deferred, 42)

  const done2 = yield* Deferred.isDone(deferred)
  console.log(done2) // true

  // Poll without blocking
  const polled = yield* Deferred.poll(deferred)
  // Option.Some(Effect that produces 42)
})
```

### Use Case: Waiting for a Signal

```typescript
import { Deferred, Effect, Fiber } from "effect"

const program = Effect.gen(function* () {
  const ready = yield* Deferred.make<void>()

  // Worker waits for signal
  const worker = yield* Effect.fork(
    Effect.gen(function* () {
      console.log("Worker waiting...")
      yield* Deferred.await(ready)
      console.log("Worker starting!")
      return "done"
    })
  )

  // Do some setup
  yield* Effect.sleep("100 millis")
  console.log("Setup complete, signaling worker")

  // Signal the worker
  yield* Deferred.succeed(ready, undefined)

  const result = yield* Fiber.join(worker)
  console.log(result) // "done"
})
```

### Use Case: One-Time Initialization

```typescript
const createService = Effect.gen(function* () {
  const initialized = yield* Deferred.make<Config>()
  let isFirst = true

  const getConfig = Effect.gen(function* () {
    if (isFirst) {
      isFirst = false
      const config = yield* loadConfig()
      yield* Deferred.succeed(initialized, config)
      return config
    }
    // Subsequent calls wait for the first to complete
    return yield* Deferred.await(initialized)
  })

  return { getConfig }
})
```

## Semaphore - Concurrency Limiting

A Semaphore controls access to resources through permits. Think of it as a ticket system: operations must acquire permits before proceeding.

### Creating a Semaphore

```typescript
import { Effect } from "effect"

const program = Effect.gen(function* () {
  // Create semaphore with 5 permits
  const sem = yield* Effect.makeSemaphore(5)
})
```

### Protecting Operations with withPermits

```typescript
const program = Effect.gen(function* () {
  const sem = yield* Effect.makeSemaphore(3)

  // This operation requires 1 permit
  const protectedOp = sem.withPermits(1)(
    Effect.gen(function* () {
      yield* Effect.log("Running with permit")
      yield* Effect.sleep("1 second")
      return "done"
    })
  )

  // Run 10 operations with max 3 concurrent
  yield* Effect.all(
    Array.from({ length: 10 }, (_, i) =>
      sem.withPermits(1)(
        Effect.gen(function* () {
          yield* Effect.log(`Task ${i} starting`)
          yield* Effect.sleep("500 millis")
          yield* Effect.log(`Task ${i} done`)
        })
      )
    ),
    { concurrency: "unbounded" }
  )
})
```

### How Permits Work

```
Semaphore with 4 permits:

Task A acquires 2 → 2 remaining
Task B acquires 2 → 0 remaining
Task C acquires 1 → WAITS (no permits available)
Task A completes  → 2 permits returned
Task C acquires 1 → 1 remaining, Task C runs
```

### Variable Permit Counts

Operations can require different numbers of permits:

```typescript
const program = Effect.gen(function* () {
  const sem = yield* Effect.makeSemaphore(4)

  // Light operation: 1 permit
  const lightTask = sem.withPermits(1)(Effect.log("light"))

  // Heavy operation: 2 permits
  const heavyTask = sem.withPermits(2)(
    Effect.gen(function* () {
      yield* Effect.log("heavy start")
      yield* Effect.sleep("1 second")
      yield* Effect.log("heavy end")
    })
  )

  // Only 2 heavy tasks can run at once, or 4 light tasks
  yield* Effect.all([heavyTask, heavyTask, lightTask, lightTask], {
    concurrency: "unbounded"
  })
})
```

### Manual Permit Control

For advanced use cases, you can manually take and release permits:

```typescript
const program = Effect.gen(function* () {
  const sem = yield* Effect.makeSemaphore(4)

  // Take permits (blocks if not available)
  yield* sem.take(2)

  // Do work...

  // Release permits
  yield* sem.release(2)

  // Release all permits (resets to initial count)
  yield* sem.releaseAll
})
```

### Resizing a Semaphore

You can change the capacity of a running semaphore:

```typescript
const program = Effect.gen(function* () {
  const sem = yield* Effect.makeSemaphore(4)

  yield* sem.take(4) // Use all permits

  // Reduce capacity - excess permits will be "owed"
  yield* sem.resize(2)

  // Now we owe 2 permits before anyone else can proceed
  yield* sem.release(2) // Still need to release 2 more
  yield* sem.release(1) // Only now can someone take 1 permit
})
```

### Use Case: Rate Limiting API Calls

```typescript
const createApiClient = Effect.gen(function* () {
  // Max 5 concurrent API calls
  const sem = yield* Effect.makeSemaphore(5)

  const fetch = (url: string) =>
    sem.withPermits(1)(
      Effect.tryPromise(() => globalThis.fetch(url))
    )

  return { fetch }
})
```

### Use Case: Mutual Exclusion (Mutex)

A semaphore with 1 permit acts as a mutex:

```typescript
const createTokenService = Effect.gen(function* () {
  // Only 1 refresh at a time
  const mutex = yield* Effect.makeSemaphore(1)
  const tokenRef = yield* Ref.make<string | null>(null)

  const refreshToken = mutex.withPermits(1)(
    Effect.gen(function* () {
      yield* Effect.log("Refreshing token...")
      const newToken = yield* fetchNewToken()
      yield* Ref.set(tokenRef, newToken)
      return newToken
    })
  )

  return { refreshToken }
})
```

### Use Case: Connection Pool

```typescript
const createDbPool = Effect.gen(function* () {
  // Max 10 concurrent DB connections
  const sem = yield* Effect.makeSemaphore(10)

  const withConnection = <A, E>(
    operation: (conn: Connection) => Effect.Effect<A, E>
  ) =>
    sem.withPermits(1)(
      Effect.acquireUseRelease(
        acquireConnection(),
        operation,
        releaseConnection
      )
    )

  return { withConnection }
})
```

## Semaphore vs Effect.all Concurrency

For simple cases, use `Effect.all` with `concurrency` option:

```typescript
// Simple: use Effect.all
yield* Effect.all(tasks, { concurrency: 5 })
```

Use Semaphore when you need:
- Shared concurrency limit across different call sites
- Variable permit costs per operation
- Dynamic resizing
- Fine-grained control over acquisition/release

```typescript
// Semaphore: shared across multiple operations
const sem = yield* Effect.makeSemaphore(5)

// Different parts of your app can share the limit
const fetchUser = sem.withPermits(1)(...)
const fetchPosts = sem.withPermits(1)(...)
const heavyAnalytics = sem.withPermits(3)(...)
```

## Comparing Primitives

| Primitive | Purpose | Cardinality |
|-----------|---------|-------------|
| `Deferred` | Wait for single value | One producer, many consumers |
| `Semaphore` | Limit concurrency | Many producers, limited concurrent |
| `Queue` | Pass messages | Many-to-many (see [Queues](queues-and-pubsub.md)) |
| `Ref` | Shared mutable state | Many readers/writers (see [State Management](state-management.md)) |
