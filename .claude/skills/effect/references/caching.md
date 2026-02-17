# Caching

Effect provides powerful caching primitives for memoizing expensive computations with automatic TTL expiration, capacity management, and concurrent-safe access. From simple single-value caches to key-value stores with scoped resource management, Effect's caching APIs help you optimize performance while maintaining type safety.

## Effect-Level Caching

The simplest caching approach is at the Effect level, where you cache the result of a single effect.

### Effect.cached - Permanent Memoization

`Effect.cached` caches the result of an effect forever after the first successful execution:

```typescript
import { Effect, Console } from "effect"

const expensiveComputation = Effect.gen(function* () {
  yield* Console.log("Computing...")
  yield* Effect.sleep("1 second")
  return 42
})

const program = Effect.gen(function* () {
  // Create a cached version of the effect
  const cached = yield* Effect.cached(expensiveComputation)

  // First call computes the value
  const a = yield* cached // logs "Computing..."

  // Subsequent calls return cached result immediately
  const b = yield* cached // no log, instant return
  const c = yield* cached // no log, instant return

  console.log(a, b, c) // 42, 42, 42
})
```

### Effect.cachedWithTTL - Time-Limited Caching

Cache a result for a specified duration, after which the effect is re-executed:

```typescript
import { Effect, Duration, Console, TestClock } from "effect"

const fetchData = Effect.gen(function* () {
  yield* Console.log("Fetching data...")
  return { timestamp: Date.now(), data: "fresh data" }
})

const program = Effect.gen(function* () {
  // Cache the result for 60 seconds
  const cached = yield* Effect.cachedWithTTL(fetchData, "60 seconds")

  const a = yield* cached // Fetches data
  const b = yield* cached // Returns cached (within TTL)

  yield* TestClock.adjust("61 seconds")

  const c = yield* cached // Fetches again (TTL expired)
})
```

Real-world example from Effect's Kubernetes client:

```typescript
import { Effect, HttpClient } from "effect"

const getPods = pipe(
  HttpClient.get("/api/v1/pods"),
  Effect.flatMap((response) => response.json),
  Effect.tapErrorCause((cause) =>
    Effect.logWarning("Failed to fetch pods", cause)
  ),
  Effect.cachedWithTTL("10 seconds")
)
```

### Effect.cachedInvalidateWithTTL - Manual Invalidation

Sometimes you need to manually invalidate the cache before the TTL expires:

```typescript
import { Effect, Console, TestClock } from "effect"

const fetchConfig = Effect.gen(function* () {
  yield* Console.log("Loading config...")
  return { setting: "value" }
})

const program = Effect.gen(function* () {
  // Returns tuple: [cachedEffect, invalidateEffect]
  const [cached, invalidate] = yield* Effect.cachedInvalidateWithTTL(
    fetchConfig,
    "60 minutes"
  )

  const a = yield* cached // Loads config
  const b = yield* cached // Returns cached

  // Manually invalidate when config changes
  yield* invalidate

  const c = yield* cached // Loads config again
})
```

### Effect.cachedFunction - Memoizing Functions

Memoize a function's results based on its input arguments:

```typescript
import { Effect, Console } from "effect"

const expensiveLookup = (id: number) =>
  Effect.gen(function* () {
    yield* Console.log(`Looking up id: ${id}`)
    yield* Effect.sleep("1 second")
    return { id, name: `User ${id}` }
  })

const program = Effect.gen(function* () {
  const memoizedLookup = yield* Effect.cachedFunction(expensiveLookup)

  const user1a = yield* memoizedLookup(1) // Computes
  const user1b = yield* memoizedLookup(1) // Cached!
  const user2  = yield* memoizedLookup(2) // Different key, computes
  const user1c = yield* memoizedLookup(1) // Still cached
})
```

You can provide a custom `Equivalence` for comparing inputs:

```typescript
import { Effect, Equivalence } from "effect"

interface Query {
  table: string
  id: number
}

const queryEquivalence: Equivalence.Equivalence<Query> = Equivalence.make(
  (a, b) => a.table === b.table && a.id === b.id
)

const executeQuery = (query: Query) =>
  Effect.succeed({ result: `Row from ${query.table}` })

const program = Effect.gen(function* () {
  const memoizedQuery = yield* Effect.cachedFunction(
    executeQuery,
    queryEquivalence
  )

  const a = yield* memoizedQuery({ table: "users", id: 1 })
  const b = yield* memoizedQuery({ table: "users", id: 1 }) // Cached
})
```

