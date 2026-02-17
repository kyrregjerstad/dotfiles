# Context & Services

Effect tracks dependencies in the third type parameter: `Effect<Success, Error, Requirements>`. When `Requirements` is `never`, all dependencies are satisfied and the effect can run.

## Context.Tag

Define services with a unique identifier and interface:

```ts
import { Context, Effect } from "effect"

class Logger extends Context.Tag("@app/Logger")<
  Logger,
  {
    readonly info: (msg: string) => Effect.Effect<void>
    readonly error: (msg: string) => Effect.Effect<void>
  }
>() {}

class Database extends Context.Tag("@app/Database")<
  Database,
  {
    readonly query: (sql: string) => Effect.Effect<unknown[]>
  }
>() {}
```

Rules:
- Tag identifiers must be globally unique (use `@scope/Name` pattern)
- Service methods should have `R = never` — dependencies are handled via Layer composition
- Services can be simple values, not just objects with methods

## Using Services

Yield the Tag to access the service:

```ts
const program = Effect.gen(function* () {
  const logger = yield* Logger
  const db = yield* Database

  yield* logger.info("Querying...")
  const users = yield* db.query("SELECT * FROM users")
  return users
})
// Effect<unknown[], never, Logger | Database>
```

## Providing Services

### Effect.provideService

```ts
const runnable = program.pipe(
  Effect.provideService(Logger, {
    info: (msg) => Effect.sync(() => console.log(msg)),
    error: (msg) => Effect.sync(() => console.error(msg)),
  })
)
```

### Layer.succeed / Layer.effect

```ts
const LoggerLive = Layer.succeed(Logger, {
  info: (msg) => Effect.sync(() => console.log(msg)),
  error: (msg) => Effect.sync(() => console.error(msg)),
})

// With dependencies
const UserRepoLive = Layer.effect(
  UserRepo,
  Effect.gen(function* () {
    const db = yield* Database
    return {
      findById: (id) => db.query(`SELECT * FROM users WHERE id = '${id}'`)
    }
  })
)

program.pipe(Effect.provide(LoggerLive))
```

### Multiple services

```ts
const AppLayer = Layer.merge(LoggerLive, DatabaseLive)
program.pipe(Effect.provide(AppLayer))
```

## Effect.Service

Bundles Tag + default Layer for services with obvious implementations:

```ts
class Logger extends Effect.Service<Logger>()("Logger", {
  succeed: {
    info: (msg: string) => Effect.log(msg),
    error: (msg: string) => Effect.logError(msg),
  },
}) {}

// Access: yield* Logger
// Default layer: Logger.Default
```

### With dependencies

```ts
class UserService extends Effect.Service<UserService>()("UserService", {
  effect: Effect.gen(function* () {
    const db = yield* Database
    return {
      getUser: (id: string) => db.query(`SELECT * FROM users WHERE id = '${id}'`)
    }
  }),
  dependencies: [DatabaseLive],
}) {}

// UserService.Default — includes DatabaseLive, ready to use
// UserService.DefaultWithoutDependencies — requires dependencies, for manual composition
```

Use `DefaultWithoutDependencies` to swap in different implementations (e.g., testing):

```ts
// Option 1: Define Test layer on the service class
class Accounts extends Effect.Service<Accounts>()("Accounts", {
  effect: Effect.gen(function* () {
    const sql = yield* SqlClient
    // ...
  }),
  dependencies: [SqlLive]
}) {
  static Test = this.DefaultWithoutDependencies.pipe(
    Layer.provide(SqlTest)
  )
}
```

```ts
// Option 2: Compose in the test file
import { it } from "@effect/vitest"

const TestLayer = StylesRepo.DefaultWithoutDependencies.pipe(
  Layer.provide(PgContainer.Live)
)

it.layer(TestLayer)("StylesRepo", (it) => {
  it.effect("creates a style", () =>
    Effect.gen(function* () {
      const repo = yield* StylesRepo
      const style = yield* repo.create({ name: "test" })
      expect(style.name).toBe("test")
    })
  )
})
```

### With accessors

```ts
class Logger extends Effect.Service<Logger>()("Logger", {
  accessors: true,
  succeed: {
    info: (msg: string) => Effect.log(msg),
  },
}) {}

// Direct call without yielding service first
Logger.info("Hello")
```

### Context.Tag vs Effect.Service

| Context.Tag | Effect.Service |
|-------------|----------------|
| Service is a primitive value | Service is an object with methods |
| Multiple implementations expected | Obvious default implementation exists |
| Interface-first design | Implementation known upfront |

## Optional Services

### Effect.serviceOption

Returns `Option<Service>`, service not added to requirements:

```ts
const program = Effect.gen(function* () {
  const userOpt = yield* Effect.serviceOption(CurrentUser)
  return Option.getOrElse(userOpt, () => "anonymous")
})
```

### Context.Reference

Service with built-in default value:

```ts
class CurrentUser extends Context.Reference<CurrentUser>()("CurrentUser", {
  defaultValue: () => Option.none<{ email: string }>(),
}) {}

// Yields the default if not provided
const user = yield* CurrentUser
```

## Layer Composition

Services with dependencies use `Layer.provide`:

```ts
const LoggerLive = Layer.succeed(Logger, { /* ... */ })

const UserRepoLive = Layer.effect(
  UserRepo,
  Effect.gen(function* () {
    const logger = yield* Logger
    return { /* ... */ }
  })
)

// Compose: UserRepo depends on Logger
const AppLayer = UserRepoLive.pipe(Layer.provide(LoggerLive))
```

See the **Layers** file for full coverage of dependency graphs and resource lifecycles.
