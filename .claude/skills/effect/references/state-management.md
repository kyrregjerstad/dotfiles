# State Management

Effect provides several types of mutable references for managing state in concurrent applications. These range from simple atomic references (`Ref`) to synchronized references with effectful updates (`SynchronizedRef`) to reactive references with change streams (`SubscriptionRef`).

## Ref - Mutable References

`Ref<A>` is a mutable reference that holds a value of type `A`. All operations on a `Ref` are atomic and fiber-safe, making it suitable for sharing state between concurrent fibers.

### Creating a Ref

Use `Ref.make` to create a reference with an initial value:

```typescript
import { Effect, Ref } from "effect"

const program = Effect.gen(function* () {
  const counter = yield* Ref.make(0)
  const name = yield* Ref.make("Alice")
})
```

### Reading and Writing

Basic operations for getting and setting values:

```typescript
import { Effect, Ref } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* Ref.make(10)

  // Get the current value
  const value = yield* Ref.get(ref)
  // value: 10

  // Set a new value
  yield* Ref.set(ref, 20)

  // Get the new value
  const newValue = yield* Ref.get(ref)
  // newValue: 20
})
```

A `Ref` is itself an `Effect` that returns its value, so you can yield it directly:

```typescript
const program = Effect.gen(function* () {
  const ref = yield* Ref.make(42)

  // These are equivalent:
  const v1 = yield* Ref.get(ref)
  const v2 = yield* ref
})
```

### Updating Values

Use `update` to modify a value based on its current state:

```typescript
import { Effect, Ref } from "effect"

const program = Effect.gen(function* () {
  const counter = yield* Ref.make(0)

  // Increment by 1
  yield* Ref.update(counter, (n) => n + 1)

  // Double the value
  yield* Ref.update(counter, (n) => n * 2)

  const result = yield* counter
  // result: 2
})
```

For compound operations, use `getAndUpdate` or `updateAndGet`:

```typescript
import { Effect, Ref } from "effect"

const program = Effect.gen(function* () {
  const counter = yield* Ref.make(10)

  // Get current value, then update
  const before = yield* Ref.getAndUpdate(counter, (n) => n + 5)
  // before: 10, counter is now 15

  // Update, then get new value
  const after = yield* Ref.updateAndGet(counter, (n) => n + 5)
  // after: 20, counter is now 20
})
```

### The modify Operation

`modify` combines reading and updating in one atomic operation. It takes a function that returns a tuple: the value to return and the new state.

```typescript
import { Effect, Ref } from "effect"

const program = Effect.gen(function* () {
  const counter = yield* Ref.make(100)

  // Atomically decrement and check if still positive
  const wasPositive = yield* Ref.modify(counter, (n) => {
    const newValue = n - 1
    return [n > 0, newValue]  // [returnValue, newState]
  })
  // wasPositive: true, counter is now 99
})
```

This is useful when you need to return something different from the new state.

### Conditional Updates with updateSome

Use `updateSome` when you only want to update based on certain conditions:

```typescript
import { Effect, Ref, Option } from "effect"

type State = { _tag: "Active" } | { _tag: "Paused" } | { _tag: "Stopped" }

const program = Effect.gen(function* () {
  const state = yield* Ref.make<State>({ _tag: "Active" })

  // Only update if currently Active
  yield* Ref.updateSome(state, (s) =>
    s._tag === "Active"
      ? Option.some({ _tag: "Paused" } as State)
      : Option.none()
  )

  const current = yield* state
  // current: { _tag: "Paused" }
})
```

### Real-World Example: In-Memory Repository

Here's a practical example using `Ref` to implement an in-memory todo repository:

```typescript
import { Effect, Ref, HashMap } from "effect"

interface Todo {
  id: number
  text: string
  done: boolean
}

class TodosRepository extends Effect.Service<TodosRepository>()("TodosRepository", {
  effect: Effect.gen(function* () {
    const todos = yield* Ref.make(HashMap.empty<number, Todo>())

    const getAll = Ref.get(todos).pipe(
      Effect.map((map) => Array.from(HashMap.values(map)))
    )

    function getById(id: number) {
      return Ref.get(todos).pipe(
        Effect.flatMap(HashMap.get(id)),
        Effect.catchTag("NoSuchElementException", () =>
          Effect.fail(new Error(`Todo ${id} not found`))
        )
      )
    }

    function create(text: string) {
      return Ref.modify(todos, (map) => {
        const id = HashMap.size(map)
        const todo: Todo = { id, text, done: false }
        return [todo, HashMap.set(map, id, todo)]
      })
    }

    function complete(id: number) {
      return getById(id).pipe(
        Effect.map((todo) => ({ ...todo, done: true })),
        Effect.tap((todo) =>
          Ref.update(todos, HashMap.set(todo.id, todo))
        )
      )
    }

    return { getAll, getById, create, complete }
  })
}) {}
```

