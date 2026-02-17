# Pool

Pool provides resource pooling for Effect, managing a collection of reusable resources like database connections, HTTP clients, or worker threads. Instead of creating and destroying resources for each operation, pools maintain a set of pre-allocated items that can be borrowed and returned efficiently.

## Resource Pooling

A `Pool<A, E>` manages items of type `A`, where acquisition may fail with error `E`. The pool handles:

- Pre-allocation of resources up to a configured size
- Automatic cleanup when the pool's scope closes
- Blocking when all items are in use
- Invalidation and replacement of broken resources

### Creating a Fixed-Size Pool

Use `Pool.make` for a pool with a constant number of items:

```ts
import { Effect, Pool, Scope } from "effect"

// Simulate a database connection
interface Connection {
  id: number
  query: (sql: string) => Effect.Effect<string>
}

let connectionId = 0
const createConnection = Effect.acquireRelease(
  Effect.sync(() => {
    const id = ++connectionId
    console.log(`Opening connection ${id}`)
    return {
      id,
      query: (sql: string) => Effect.succeed(`Result from conn ${id}: ${sql}`)
    } as Connection
  }),
  (conn) => Effect.sync(() => console.log(`Closing connection ${conn.id}`))
)

const program = Effect.gen(function* () {
  // Create a pool of 3 connections
  const pool = yield* Pool.make({
    acquire: createConnection,
    size: 3
  })

  // Pool pre-allocates all 3 connections immediately
  // Output:
  // Opening connection 1
  // Opening connection 2
  // Opening connection 3

  // Get a connection from the pool
  const conn = yield* pool.get
  const result = yield* conn.query("SELECT * FROM users")
  console.log(result)
}).pipe(Effect.scoped)

// When scope closes, all connections are released:
// Closing connection 1
// Closing connection 2
// Closing connection 3
```

### Pool as an Effect

Pool implements `Effect`, so you can use it directly instead of calling `.get`:

```ts
const program = Effect.gen(function* () {
  const pool = yield* Pool.make({
    acquire: createConnection,
    size: 3
  })

  // These are equivalent:
  const conn1 = yield* pool.get
  const conn2 = yield* pool  // Pool is itself an Effect
}).pipe(Effect.scoped)
```

## Pool Sizing Strategies

Effect provides two pool constructors with different sizing behaviors.

### Fixed Size Pool

`Pool.make` creates a pool with exactly `size` items. The pool pre-allocates all items immediately and maintains that count throughout its lifetime:

```ts
const fixedPool = Pool.make({
  acquire: createConnection,
  size: 10  // Always 10 connections
})
```

Use fixed pools when you know the exact resource count needed and want predictable allocation.

### Dynamic Pool with TTL

`Pool.makeWithTTL` creates a pool that scales between `min` and `max` based on demand:

```ts
import { Duration } from "effect"

const dynamicPool = Pool.makeWithTTL({
  acquire: createConnection,
  min: 2,     // Always keep at least 2
  max: 10,    // Scale up to 10 under load
  timeToLive: Duration.seconds(60)  // Shrink excess after 60s idle
})
```

The pool scales up when requests exceed available capacity and scales back down when excess items remain unused for the TTL period.

```ts
const program = Effect.gen(function* () {
  const pool = yield* Pool.makeWithTTL({
    acquire: createConnection,
    min: 2,
    max: 10,
    timeToLive: Duration.seconds(60)
  })

  // Initially: 2 connections (min)

  // Under heavy load: scales up to 10
  yield* Effect.all(
    Array.from({ length: 10 }, () => Effect.scoped(pool.get)),
    { concurrency: 10 }
  )

  // After 60s of low usage: scales back to 2
}).pipe(Effect.scoped)
```

### TTL Strategy: Creation vs Usage

By default, items are invalidated based on pool usage patterns (`"usage"` strategy). The `"creation"` strategy instead invalidates items based on when they were created:

```ts
const pool = Pool.makeWithTTL({
  acquire: createConnection,
  min: 5,
  max: 20,
  timeToLive: Duration.minutes(5),
  timeToLiveStrategy: "creation"  // Invalidate 5 minutes after creation
})
```

Use `"creation"` when connections have natural expiration times (like OAuth tokens or session limits). Use `"usage"` (default) for general load-based scaling.

## Concurrency Per Item

By default, each pool item can only be used by one fiber at a time. The `concurrency` option allows multiple concurrent uses per item:

```ts
// Each connection can handle 3 concurrent queries
const pool = Pool.make({
  acquire: createConnection,
  size: 4,
  concurrency: 3
})
// Total concurrent operations: 4 connections × 3 = 12
```

