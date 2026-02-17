# Layers

`Layer<Out, E, In>` constructs services: handles initialization, dependency resolution, resource acquisition, and cleanup.

- `Out` — services produced
- `E` — construction errors
- `In` — services required to construct

## Constructing Layers

### Layer.succeed

No initialization logic:

```ts
const LoggerLive = Layer.succeed(Logger, {
  info: (msg) => Effect.sync(() => console.log(`[INFO] ${msg}`)),
  error: (msg) => Effect.sync(() => console.error(`[ERROR] ${msg}`)),
})
```

### Layer.sync

Synchronous initialization:

```ts
const CacheLive = Layer.sync(Cache, () => {
  const store = new Map<string, string>()
  return {
    get: (key) => Effect.succeed(store.get(key) ?? null),
    set: (key, value) => Effect.sync(() => void store.set(key, value)),
  }
})
```

### Layer.effect

Requires Effects or other services:

```ts
const UserApiLive = Layer.effect(
  UserApi,
  Effect.gen(function* () {
    const http = yield* HttpClient.HttpClient
    const logger = yield* Logger

    return {
      getUser: (id) => Effect.gen(function* () {
        yield* logger.info(`Fetching user ${id}`)
        const response = yield* http.get(`/users/${id}`)
        return yield* response.json
      }),
    }
  })
)
```

### Layer.scoped

Acquires resources with cleanup:

```ts
const DatabaseLive = Layer.scoped(
  Database,
  Effect.gen(function* () {
    const conn = yield* openDatabaseConnection()

    yield* Effect.addFinalizer(() =>
      Effect.sync(() => conn.close())
    )

    return {
      query: (sql) => Effect.promise(() => conn.query(sql)),
    }
  })
)
```

Finalizers run when the layer's scope closes (program end or `ManagedRuntime.dispose()`).

## Composing Layers

### Layer.provide

Provide dependencies to a layer:

```ts
const UserRepoLive = Layer.effect(
  UserRepo,
  Effect.gen(function* () {
    const db = yield* Database
    return { findById: (id) => db.query(`SELECT * FROM users WHERE id = '${id}'`) }
  })
)

const UserRepoWithDeps = UserRepoLive.pipe(Layer.provide(DatabaseLive))
// Layer<UserRepo, never, never>
```

### Layer.merge / Layer.mergeAll

Combine independent layers:

```ts
const AppLayer = Layer.merge(LoggerLive, CacheLive)
// Layer<Logger | Cache>

const FullLayer = Layer.mergeAll(LoggerLive, CacheLive, DatabaseLive)
```

### Layer.provideMerge

Provide and keep both in output:

```ts
const AppLayer = UserRepoLive.pipe(
  Layer.provideMerge(DatabaseLive),
  Layer.provideMerge(LoggerLive)
)
// Layer<UserRepo | Database | Logger>
```

### Local Co-location Pattern

Provide dependencies locally, merge at root:

```ts
const UserRepoLive = Layer.effect(UserRepo, /* ... */)
  .pipe(Layer.provide(DatabaseLive))

const TodoRepoLive = Layer.effect(TodoRepo, /* ... */)
  .pipe(Layer.provide(DatabaseLive))

// Root: just merge
const MainLive = Layer.mergeAll(UserRepoLive, TodoRepoLive)
```

Benefits:
- Dependencies explicit at point of use
- Root composition is simple merging
- Memoization still works

## Memoization

Layers are memoized by reference identity. Same layer instance → constructed once.

```ts
// ❌ Bad: two instances (different references)
const bad = Layer.merge(
  UserRepoLive.pipe(Layer.provide(Database.layer({ poolSize: 10 }))),
  TodoRepoLive.pipe(Layer.provide(Database.layer({ poolSize: 10 })))
)
// Creates TWO connection pools

// ✅ Good: store in constant first
const databaseLayer = Database.layer({ poolSize: 10 })

const good = Layer.merge(
  UserRepoLive.pipe(Layer.provide(databaseLayer)),
  TodoRepoLive.pipe(Layer.provide(databaseLayer))
)
// Single connection pool
```

**Rule**: Parameterized layer constructors → store result in constant before reusing.

### Effect.provide memoization

```ts
// ❌ Bad: chained provides don't share
program.pipe(
  Effect.provide(UserRepoLive),
  Effect.provide(TodoRepoLive)
)

// ✅ Good: array or merge
program.pipe(Effect.provide([UserRepoLive, TodoRepoLive]))

// Or
const MainLive = Layer.mergeAll(UserRepoLive, TodoRepoLive)
program.pipe(Effect.provide(MainLive))
```

### Layer.fresh

Opt out of memoization:

```ts
Layer.provide(Layer.fresh(DatabaseLive))  // forces new instance
```

## Background Processes

Use `Effect.forkScoped` in layer constructors to tie fibers to layer lifetime:

```ts
class HealthChecker extends Effect.Service<HealthChecker>()("HealthChecker", {
  scoped: Effect.gen(function* () {
    const db = yield* Database

    yield* Effect.forkScoped(
      db.query("SELECT 1").pipe(
        Effect.repeat({ schedule: Schedule.spaced("30 seconds") })
      )
    )

    return { status: () => Effect.succeed("healthy") }
  }),
}) {}
```

## Testing

### Test layers

```ts
class Database extends Context.Tag("Database")<Database, DbService>() {
  static Live = Layer.scoped(/* real impl */)

  static Test = Layer.sync(Database, () => ({
    query: (sql) => Effect.succeed([{ id: 1 }]),
    execute: (sql) => Effect.void,
  }))
}
```

### Per-test layers (recommended)

```ts
it.effect("finds user", () =>
  Effect.gen(function* () {
    const repo = yield* UserRepo
    const user = yield* repo.findById("1")
    expect(user.name).toBe("Alice")
  }).pipe(
    Effect.provide(UserRepo.Test),
    Effect.provide(Database.Test)
  )
)
```

### Shared layer for expensive resources

```ts
it.layer(Database.Live)("database tests", (it) => {
  it.effect("query works", () =>
    Effect.gen(function* () {
      const db = yield* Database
      const result = yield* db.query("SELECT 1")
      expect(result).toHaveLength(1)
    })
  )
})
```

## ManagedRuntime

For applications with multiple entry points (HTTP handlers, CLI), build layers once:

```ts
import { ManagedRuntime } from "effect"

const runtime = ManagedRuntime.make(MainLive)

// HTTP handlers reuse pre-built runtime
app.get("/users/:id", async (c) => {
  const result = await runtime.runPromise(getUser(c.params.id))
  return c.json(result)
})

// Cleanup on shutdown
process.on("SIGTERM", async () => {
  await runtime.dispose()
  process.exit(0)
})
```

Without `ManagedRuntime`, each `Effect.provide(MainLive)` rebuilds all layers.

### React

```ts
function App() {
  const [runtime] = useState(() => ManagedRuntime.make(MainLive))

  useEffect(() => () => { runtime.dispose() }, [runtime])

  const handleClick = async () => {
    const result = await runtime.runPromise(someEffect)
  }

  return <button onClick={handleClick}>Run</button>
}
```

## Swapping Implementations

```ts
// Production
const MainLive = Layer.mergeAll(UserRepo.Live, Database.PostgresLive)

// Testing
const MainTest = Layer.mergeAll(UserRepo.Live, Database.InMemoryLive)

// Development
const MainDev = Layer.mergeAll(UserRepo.Live, Database.SqliteLive)
```

Business logic unchanged — only underlying implementations vary.