### Effect.once - Run Only Once

Execute an effect exactly once, regardless of how many times it's called:

```typescript
import { Effect, Console } from "effect"

const program = Effect.gen(function* () {
  const logOnce = yield* Effect.once(Console.log("Initializing..."))

  yield* logOnce // Logs "Initializing..."
  yield* logOnce // Does nothing
  yield* logOnce // Does nothing
})
```

## Cache - Key-Value Memoization

For more sophisticated caching needs, the `Cache` module provides a full-featured key-value cache with capacity limits, TTL, and statistics.

### Creating a Cache

```typescript
import { Cache, Effect, Duration } from "effect"

interface User {
  id: number
  name: string
  email: string
}

const fetchUser = (id: number): Effect.Effect<User, Error> =>
  Effect.gen(function* () {
    yield* Effect.log(`Fetching user ${id} from database...`)
    yield* Effect.sleep("100 millis")
    return { id, name: `User ${id}`, email: `user${id}@example.com` }
  })

const program = Effect.gen(function* () {
  // Create cache with lookup function
  const userCache = yield* Cache.make({
    capacity: 100,               // Max 100 entries
    timeToLive: "5 minutes",     // Entries expire after 5 minutes
    lookup: fetchUser            // Function to compute missing values
  })

  // Get triggers lookup on cache miss
  const user1 = yield* userCache.get(1) // Fetches from DB
  const user1Again = yield* userCache.get(1) // Cache hit!
  const user2 = yield* userCache.get(2) // Different key, fetches
})
```

### Cache Operations

```typescript
import { Cache, Effect, Option } from "effect"

const program = Effect.gen(function* () {
  const cache = yield* Cache.make({
    capacity: 100,
    timeToLive: "1 hour",
    lookup: (key: string) => Effect.succeed(key.toUpperCase())
  })

  // Get - computes if missing
  const value = yield* cache.get("hello") // "HELLO"

  // getOption - returns Option, doesn't compute
  const existing = yield* cache.getOption("hello") // Some("HELLO")
  const missing = yield* cache.getOption("world")  // None

  // getOptionComplete - only returns if lookup completed (not pending)
  const complete = yield* cache.getOptionComplete("hello")

  // set - manually set a value
  yield* cache.set("manual", "MANUAL")

  // contains - check if key exists
  const hasKey = yield* cache.contains("hello") // true

  // refresh - recompute value in background
  yield* cache.refresh("hello")

  // invalidate - remove specific key
  yield* cache.invalidate("hello")

  // invalidateWhen - conditional invalidation
  yield* cache.invalidateWhen("manual", (v) => v === "MANUAL")

  // invalidateAll - clear the cache
  yield* cache.invalidateAll
})
```

### Cache Statistics

Track cache performance with built-in statistics:

```typescript
import { Cache, Effect } from "effect"

const program = Effect.gen(function* () {
  const cache = yield* Cache.make({
    capacity: 100,
    timeToLive: "1 hour",
    lookup: (n: number) => Effect.succeed(n * 2)
  })

  yield* cache.get(1) // Miss
  yield* cache.get(1) // Hit
  yield* cache.get(2) // Miss
  yield* cache.get(1) // Hit

  const stats = yield* cache.cacheStats
  console.log(`Hits: ${stats.hits}`)     // 2
  console.log(`Misses: ${stats.misses}`) // 2
  console.log(`Size: ${stats.size}`)     // 2

  // Entry-level statistics
  const entryStats = yield* cache.entryStats(1)
  // Option<{ loadedMillis: number }>
})
```

### Dynamic TTL with makeWith

Vary the TTL based on the result of the lookup:

```typescript
import { Cache, Effect, Exit, Duration } from "effect"

interface CacheEntry {
  data: string
  isVolatile: boolean
}

const program = Effect.gen(function* () {
  const cache = yield* Cache.makeWith({
    capacity: 100,
    lookup: (key: string): Effect.Effect<CacheEntry> =>
      Effect.succeed({
        data: `Data for ${key}`,
        isVolatile: key.startsWith("temp_")
      }),
    // TTL depends on the exit value
    timeToLive: (exit) => {
      if (Exit.isFailure(exit)) {
        return "10 seconds" // Short TTL for errors
      }
      const entry = exit.value
      return entry.isVolatile
        ? "1 minute"   // Short TTL for volatile data
        : "1 hour"     // Long TTL for stable data
    }
  })

  yield* cache.get("stable_key")   // Cached for 1 hour
  yield* cache.get("temp_data")    // Cached for 1 minute
})
```

