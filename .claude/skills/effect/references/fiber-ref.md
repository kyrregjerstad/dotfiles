# FiberRef

`FiberRef<A>` provides fiber-local state in Effect. Unlike `Ref` which is shared across all fibers, each fiber has its own copy of a `FiberRef` value. When a fiber forks, the child inherits the parent's value, and changes in the child don't affect the parent.

## Fiber-Local State

### Creating a FiberRef

Use `FiberRef.make` to create a scoped fiber reference:

```typescript
import { Effect, FiberRef, Scope } from "effect"

const program = Effect.gen(function* () {
  // Creates a FiberRef with initial value "default"
  const ref = yield* FiberRef.make("default")

  const value = yield* FiberRef.get(ref)
  // value: "default"
})
```

For global or long-lived references, use `FiberRef.unsafeMake`:

```typescript
import { FiberRef } from "effect"

// Create a global FiberRef (not scoped)
const currentUserId = FiberRef.unsafeMake<string | null>(null)
const currentRequestId = FiberRef.unsafeMake("")
```

### Basic Operations

`FiberRef` supports the same operations as `Ref`:

```typescript
import { Effect, FiberRef } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* FiberRef.make(0)

  // Get current value
  const value = yield* FiberRef.get(ref)

  // Set a new value
  yield* FiberRef.set(ref, 10)

  // Update based on current value
  yield* FiberRef.update(ref, (n) => n + 1)

  // Get and update atomically
  const before = yield* FiberRef.getAndUpdate(ref, (n) => n * 2)

  // Update and get the new value
  const after = yield* FiberRef.updateAndGet(ref, (n) => n + 5)

  // Modify: return a value while updating
  const result = yield* FiberRef.modify(ref, (n) => ["computed", n + 1])
})
```

A `FiberRef` is itself an `Effect`, so you can yield it directly:

```typescript
const program = Effect.gen(function* () {
  const ref = yield* FiberRef.make(42)

  // These are equivalent:
  const v1 = yield* FiberRef.get(ref)
  const v2 = yield* ref
})
```

### Reset and Delete

Reset a `FiberRef` to its initial value:

```typescript
import { Effect, FiberRef } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* FiberRef.make("initial")

  yield* FiberRef.set(ref, "changed")
  yield* FiberRef.delete(ref)  // or FiberRef.reset(ref)

  const value = yield* ref
  // value: "initial"
})
```

## Propagation and Forking Behavior

### Child Fibers Inherit Parent Values

When you fork a fiber, the child gets a copy of the parent's `FiberRef` values:

```typescript
import { Effect, FiberRef, Fiber } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* FiberRef.make("parent-value")

  const fiber = yield* Effect.fork(FiberRef.get(ref))
  const childValue = yield* Fiber.join(fiber)
  // childValue: "parent-value"
})
```

### Child Changes Don't Affect Parent

Changes made by a child fiber are isolated:

```typescript
import { Effect, FiberRef, Fiber, Deferred } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* FiberRef.make("initial")
  const done = yield* Deferred.make<void>()

  // Child modifies its copy
  yield* Effect.fork(
    Effect.gen(function* () {
      yield* FiberRef.set(ref, "child-value")
      yield* Deferred.succeed(done, void 0)
    })
  )

  yield* Deferred.await(done)

  // Parent still has original value
  const parentValue = yield* ref
  // parentValue: "initial"
})
```

### Joining Inherits Child Values

When you `Fiber.join` a child, the parent inherits the child's `FiberRef` values:

```typescript
import { Effect, FiberRef, Fiber } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* FiberRef.make("initial")

  const child = yield* Effect.fork(FiberRef.set(ref, "updated"))
  yield* Fiber.join(child)

  const value = yield* ref
  // value: "updated"
})
```

### Custom Fork Behavior

You can customize how values propagate on fork with the `fork` option:

```typescript
import { Effect, FiberRef, Fiber } from "effect"

const program = Effect.gen(function* () {
  // Each forked fiber gets an incremented value
  const forkCount = yield* FiberRef.make(0, {
    fork: (n) => n + 1
  })

  const child1 = yield* Effect.fork(FiberRef.get(forkCount))
  const child2 = yield* Effect.fork(FiberRef.get(forkCount))

  const v0 = yield* forkCount  // 0 (parent)
  const v1 = yield* Fiber.join(child1)  // 1 (first fork)
  const v2 = yield* Fiber.join(child2)  // 1 (also first fork from parent)
})
```

Nested forks accumulate:

```typescript
import { Effect, FiberRef, Fiber } from "effect"

const program = Effect.gen(function* () {
  const depth = yield* FiberRef.make(0, {
    fork: (n) => n + 1
  })

  // Fork, then fork again inside
  const nested = yield* Effect.fork(
    Effect.gen(function* () {
      const inner = yield* Effect.fork(FiberRef.get(depth))
      return yield* Fiber.join(inner)
    })
  )

  const result = yield* Fiber.join(nested)
  // result: 2 (two levels of forking)
})
```

### Custom Join Behavior

The `join` option controls how child values merge back to the parent:

```typescript
import { Effect, FiberRef, Fiber, Function } from "effect"

const program = Effect.gen(function* () {
  // Sum values on join
  const counter = yield* FiberRef.make(0, {
    fork: Function.constant(0),  // Children start at 0
    join: (parent, child) => parent + child
  })

  // Run 1000 fibers, each incrementing by 1
  yield* Effect.all(
    Array.from({ length: 1000 }, () =>
      FiberRef.update(counter, (n) => n + 1)
    ),
    { concurrency: "unbounded" }
  )

  const total = yield* counter
  // total: 1000 (all increments collected)
})
```

