# Testing

Effect provides first-class testing support through `@effect/vitest`, which integrates Effect's execution model with Vitest. It handles Effect execution, scoped resources, test services, and provides detailed fiber failure reporting.

## @effect/vitest

### Installation

```bash
bun add -D vitest @effect/vitest
```

Configure vitest in your project:

```ts
// vitest.config.ts
import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
  },
})
```

### Basic Test Structure

Import test functions and assertions from `@effect/vitest`:

```ts
import { describe, expect, it } from "@effect/vitest"
import { Effect } from "effect"

describe("Calculator", () => {
  // Regular sync test
  it("adds numbers", () => {
    expect(1 + 1).toBe(2)
  })

  // Effect test - returns Effect
  it.effect("adds numbers with Effect", () =>
    Effect.gen(function* () {
      const result = yield* Effect.succeed(1 + 1)
      expect(result).toBe(2)
    })
  )
})
```

### Test Variants

#### it.effect()

The primary way to test Effect code. Automatically provides `TestContext` with `TestClock`:

```ts
import { Effect } from "effect"
import { it, expect } from "@effect/vitest"

const divide = (a: number, b: number) =>
  b === 0 ? Effect.fail("Cannot divide by zero") : Effect.succeed(a / b)

it.effect("divides numbers", () =>
  Effect.gen(function* () {
    const result = yield* divide(10, 2)
    expect(result).toBe(5)
  })
)
```

#### it.scoped()

For tests that use scoped resources. The scope closes automatically when the test ends:

```ts
import { Effect } from "effect"
import { it, expect } from "@effect/vitest"

it.scoped("manages scoped resources", () =>
  Effect.gen(function* () {
    const resource = yield* Effect.acquireRelease(
      Effect.succeed("resource"),
      () => Effect.log("Released")
    )
    expect(resource).toBe("resource")
    // Resource is released when test completes
  })
)
```

#### it.live()

Uses the real system clock and live services instead of test services:

```ts
import { Clock, Effect } from "effect"
import { it, expect } from "@effect/vitest"

it.live("uses real time", () =>
  Effect.gen(function* () {
    const now = yield* Clock.currentTimeMillis
    expect(now).toBeGreaterThan(0)
  })
)
```

#### it.scopedLive()

Combines `scoped` and `live` - scoped resources with real services:

```ts
it.scopedLive("scoped with live services", () =>
  Effect.gen(function* () {
    const resource = yield* Effect.acquireRelease(
      Effect.succeed("resource"),
      () => Effect.log("Released")
    )
    const now = yield* Clock.currentTimeMillis
    expect(now).toBeGreaterThan(0)
  })
)
```

### Test Modifiers

```ts
// Skip a test
it.effect.skip("temporarily disabled", () =>
  Effect.gen(function* () {
    // Won't run
  })
)

// Run only this test
it.effect.only("focus on this", () =>
  Effect.gen(function* () {
    // Only this runs
  })
)

// Expect test to fail (for documenting known issues)
it.effect.fails("known bug", () =>
  Effect.gen(function* () {
    expect(1).toBe(2) // Expected to fail
  })
)

// Skip based on condition
it.effect.skipIf(process.env.CI)("skip in CI", () =>
  Effect.gen(function* () {
    // Skipped when CI=true
  })
)

// Run based on condition
it.effect.runIf(process.platform === "linux")("linux only", () =>
  Effect.gen(function* () {
    // Only runs on Linux
  })
)
```

### Parameterized Tests

Use `.each` for data-driven tests:

```ts
it.effect.each([
  { a: 1, b: 2, expected: 3 },
  { a: 5, b: 3, expected: 8 },
])("adds $a + $b = $expected", ({ a, b, expected }) =>
  Effect.gen(function* () {
    const result = yield* Effect.succeed(a + b)
    expect(result).toBe(expected)
  })
)
```

## Test Services (TestClock, TestRandom)

### TestClock

`it.effect` automatically provides `TestContext` which includes `TestClock`. The clock starts at 0 and time only advances when you explicitly adjust it:

```ts
import { Effect, Fiber, TestClock, Clock } from "effect"
import { it, expect } from "@effect/vitest"

it.effect("clock starts at 0", () =>
  Effect.gen(function* () {
    const now = yield* Clock.currentTimeMillis
    expect(now).toBe(0)
  })
)

it.effect("adjusts time", () =>
  Effect.gen(function* () {
    yield* TestClock.adjust("1000 millis")
    const now = yield* Clock.currentTimeMillis
    expect(now).toBe(1000)
  })
)

it.effect("tests delayed operations", () =>
  Effect.gen(function* () {
    // Fork a fiber that sleeps
    const fiber = yield* Effect.delay(Effect.succeed("done"), "10 seconds").pipe(
      Effect.fork
    )

    // Advance time to trigger the delay
    yield* TestClock.adjust("10 seconds")

    // Join completes immediately
    const result = yield* Fiber.join(fiber)
    expect(result).toBe("done")
  })
)
```

#### TestClock API

```ts
import { TestClock, DateTime } from "effect"

// Adjust time forward by duration
yield* TestClock.adjust("5 seconds")
yield* TestClock.adjust("1 hour")

// Set time to specific value (millis)
yield* TestClock.setTime(1000)

// Set time using DateTime
yield* TestClock.setTime(DateTime.unsafeMake("2023-12-31T11:00:00Z"))

// Set time using Date
yield* TestClock.setTime(new Date("2023-12-31"))
```

### Deterministic Random

Use `Random.fixed` or `Effect.withRandomFixed` for deterministic random values:

```ts
import { Effect, Random } from "effect"
import { it, expect } from "@effect/vitest"

it.effect("cycles through fixed values", () =>
  Effect.gen(function* () {
    expect(yield* Random.next).toBe(0.2)
    expect(yield* Random.next).toBe(0.5)
    expect(yield* Random.next).toBe(0.8)
    expect(yield* Random.next).toBe(0.2) // Cycles back
  }).pipe(Effect.withRandomFixed([0.2, 0.5, 0.8]))
)

it.effect("fixed booleans", () =>
  Effect.gen(function* () {
    expect(yield* Random.nextBoolean).toBe(true)
    expect(yield* Random.nextBoolean).toBe(false)
    expect(yield* Random.nextBoolean).toBe(true)
  }).pipe(Effect.withRandom(Random.fixed([true, false, true])))
)

it.effect("fixed integers", () =>
  Effect.gen(function* () {
    expect(yield* Random.nextInt).toBe(10)
    expect(yield* Random.nextInt).toBe(20)
    expect(yield* Random.nextInt).toBe(10) // Cycles
  }).pipe(Effect.withRandom(Random.fixed([10, 20])))
)
```

## Mocking Dependencies

### Using Layer.succeed for Simple Mocks

Create test layers that provide mock implementations:

```ts
import { Context, Effect, Layer } from "effect"
import { describe, expect, it } from "@effect/vitest"

// Define a service
class Database extends Context.Tag("Database")<
  Database,
  { query: (sql: string) => Effect.Effect<string[]> }
>() {}

// Create a test layer with mock implementation
const TestDatabase = Layer.succeed(Database, {
  query: (_sql) => Effect.succeed(["mock", "data"])
})

it.effect("uses mock database", () =>
  Effect.gen(function* () {
    const db = yield* Database
    const results = yield* db.query("SELECT * FROM users")
    expect(results).toEqual(["mock", "data"])
  }).pipe(Effect.provide(TestDatabase))
)
```

### Using Layer.sync for Stateful Mocks

When you need mutable state in tests (e.g., to track calls):

```ts
class EmailService extends Context.Tag("EmailService")<
  EmailService,
  {
    send: (to: string, body: string) => Effect.Effect<void>
    getSent: Effect.Effect<Array<{ to: string; body: string }>>
  }
>() {
  static testLayer = Layer.sync(EmailService, () => {
    const sent: Array<{ to: string; body: string }> = []

    return EmailService.of({
      send: (to, body) => Effect.sync(() => void sent.push({ to, body })),
      getSent: Effect.sync(() => sent)
    })
  })
}

it.effect("tracks sent emails", () =>
  Effect.gen(function* () {
    const email = yield* EmailService
    yield* email.send("user@example.com", "Hello!")

    const sent = yield* email.getSent
    expect(sent).toHaveLength(1)
    expect(sent[0].to).toBe("user@example.com")
  }).pipe(Effect.provide(EmailService.testLayer))
)
```