### Refresh vs Invalidate

Understanding the difference between refresh and invalidate:

```typescript
import { Cache, Effect, Ref } from "effect"

const program = Effect.gen(function* () {
  const counter = yield* Ref.make(0)

  const cache = yield* Cache.make({
    capacity: 10,
    timeToLive: "1 hour",
    lookup: (_: string) => Ref.updateAndGet(counter, (n) => n + 1)
  })

  const v1 = yield* cache.get("key") // 1

  // Refresh: recomputes in background, serves old value during refresh
  yield* cache.refresh("key")
  const v2 = yield* cache.get("key") // 2 (new value)

  // Invalidate: removes entry, next get triggers new lookup
  yield* cache.invalidate("key")
  const v3 = yield* cache.get("key") // 3 (fresh lookup)
})
```

Key differences:
- **refresh**: Triggers a new lookup immediately, but existing value remains available until the new one is ready
- **invalidate**: Removes the entry; the next `get` will block until a new value is computed

## ScopedCache - Caching Scoped Resources

`ScopedCache` is designed for caching resources that require cleanup (like database connections, file handles, or HTTP clients). Each cached value is scoped - it's acquired when accessed and released when no longer needed.

### Creating a ScopedCache

```typescript
import { ScopedCache, Effect, Scope, Console } from "effect"

interface DbConnection {
  query: (sql: string) => Effect.Effect<unknown>
  close: Effect.Effect<void>
}

const acquireConnection = (host: string): Effect.Effect<DbConnection, never, Scope.Scope> =>
  Effect.acquireRelease(
    Effect.gen(function* () {
      yield* Console.log(`Opening connection to ${host}`)
      return {
        query: (sql) => Effect.succeed({ rows: [] }),
        close: Console.log(`Closing connection to ${host}`)
      }
    }),
    (conn) => conn.close
  )

const program = Effect.scoped(
  Effect.gen(function* () {
    // Create scoped cache - requires Scope
    const connectionCache = yield* ScopedCache.make({
      capacity: 10,
      timeToLive: "5 minutes",
      lookup: acquireConnection
    })

    // Get returns a scoped effect
    yield* Effect.scoped(
      Effect.gen(function* () {
        const conn = yield* connectionCache.get("db.example.com")
        yield* conn.query("SELECT * FROM users")
        // Connection is released when scope closes
      })
    )

    // Getting same key reuses the cached connection
    yield* Effect.scoped(
      Effect.gen(function* () {
        const conn = yield* connectionCache.get("db.example.com")
        yield* conn.query("SELECT * FROM orders")
      })
    )
  })
)
```

### Resource Lifecycle in ScopedCache

The key difference from regular `Cache`:
- Resources are acquired lazily when `get` is called
- Resources remain cached and alive while referenced
- When TTL expires or capacity is exceeded, resources are cleaned up only after all references are released

```typescript
import { ScopedCache, Effect, Scope, Ref, Console } from "effect"

const makeResource = (id: number) =>
  Effect.acquireRelease(
    Effect.gen(function* () {
      yield* Console.log(`Acquired resource ${id}`)
      return { id }
    }),
    () => Console.log(`Released resource ${id}`)
  )

const program = Effect.scoped(
  Effect.gen(function* () {
    const cache = yield* ScopedCache.make({
      capacity: 2,
      timeToLive: "1 minute",
      lookup: makeResource
    })

    // First access - acquires resource
    const resource1 = yield* Effect.scoped(cache.get(1))
    // "Acquired resource 1"

    // Resource is still cached, not released yet
    const resource1Again = yield* Effect.scoped(cache.get(1))
    // No "Acquired" log - reuses cached resource

    // Exceed capacity - oldest unused resource is released
    yield* Effect.scoped(cache.get(2))
    yield* Effect.scoped(cache.get(3))
    // "Acquired resource 2"
    // "Acquired resource 3"
    // "Released resource 1" (evicted due to capacity)
  })
)
// Cache scope closes: "Released resource 2", "Released resource 3"
```