## SynchronizedRef - Atomic Effectful Updates

`SynchronizedRef<A>` extends `Ref<A>` with the ability to run effectful updates atomically. When you need to update state based on an effect (like fetching data or checking a condition), `SynchronizedRef` ensures no concurrent updates interfere.

### When to Use SynchronizedRef

Use `SynchronizedRef` when your update logic involves effects:

- Fetching data to compute the new value
- Checking external conditions
- Performing validation that might fail
- Any update that needs to be atomic across an effect

### Creating a SynchronizedRef

```typescript
import { Effect, SynchronizedRef } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* SynchronizedRef.make({ count: 0, lastUpdated: Date.now() })
})
```

### Effectful Updates

Use `updateEffect` to run an effect during the update:

```typescript
import { Effect, SynchronizedRef } from "effect"

interface TokenState {
  token: string
  expiresAt: number
}

const fetchNewToken = Effect.succeed({
  token: "new-token-123",
  expiresAt: Date.now() + 3600000
})

const program = Effect.gen(function* () {
  const tokenRef = yield* SynchronizedRef.make<TokenState>({
    token: "initial",
    expiresAt: 0
  })

  // Atomically fetch and update token
  yield* SynchronizedRef.updateEffect(tokenRef, (current) =>
    Effect.gen(function* () {
      if (current.expiresAt > Date.now()) {
        return current  // Still valid, no update needed
      }
      // Fetch new token
      const newToken = yield* fetchNewToken
      return newToken
    })
  )
})
```

### modifyEffect for Complex Updates

`modifyEffect` lets you return a value alongside the update:

```typescript
import { Effect, SynchronizedRef } from "effect"

interface CacheEntry<A> {
  value: A
  timestamp: number
}

const program = Effect.gen(function* () {
  const cache = yield* SynchronizedRef.make<CacheEntry<string> | null>(null)

  // Get value, refreshing if stale
  const value = yield* SynchronizedRef.modifyEffect(cache, (entry) =>
    Effect.gen(function* () {
      const now = Date.now()

      if (entry && now - entry.timestamp < 60000) {
        // Cache hit - return value, don't update state
        return [entry.value, entry] as const
      }

      // Cache miss or stale - fetch new value
      const newValue = yield* Effect.succeed("fetched-data")
      const newEntry = { value: newValue, timestamp: now }

      return [newValue, newEntry] as const
    })
  )
})
```

### Handling Failures

Effectful updates can fail. If the effect fails, the state remains unchanged:

```typescript
import { Effect, SynchronizedRef, Exit } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* SynchronizedRef.make(10)

  // This update will fail, leaving ref at 10
  const exit = yield* SynchronizedRef.updateEffect(ref, (n) =>
    Effect.fail("validation error")
  ).pipe(Effect.exit)

  const value = yield* ref
  // value: 10 (unchanged because update failed)
})
```

### Preventing Concurrent Token Refresh

A common pattern is ensuring only one fiber refreshes a token while others wait:

```typescript
import { Effect, SynchronizedRef, Deferred } from "effect"

interface TokenState {
  token: string
  refreshing: Deferred.Deferred<string, Error> | null
}

const refreshToken = Effect.gen(function* () {
  yield* Effect.sleep("1 second")  // Simulate API call
  return `token-${Date.now()}`
})

const getToken = (ref: SynchronizedRef.SynchronizedRef<TokenState>) =>
  SynchronizedRef.modifyEffect(ref, (state) =>
    Effect.gen(function* () {
      if (state.refreshing) {
        // Another fiber is refreshing, wait for it
        const token = yield* Deferred.await(state.refreshing)
        return [token, state] as const
      }

      // Start refresh
      const deferred = yield* Deferred.make<string, Error>()
      const newState = { ...state, refreshing: deferred }

      // Fork the refresh in background
      yield* Effect.gen(function* () {
        const newToken = yield* refreshToken
        yield* Deferred.succeed(deferred, newToken)
        yield* SynchronizedRef.update(ref, (s) => ({
          token: newToken,
          refreshing: null
        }))
      }).pipe(Effect.fork)

      // Wait for the token
      const token = yield* Deferred.await(deferred)
      return [token, newState] as const
    })
  )
```

## SubscriptionRef - Reactive State with Streams

`SubscriptionRef<A>` extends `SynchronizedRef<A>` with a `changes` stream. Subscribers automatically receive the current value and all subsequent updates, making it ideal for reactive state management.

### Creating a SubscriptionRef

```typescript
import { Effect, SubscriptionRef } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* SubscriptionRef.make(0)
})
```

### Subscribing to Changes

The `changes` property is a `Stream` that emits the current value immediately, followed by all updates:

```typescript
import { Effect, SubscriptionRef, Stream, Fiber } from "effect"

const program = Effect.gen(function* () {
  const counter = yield* SubscriptionRef.make(0)

  // Start a subscriber in the background
  const subscriber = yield* counter.changes.pipe(
    Stream.tap((value) => Effect.log(`Counter is now: ${value}`)),
    Stream.take(4),  // Stop after 4 values
    Stream.runDrain,
    Effect.fork
  )

  // Make some updates
  yield* SubscriptionRef.update(counter, (n) => n + 1)
  yield* SubscriptionRef.update(counter, (n) => n + 1)
  yield* SubscriptionRef.update(counter, (n) => n + 1)

  yield* Fiber.join(subscriber)
  // Logs: Counter is now: 0
  // Logs: Counter is now: 1
  // Logs: Counter is now: 2
  // Logs: Counter is now: 3
})
```

### Multiple Subscribers

Multiple subscribers can listen to the same `SubscriptionRef`. Each subscriber starts with the current value at subscription time:

```typescript
import { Effect, SubscriptionRef, Stream, Fiber, Deferred } from "effect"

const program = Effect.gen(function* () {
  const ref = yield* SubscriptionRef.make(0)

  // First subscriber - sees 0, 1, 2
  const ready1 = yield* Deferred.make<void>()
  const sub1 = yield* ref.changes.pipe(
    Stream.tap(() => Deferred.succeed(ready1, void 0)),
    Stream.take(3),
    Stream.runCollect,
    Effect.fork
  )
  yield* Deferred.await(ready1)

  yield* SubscriptionRef.update(ref, (n) => n + 1)  // now 1

  // Second subscriber starts - sees 1, 2
  const ready2 = yield* Deferred.make<void>()
  const sub2 = yield* ref.changes.pipe(
    Stream.tap(() => Deferred.succeed(ready2, void 0)),
    Stream.take(2),
    Stream.runCollect,
    Effect.fork
  )
  yield* Deferred.await(ready2)

  yield* SubscriptionRef.update(ref, (n) => n + 1)  // now 2

  const result1 = yield* Fiber.join(sub1)
  const result2 = yield* Fiber.join(sub2)
  // result1: [0, 1, 2]
  // result2: [1, 2]
})
```

### Real-World Example: Network Status Monitor

Here's a practical example using `SubscriptionRef` to track network connectivity:

```typescript
import { Effect, SubscriptionRef, Stream, Chunk } from "effect"

class NetworkMonitor extends Effect.Service<NetworkMonitor>()("NetworkMonitor", {
  scoped: Effect.gen(function* () {
    // Create reactive reference for online status
    const status = yield* SubscriptionRef.make<boolean>(
      window.navigator.onLine
    )

    // Listen to browser events and update the ref
    yield* Stream.async<boolean>((emit) => {
      const onlineHandler = () => emit(Effect.succeed(Chunk.of(true)))
      const offlineHandler = () => emit(Effect.succeed(Chunk.of(false)))

      window.addEventListener("online", onlineHandler)
      window.addEventListener("offline", offlineHandler)

      return Effect.sync(() => {
        window.removeEventListener("online", onlineHandler)
        window.removeEventListener("offline", offlineHandler)
      })
    }).pipe(
      Stream.tap((isOnline) =>
        SubscriptionRef.update(status, () => isOnline)
      ),
      Stream.runDrain,
      Effect.forkScoped
    )

    return {
      // Current status
      isOnline: SubscriptionRef.get(status),
      // Subscribe to status changes
      changes: status.changes
    }
  })
}) {}

// Usage
const program = Effect.gen(function* () {
  const monitor = yield* NetworkMonitor

  // Check current status
  const online = yield* monitor.isOnline
  console.log(`Currently online: ${online}`)

  // React to changes
  yield* monitor.changes.pipe(
    Stream.tap((online) =>
      Effect.log(online ? "Back online!" : "Gone offline")
    ),
    Stream.runDrain,
    Effect.fork
  )
})
```

### Use Cases for SubscriptionRef

| Use Case | Description |
|----------|-------------|
| UI State | Components subscribe to state changes for reactive updates |
| Configuration | Services react to config changes without polling |
| Status Monitoring | Track connection status, health checks, etc. |
| Live Data | Push updates to multiple consumers |
| Cache Invalidation | Notify subscribers when cached data changes |

## Choosing the Right Reference Type

| Type | Use When |
|------|----------|
| `Ref` | Simple state that updates synchronously |
| `SynchronizedRef` | Updates require running effects atomically |
| `SubscriptionRef` | Multiple consumers need to react to changes |

All three types are fiber-safe and can be safely shared across concurrent operations. Start with `Ref` for simplicity and upgrade to the more powerful variants when your requirements demand it.