### Composing Test Layers

Use `Layer.provideMerge` to compose layers and expose dependencies for assertions:

```ts
import { Context, Effect, Layer, Clock } from "effect"
import { describe, expect, it } from "@effect/vitest"

// Domain types
class User extends Context.Tag("User")<User, { id: string; name: string }>() {}

// Services
class Users extends Context.Tag("Users")<
  Users,
  {
    create: (name: string) => Effect.Effect<User>
    findById: (id: string) => Effect.Effect<User | null>
  }
>() {
  static testLayer = Layer.sync(Users, () => {
    const store = new Map<string, User>()
    let counter = 0

    return Users.of({
      create: (name) => Effect.sync(() => {
        const user = { id: `user-${counter++}`, name }
        store.set(user.id, user)
        return user
      }),
      findById: (id) => Effect.sync(() => store.get(id) ?? null)
    })
  })
}

class Emails extends Context.Tag("Emails")<
  Emails,
  {
    send: (to: string, subject: string) => Effect.Effect<void>
    sent: Effect.Effect<ReadonlyArray<{ to: string; subject: string }>>
  }
>() {
  static testLayer = Layer.sync(Emails, () => {
    const emails: Array<{ to: string; subject: string }> = []

    return Emails.of({
      send: (to, subject) => Effect.sync(() => void emails.push({ to, subject })),
      sent: Effect.sync(() => emails)
    })
  })
}

// Service under test
class Registration extends Context.Tag("Registration")<
  Registration,
  { register: (name: string, email: string) => Effect.Effect<User> }
>() {
  static layer = Layer.effect(
    Registration,
    Effect.gen(function* () {
      const users = yield* Users
      const emails = yield* Emails

      return Registration.of({
        register: (name, email) =>
          Effect.gen(function* () {
            const user = yield* users.create(name)
            yield* emails.send(email, "Welcome!")
            return user
          })
      })
    })
  )
}

// Compose test layers - provideMerge exposes leaf services for assertions
const testLayer = Registration.layer.pipe(
  Layer.provideMerge(Users.testLayer),
  Layer.provideMerge(Emails.testLayer)
)

describe("Registration", () => {
  it.effect("creates user and sends welcome email", () =>
    Effect.gen(function* () {
      const registration = yield* Registration
      const emails = yield* Emails

      const user = yield* registration.register("Alice", "alice@example.com")

      expect(user.name).toBe("Alice")

      const sent = yield* emails.sent
      expect(sent).toHaveLength(1)
      expect(sent[0].to).toBe("alice@example.com")
      expect(sent[0].subject).toBe("Welcome!")
    }).pipe(Effect.provide(testLayer))
  )
})
```

### Using it.layer for Shared Layer Setup

When multiple tests share the same layer, use `it.layer` to avoid repeating setup:

```ts
import { Context, Effect, Layer } from "effect"
import { describe, expect, it, layer } from "@effect/vitest"

class Config extends Context.Tag("Config")<Config, { apiUrl: string }>() {
  static Live = Layer.succeed(Config, { apiUrl: "https://api.example.com" })
}

// layer() provides context for all nested tests
layer(Config.Live)((it) => {
  it.effect("has config", () =>
    Effect.gen(function* () {
      const config = yield* Config
      expect(config.apiUrl).toBe("https://api.example.com")
    })
  )

  it.effect("can use config in other tests", () =>
    Effect.gen(function* () {
      const config = yield* Config
      expect(config.apiUrl).toContain("example.com")
    })
  )
})

// Alternative syntax with describe-like naming
it.layer(Config.Live)("Config tests", (it) => {
  it.effect("works", () =>
    Effect.gen(function* () {
      const config = yield* Config
      expect(config.apiUrl).toBeDefined()
    })
  )
})
```

### Nested Layers

Layers can be nested to build up context incrementally:

```ts
class Foo extends Context.Tag("Foo")<Foo, "foo">() {
  static Live = Layer.succeed(Foo, "foo")
}

class Bar extends Context.Tag("Bar")<Bar, "bar">() {
  static Live = Layer.effect(Bar, Effect.map(Foo, () => "bar" as const))
}

layer(Foo.Live)((it) => {
  it.effect("has Foo", () =>
    Effect.gen(function* () {
      const foo = yield* Foo
      expect(foo).toBe("foo")
    })
  )

  // Nested layer adds Bar (which depends on Foo)
  it.layer(Bar.Live)("with Bar", (it) => {
    it.effect("has both", () =>
      Effect.gen(function* () {
        const foo = yield* Foo
        const bar = yield* Bar
        expect(foo).toBe("foo")
        expect(bar).toBe("bar")
      })
    )
  })
})
```

### Partial Mocks

Create partial mocks where only some methods are implemented:

```ts
import type { Context } from "effect"
import { Effect, Layer } from "effect"

const makeTestLayer = <I, S extends object>(
  tag: Context.Tag<I, S>
) => (service: Partial<S>): Layer.Layer<I> => {
  const proxy = new Proxy(service as S, {
    get(target, prop) {
      if (prop in target) {
        return target[prop as keyof S]
      }
      return () => Effect.die(`Unimplemented: ${String(prop)}`)
    }
  })
  return Layer.succeed(tag, proxy)
}

// Usage
class UserService extends Context.Tag("UserService")<
  UserService,
  {
    create: (name: string) => Effect.Effect<{ id: string; name: string }>
    delete: (id: string) => Effect.Effect<void>
    findAll: () => Effect.Effect<Array<{ id: string; name: string }>>
  }
>() {}

// Only mock the methods you need
const PartialMock = makeTestLayer(UserService)({
  create: (name) => Effect.succeed({ id: "test-id", name })
  // delete and findAll will throw "Unimplemented" if called
})
```

### Testing with ConfigProvider

Mock configuration values using `ConfigProvider.fromMap`:

```ts
import { Config, ConfigProvider, Effect, Layer } from "effect"
import { it, expect } from "@effect/vitest"

const TestConfigProvider = ConfigProvider.fromMap(
  new Map([
    ["API_URL", "http://localhost:3000"],
    ["API_KEY", "test-key"]
  ])
)

const ConfigLayer = Layer.setConfigProvider(TestConfigProvider)

it.effect("uses test config", () =>
  Effect.gen(function* () {
    const apiUrl = yield* Config.string("API_URL")
    const apiKey = yield* Config.string("API_KEY")

    expect(apiUrl).toBe("http://localhost:3000")
    expect(apiKey).toBe("test-key")
  }).pipe(Effect.provide(ConfigLayer))
)
```

## Logging in Tests

By default, `it.effect` suppresses log output. To enable logging:

```ts
import { Effect, Logger } from "effect"
import { it } from "@effect/vitest"

// Option 1: Provide a logger
it.effect("with logging", () =>
  Effect.gen(function* () {
    yield* Effect.log("This will be shown")
  }).pipe(Effect.provide(Logger.pretty))
)

// Option 2: Use it.live (logging enabled by default)
it.live("live with logging", () =>
  Effect.gen(function* () {
    yield* Effect.log("This will be shown")
  })
)
```

## Property-Based Testing

`@effect/vitest` supports property-based testing with fast-check:

```ts
import { it } from "@effect/vitest"
import { Effect, FastCheck, Schema } from "effect"

// Basic property test
it.prop("addition is commutative", [FastCheck.integer(), FastCheck.integer()], ([a, b]) =>
  a + b === b + a
)

// With Schema for better generators
const PositiveInt = Schema.Int.pipe(Schema.positive())

it.prop("positive numbers stay positive", [PositiveInt], ([n]) =>
  n > 0
)

// Effect-based property tests
it.effect.prop(
  "strings contain their substrings",
  { a: Schema.String, b: Schema.String },
  ({ a, b }) =>
    Effect.gen(function* () {
      return (a + b).includes(a) && (a + b).includes(b)
    })
)

// Scoped property tests
it.scoped.prop(
  "resources are managed",
  { value: Schema.String },
  ({ value }) =>
    Effect.gen(function* () {
      yield* Effect.scope
      return value.length >= 0
    })
)
```