This is useful for aggregating metrics across concurrent operations.

## Scoped Updates with locally

`Effect.locally` temporarily sets a `FiberRef` value for a specific effect, then restores the original:

```typescript
import { Effect, FiberRef } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* FiberRef.make("outer")

  const innerValue = yield* Effect.locally(ref, "inner")(
    FiberRef.get(ref)
  )
  // innerValue: "inner"

  const outerValue = yield* ref
  // outerValue: "outer" (restored)
})
```

This is the preferred pattern for context propagation:

```typescript
import { Effect, FiberRef } from "effect"

const currentResourceName = FiberRef.unsafeMake("")

const withResource = <A, E, R>(name: string) =>
  <A, E, R>(effect: Effect.Effect<A, E, R>) =>
    Effect.locally(currentResourceName, name)(effect)

const program = Effect.gen(function* () {
  yield* doWork().pipe(withResource("users-api"))
  yield* doOther().pipe(withResource("orders-api"))
})
```

### locallyScoped for Layer Integration

Use `Effect.locallyScoped` when you need the value to persist through a scope:

```typescript
import { Effect, FiberRef, Layer, Context } from "effect"

const myRef = FiberRef.unsafeMake(false)

interface MyService {
  readonly value: boolean
}
const MyService = Context.GenericTag<MyService>("MyService")

const program = Effect.gen(function* () {
  // Set FiberRef value that persists during layer construction
  const layer1 = Layer.scopedDiscard(
    Effect.locallyScoped(myRef, true)
  )

  // This layer sees the updated value
  const layer2 = Layer.effect(
    MyService,
    FiberRef.get(myRef).pipe(Effect.map((value) => ({ value })))
  )

  const combined = layer2.pipe(Layer.provide(layer1))

  const service = yield* Effect.provide(MyService, combined)
  // service.value: true
})
```

### locallyWith for Updates

`Effect.locallyWith` updates the value using a function:

```typescript
import { Effect, FiberRef, List } from "effect"

const callStack = FiberRef.unsafeMake<List.List<string>>(List.empty())

const withStackFrame = (name: string) =>
  <A, E, R>(effect: Effect.Effect<A, E, R>) =>
    Effect.locallyWith(callStack, List.prepend(name))(effect)

const program = Effect.gen(function* () {
  yield* doSomething().pipe(
    withStackFrame("doSomething"),
    withStackFrame("program")
  )
})
```

## Built-in FiberRefs

Effect uses `FiberRef` internally for many features. These are available for customization:

```typescript
import { FiberRef, LogLevel, Effect } from "effect"

// Logging
FiberRef.currentLogLevel        // Current log level
FiberRef.currentMinimumLogLevel // Minimum level to output
FiberRef.currentLogAnnotations  // HashMap of log annotations
FiberRef.currentLogSpan         // Current log spans

// Tracing
FiberRef.currentTracerEnabled         // Whether tracing is on
FiberRef.currentTracerTimingEnabled   // Whether timing is on
FiberRef.currentTracerSpanAnnotations // Span annotations

// Concurrency
FiberRef.currentConcurrency           // Default concurrency level
FiberRef.currentSchedulingPriority    // Fiber scheduling priority
FiberRef.currentMaxOpsBeforeYield     // Ops before yielding

// Batching
FiberRef.currentRequestBatchingEnabled // Whether batching is on
FiberRef.currentRequestCacheEnabled    // Request cache enabled

// Runtime
FiberRef.currentScheduler      // The scheduler to use
FiberRef.currentSupervisor     // Fiber supervisor
FiberRef.currentRuntimeFlags   // Runtime flags
```

### Example: Customizing Log Level Per-Request

```typescript
import { Effect, FiberRef, LogLevel } from "effect"

const handleRequest = (verbose: boolean) =>
  Effect.gen(function* () {
    yield* Effect.log("Processing request")
    // ... do work
  }).pipe(
    Effect.locally(
      FiberRef.currentMinimumLogLevel,
      verbose ? LogLevel.Debug : LogLevel.Info
    )
  )
```

### Example: SQL Query Tracing

A practical example using `FiberRef` to add context to SQL queries:

```typescript
import { Effect, FiberRef, FiberRefs, Option } from "effect"

// Define a FiberRef for the current resource name
const currentResourceName = FiberRef.unsafeMake("")

// In a SQL statement transformer
const transformQuery = (sql: string, refs: FiberRefs.FiberRefs, span: any) => {
  const resourceName = Option.getOrUndefined(
    FiberRefs.get(refs, currentResourceName)
  )

  return `/* resource: ${resourceName} */ ${sql}`
}

// Usage in handlers
const handleGetUsers = Effect.gen(function* () {
  // ... execute SQL queries
}).pipe(Effect.locally(currentResourceName, "GET /users"))

const handleGetOrders = Effect.gen(function* () {
  // ... execute SQL queries
}).pipe(Effect.locally(currentResourceName, "GET /orders"))
```

## FiberRef vs Ref

| Feature | FiberRef | Ref |
|---------|----------|-----|
| Scope | Fiber-local (each fiber has own copy) | Shared across all fibers |
| Fork | Child inherits parent's value | Same ref shared with child |
| Isolation | Changes in child don't affect parent | Changes visible to all |
| Join | Can merge child values to parent | N/A - always shared |
| Use Case | Context propagation, request-scoped data | Shared mutable state |

Use `FiberRef` for:
- Request IDs and correlation IDs
- User context and authentication
- Log annotations and tracing context
- Per-request configuration
- Any data that should flow through a call chain but be isolated between requests

Use `Ref` for:
- Shared counters and metrics
- Caches and connection pools
- Application state that all fibers should see