### ScopedCache Operations

```typescript
import { ScopedCache, Effect, Option } from "effect"

const program = Effect.scoped(
  Effect.gen(function* () {
    const cache = yield* ScopedCache.make({
      capacity: 100,
      timeToLive: "1 hour",
      lookup: (key: number) => Effect.succeed({ value: key * 2 })
    })

    // getOption - returns None if not cached, Some if cached
    const maybeValue = yield* Effect.scoped(cache.getOption(1)) // None

    // get - acquires/returns cached resource
    yield* Effect.scoped(cache.get(1))

    const nowCached = yield* Effect.scoped(cache.getOption(1)) // Some

    // getOptionComplete - only Some if lookup finished (not pending)
    const complete = yield* Effect.scoped(cache.getOptionComplete(1))

    // contains - check if key is cached
    const has1 = yield* cache.contains(1) // true

    // refresh - recompute, old resource stays until new one is ready
    yield* cache.refresh(1)

    // invalidate - removes and cleans up resource when safe
    yield* cache.invalidate(1)

    // invalidateAll - clears entire cache
    yield* cache.invalidateAll

    // Statistics
    const stats = yield* cache.cacheStats
    const size = yield* cache.size
  })
)
```

### TTL and Resource Cleanup

When a cached resource expires:
1. New `get` calls trigger a fresh lookup
2. The old resource is cleaned up only when all existing references are released

```typescript
import { ScopedCache, Effect, TestClock, Scope, Context } from "effect"

const program = Effect.scoped(
  Effect.gen(function* () {
    const cache = yield* ScopedCache.make({
      capacity: 10,
      timeToLive: "10 seconds",
      lookup: (key: number) => Effect.succeed(`resource-${key}`)
    })

    // Create a scope that we control
    const scope = yield* Scope.make()

    // Acquire resource into our scope
    yield* Effect.provide(
      cache.get(1),
      Context.make(Scope.Scope, scope)
    )

    // Expire the TTL
    yield* TestClock.adjust("11 seconds")

    // New get creates fresh resource
    yield* Effect.scoped(cache.get(1)) // Gets new resource

    // Old resource still exists (scope not closed)
    // Close our scope - now old resource is cleaned up
    yield* Scope.close(scope, Exit.void)
  })
)
```

## When to Use Each Approach

| Use Case | Solution |
|----------|----------|
| Cache single effect result forever | `Effect.cached` |
| Cache single effect with expiration | `Effect.cachedWithTTL` |
| Cache with manual invalidation | `Effect.cachedInvalidateWithTTL` |
| Memoize function by arguments | `Effect.cachedFunction` |
| Key-value cache with capacity | `Cache.make` |
| Cache resources needing cleanup | `ScopedCache.make` |
| Run effect exactly once | `Effect.once` |

## Best Practices

1. **Choose appropriate TTL**: Balance freshness vs. performance. Too short = too many recomputes. Too long = stale data.

2. **Set reasonable capacity**: Prevent memory issues by limiting cache size. Consider your data size and memory constraints.

3. **Use ScopedCache for resources**: Any value that needs cleanup (connections, file handles, etc.) should use `ScopedCache`.

4. **Monitor statistics**: Use `cacheStats` to understand cache behavior and tune parameters.

5. **Handle errors appropriately**: Decide whether to cache errors (with `makeWith`) or let them propagate.

6. **Consider concurrent access**: All Effect caches are safe for concurrent access. Multiple fibers requesting the same key will share the lookup result.

```typescript
import { Cache, Effect } from "effect"

// Multiple concurrent requests for same key share one lookup
const program = Effect.gen(function* () {
  const cache = yield* Cache.make({
    capacity: 100,
    timeToLive: "1 hour",
    lookup: (id: number) =>
      Effect.gen(function* () {
        yield* Effect.log(`Fetching ${id}...`)
        yield* Effect.sleep("1 second")
        return { id }
      })
  })

  // All three fibers will share the same lookup
  yield* Effect.all([
    cache.get(1),
    cache.get(1),
    cache.get(1)
  ], { concurrency: "unbounded" })

  // Only logs "Fetching 1..." once!
})
```