This is useful for resources that support multiplexing, like HTTP/2 connections or database connection pools with query pipelining.

```ts
const program = Effect.gen(function* () {
  const pool = yield* Pool.make({
    acquire: createConnection,
    size: 2,
    concurrency: 3
  })

  // Can run 6 concurrent queries (2 connections × 3 each)
  yield* Effect.all(
    Array.from({ length: 6 }, (_, i) =>
      Effect.scoped(
        Effect.gen(function* () {
          const conn = yield* pool.get
          return yield* conn.query(`Query ${i}`)
        })
      )
    ),
    { concurrency: 6 }
  )
}).pipe(Effect.scoped)
```

## Target Utilization

The `targetUtilization` option controls when the pool creates new items. It's a value between 0 and 1:

- `1.0` (default): Create new items only when existing ones are fully utilized
- `0.5`: Create new items when existing ones are 50% utilized

```ts
const pool = Pool.makeWithTTL({
  acquire: createConnection,
  min: 2,
  max: 10,
  timeToLive: Duration.seconds(60),
  targetUtilization: 0.7  // Scale up at 70% utilization
})
```

Lower values make the pool more aggressive about scaling up, reducing latency but using more resources.

## Invalidating Pool Items

When a resource becomes corrupted or stale, invalidate it to trigger replacement:

```ts
const program = Effect.gen(function* () {
  const pool = yield* Pool.make({
    acquire: createConnection,
    size: 3
  })

  const conn = yield* pool.get

  // Check if connection is healthy
  const isHealthy = yield* checkConnection(conn)

  if (!isHealthy) {
    // Mark this connection for replacement
    yield* pool.invalidate(conn)
    // Pool will create a new connection to maintain size
  }
}).pipe(Effect.scoped)
```

Invalidation is lazy—the item is marked for replacement but not immediately destroyed. The pool creates a new item when needed to maintain its target size.

```ts
// Invalidation example with error handling
const robustQuery = (pool: Pool.Pool<Connection>) =>
  Effect.gen(function* () {
    const conn = yield* pool.get
    return yield* conn.query("SELECT 1").pipe(
      Effect.catchAll((error) =>
        Effect.gen(function* () {
          yield* pool.invalidate(conn)
          return yield* Effect.fail(error)
        })
      )
    )
  }).pipe(Effect.scoped)
```

## Blocking Behavior

When all pool items are in use, `pool.get` blocks until an item becomes available:

```ts
const program = Effect.gen(function* () {
  const pool = yield* Pool.make({
    acquire: createConnection,
    size: 2
  })

  // Acquire both connections
  const conn1 = yield* pool.get
  const conn2 = yield* pool.get

  // This will block until conn1 or conn2 is released
  const fiber = yield* Effect.fork(pool.get)

  // Simulate work then release conn1
  yield* Effect.sleep(Duration.seconds(1))
  // conn1 released when its scope closes
}).pipe(Effect.scoped)
```

The blocking is interruptible—you can combine it with timeouts:

```ts
const getWithTimeout = (pool: Pool.Pool<Connection>) =>
  pool.get.pipe(
    Effect.timeout(Duration.seconds(5)),
    Effect.scoped
  )
```

## KeyedPool

`KeyedPool` manages separate pools for different keys. Each key gets its own pool of items:

```ts
import { KeyedPool } from "effect"

// Pool connections per database
const program = Effect.gen(function* () {
  const pool = yield* KeyedPool.make({
    acquire: (dbName: string) =>
      Effect.acquireRelease(
        Effect.sync(() => ({
          db: dbName,
          query: (sql: string) => Effect.succeed(`${dbName}: ${sql}`)
        })),
        () => Effect.log(`Closing ${dbName} connection`)
      ),
    size: 5  // 5 connections per database
  })

  // Get connection to "users" database
  const usersConn = yield* pool.get("users")
  yield* usersConn.query("SELECT * FROM accounts")

  // Get connection to "orders" database (separate pool)
  const ordersConn = yield* pool.get("orders")
  yield* ordersConn.query("SELECT * FROM items")
}).pipe(Effect.scoped)
```

### Variable Size Per Key

Use `KeyedPool.makeWith` for different pool sizes per key:

```ts
const pool = KeyedPool.makeWith({
  acquire: (dbName: string) => createConnectionTo(dbName),
  size: (dbName) => {
    // Main database gets more connections
    if (dbName === "main") return 20
    return 5
  }
})
```

### KeyedPool with TTL

`KeyedPool.makeWithTTL` adds dynamic sizing per key:

```ts
const pool = KeyedPool.makeWithTTL({
  acquire: (dbName: string) => createConnectionTo(dbName),
  min: () => 2,
  max: () => 10,
  timeToLive: Duration.minutes(5)
})
```

For per-key TTL configuration, use `KeyedPool.makeWithTTLBy`:

```ts
const pool = KeyedPool.makeWithTTLBy({
  acquire: (dbName: string) => createConnectionTo(dbName),
  min: (dbName) => (dbName === "main" ? 5 : 1),
  max: (dbName) => (dbName === "main" ? 50 : 10),
  timeToLive: (dbName) =>
    dbName === "main" ? Duration.minutes(10) : Duration.minutes(2)
})
```

## Practical Example: Database Connection Pool

A complete example integrating Pool with the service pattern:

```ts
import { Effect, Pool, Layer, Duration } from "effect"

// Connection interface
interface DbConnection {
  readonly id: number
  query<T>(sql: string): Effect.Effect<T>
  close(): Effect.Effect<void>
}

// Database service with pooled connections
class Database extends Effect.Service<Database>()("Database", {
  scoped: Effect.gen(function* () {
    let nextId = 0

    const pool = yield* Pool.makeWithTTL({
      acquire: Effect.acquireRelease(
        Effect.sync((): DbConnection => {
          const id = ++nextId
          console.log(`Creating connection ${id}`)
          return {
            id,
            query: <T>(sql: string) =>
              Effect.sync(() => {
                console.log(`[Conn ${id}] ${sql}`)
                return {} as T
              }),
            close: () => Effect.sync(() => console.log(`Closing connection ${id}`))
          }
        }),
        (conn) => conn.close()
      ),
      min: 5,
      max: 20,
      concurrency: 1,
      timeToLive: Duration.minutes(5)
    })

    return {
      withConnection: <A, E>(
        f: (conn: DbConnection) => Effect.Effect<A, E>
      ): Effect.Effect<A, E> =>
        Effect.scoped(
          Effect.flatMap(pool.get, f)
        ),

      query: <T>(sql: string): Effect.Effect<T> =>
        Effect.scoped(
          Effect.flatMap(pool.get, (conn) => conn.query<T>(sql))
        )
    }
  })
}) {}

// Usage
const program = Effect.gen(function* () {
  const db = yield* Database

  // Simple query
  yield* db.query("SELECT * FROM users")

  // Multiple queries with same connection
  yield* db.withConnection((conn) =>
    Effect.gen(function* () {
      yield* conn.query("BEGIN")
      yield* conn.query("INSERT INTO users VALUES (...)")
      yield* conn.query("COMMIT")
    })
  )

  // Parallel queries (uses multiple connections from pool)
  yield* Effect.all(
    Array.from({ length: 10 }, (_, i) =>
      db.query(`SELECT * FROM table_${i}`)
    ),
    { concurrency: 10 }
  )
}).pipe(
  Effect.provide(Database.Default)
)
```

## Error Handling

Failed acquisitions are reported through `pool.get`:

```ts
const program = Effect.gen(function* () {
  const pool = yield* Pool.make({
    acquire: Effect.fail("Connection failed"),
    size: 3
  })

  // This will fail with "Connection failed"
  const result = yield* pool.get.pipe(
    Effect.catchAll((error) => Effect.succeed(`Fallback: ${error}`))
  )
}).pipe(Effect.scoped)
```

The pool continues trying to maintain its target size even after failures. Retrying `pool.get` will attempt acquisition again:

```ts
const getWithRetry = (pool: Pool.Pool<Connection, string>) =>
  pool.get.pipe(
    Effect.retry({ times: 3 }),
    Effect.scoped
  )
```

## Lifecycle and Cleanup

Pools are scoped resources. When the scope closes:

1. No new items can be acquired
2. Items currently in use continue until their scopes close
3. All items are released (finalizers run)
4. The pool shuts down completely

```ts
const program = Effect.gen(function* () {
  const pool = yield* Pool.make({
    acquire: createConnection,
    size: 3
  })

  // Use pool...
  yield* doWork(pool)

  // Pool cleanup happens automatically when this scope closes
}).pipe(Effect.scoped)
```

For long-running applications, consider using `ManagedRuntime` to control pool lifetime:

```ts
import { ManagedRuntime, Layer } from "effect"

const DatabasePool = Layer.scoped(
  DatabasePoolTag,
  Pool.make({
    acquire: createConnection,
    size: 10
  })
)

const runtime = ManagedRuntime.make(DatabasePool)

// Use runtime.runPromise(...) for requests
// Call runtime.dispose() on shutdown to clean up pool
```
