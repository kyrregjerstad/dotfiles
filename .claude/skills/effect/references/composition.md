# Composition

Effect programs are built by composing smaller effects into larger ones. This chapter covers the core patterns: piping with `pipe`, generators with `Effect.gen`, and transformation functions like `map`, `tap`, and `flatMap`.

## Piping (pipe)

The `pipe` function chains operations together, passing the result of each step to the next:

```typescript
import { pipe } from "effect"

const result = pipe(
  10,
  (n) => n * 2,       // 20
  (n) => n.toString() // "20"
)
```

Every Effect has a built-in `.pipe()` method, so you don't need to import `pipe` separately:

```typescript
import { Effect } from "effect"

const fetchRequest = Effect.tryPromise(() =>
  fetch("https://api.example.com/data")
)

const jsonResponse = (response: Response) =>
  Effect.tryPromise(() => response.json())

const saveToDB = (data: unknown) =>
  Effect.tryPromise(() =>
    fetch("/api/save", { body: JSON.stringify(data) })
  )

// Read top-to-bottom: fetch → parse JSON → save
const program = fetchRequest.pipe(
  Effect.flatMap(jsonResponse),
  Effect.flatMap(saveToDB)
)
```

Compare with nested function calls:

```typescript
// Hard to read - where does it start?
const program = Effect.flatMap(
  Effect.flatMap(fetchRequest, jsonResponse),
  saveToDB
)
```

### Dual API

Most Effect functions support both "data-first" and "data-last" calling styles:

```typescript
// Data-first: pass the effect and function together
Effect.flatMap(fetchRequest, jsonResponse)

// Data-last: partial application for piping
fetchRequest.pipe(Effect.flatMap(jsonResponse))
```

The data-last style enables clean pipelines. Effect detects which style you're using based on argument count.

## Generators (Effect.gen)

As pipelines grow, nesting becomes a problem:

```typescript
const program = fetchRequest.pipe(
  Effect.flatMap((response) =>
    jsonResponse(response).pipe(
      Effect.flatMap((data) =>
        saveToDB(data).pipe(
          Effect.flatMap(() => logSuccess(data)) // 4 levels deep!
        )
      )
    )
  )
)
```

`Effect.gen` solves this with a syntax similar to `async/await`:

```typescript
const program = Effect.gen(function* () {
  const response = yield* fetchRequest
  const data = yield* jsonResponse(response)
  yield* saveToDB(data)
  yield* logSuccess(data)
  return data
})
```

The mental model:
- `async/await` → `Effect.gen/yield*`
- `throw` → `return yield* new MyError()` (if using `Data.TaggedError`)

```typescript
// async/await version
const main = async () => {
  const response = await fetchRequest()
  if (!response.ok) {
    throw new FetchError()
  }
  return await parseJson(response)
}

// Effect.gen version (FetchError extends Data.TaggedError)
const main = Effect.gen(function* () {
  const response = yield* fetchRequest
  if (!response.ok) {
    return yield* new FetchError()
  }
  return yield* parseJson(response)
})
```

### Failing in Generators

Always use `return yield*` for failures, not `throw`:

```typescript
// ❌ Don't throw - creates an untyped defect
if (value === null) {
  throw new Error("Null value")
}

// ✅ Use return yield* - tracked in the type system
if (value === null) {
  return yield* new NullError() // NullError extends Data.TaggedError
}

// Also works with Effect.fail for non-TaggedError types
if (value === null) {
  return yield* Effect.fail(new Error("Null value"))
}
```

The `return` is crucial for TypeScript type narrowing:

```typescript
const program = Effect.gen(function* () {
  const value: string | null = yield* getValue

  if (value === null) {
    return yield* new NullError()
  }

  // TypeScript knows value is string here
  return value.toUpperCase()
})
```

### Mixing Generators and Pipes

Combine both styles for clean code:

```typescript
Effect.gen(function* () {
  const values = yield* getValues

  // Use pipe for transformations before yielding
  const processed = yield* processValues(values).pipe(
    Effect.tap((result) => logResult(result)),
    Effect.timeout("5 seconds")
  )

  return processed
})
```

### Effect.fn for Traced Functions

Wrap generator functions with `Effect.fn` for better stack traces and tracing:

```typescript
const processUser = Effect.fn("processUser")(function* (userId: string) {
  yield* Effect.logInfo(`Processing user ${userId}`)
  const user = yield* getUser(userId)
  return yield* validateUser(user)
})

// Stack traces show "processUser" and where it was called from
```

`Effect.fn` also accepts a second argument for cross-cutting concerns:

```typescript
import { Effect, flow, Schedule } from "effect"

const fetchWithRetry = Effect.fn("fetchWithRetry")(
  function* (url: string) {
    return yield* fetchData(url)
  },
  flow(
    Effect.retry(Schedule.recurs(3)),
    Effect.timeout("10 seconds")
  )
)
```

## Transformation (map, tap)

### Effect.map

Transforms the success value without changing the effect's structure:

```typescript
const program = Effect.succeed({ id: 123, values: [10, 20, 30] })

const values = program.pipe(
  Effect.map((data) => data.values)
)
// Effect<number[], never, never>
```

If the effect fails, `map` won't run—the error propagates unchanged.

### Effect.tap

Runs a side effect without changing the success value:

```typescript
const program = Effect.succeed(42).pipe(
  Effect.tap((n) => Console.log(`Got: ${n}`)),
  Effect.tap((n) => saveToMetrics(n))
)
// Effect<number, never, never> - still returns 42
```

`tap` is flexible—it accepts:
- Plain functions: `Effect.tap((n) => console.log(n))`
- Effects: `Effect.tap((n) => Effect.log(n))`
- Promises: `Effect.tap((n) => fetch(...))`

Errors from `tap` propagate but don't change the success type:

```typescript
const program = Effect.succeed(42).pipe(
  Effect.tap((n) => {
    if (n < 0) return Effect.fail(new NegativeError())
    return Effect.void
  })
)
// Effect<number, NegativeError, never>
// Success type is still number, not void
```

### Effect.as

Replace the success value with a constant:

```typescript
Effect.succeed(100).pipe(Effect.as(42))
// Effect<42, never, never>

// Equivalent to:
Effect.succeed(100).pipe(Effect.map(() => 42))
```

## Sequencing (flatMap, andThen)

### Effect.flatMap

Chains effects where the next effect depends on the previous result:

```typescript
const getUser = (id: string) => Effect.succeed({ name: "Alice", age: 30 })
const sendEmail = (user: { name: string }) => Effect.succeed(`Sent to ${user.name}`)

const program = getUser("123").pipe(
  Effect.flatMap((user) => sendEmail(user))
)
// Effect<string, never, never>
```

`flatMap` unifies error and requirement channels:

```typescript
// If effect1: Effect<A, E1, R1>
// And f returns: Effect<B, E2, R2>
// Then flatMap produces: Effect<B, E1 | E2, R1 | R2>
```

Without `flatMap`, you'd get nested effects:

```typescript
// Using map creates Effect<Effect<B>>
const nested = effect.pipe(Effect.map((a) => produceEffect(a)))
// Effect<Effect<B, E2>, E1, R1> - not what we want!

// flatMap "flattens" the nesting
const flat = effect.pipe(Effect.flatMap((a) => produceEffect(a)))
// Effect<B, E1 | E2, R1 | R2> - correct!
```

### Effect.andThen

A more flexible alternative to `flatMap`. Accepts effects, functions, values, or promises:

```typescript
// With another effect
Effect.succeed(1).pipe(Effect.andThen(Effect.succeed(2)))
// Effect<2>

// With a function returning an effect
Effect.succeed(1).pipe(Effect.andThen((n) => Effect.succeed(n + 1)))
// Effect<2>

// With a plain value
Effect.succeed(1).pipe(Effect.andThen("done"))
// Effect<"done">

// With a function returning a value
Effect.succeed(1).pipe(Effect.andThen((n) => n.toString()))
// Effect<string>

// With a promise
Effect.succeed(1).pipe(Effect.andThen(() => Promise.resolve("ok")))
// Effect<string, UnknownException>
```

Use `andThen` when you want flexibility. Use `flatMap` when you specifically need a function that returns an effect.

### Effect.zip

Combines two effects into a tuple:

```typescript
const program = Effect.succeed(1).pipe(
  Effect.zip(Effect.succeed("hello"))
)
// Effect<[number, string], never, never>
```

With concurrent execution:

```typescript
const program = Effect.succeed(1).pipe(
  Effect.zip(Effect.succeed("hello"), { concurrent: true })
)
```

### Effect.zipLeft and Effect.zipRight

Run two effects but keep only one result:

```typescript
// zipLeft: run both, keep the first result
Effect.succeed(1).pipe(
  Effect.zipLeft(Console.log("side effect"))
)
// Effect<1>

// zipRight: run both, keep the second result
Console.log("setup").pipe(
  Effect.zipRight(Effect.succeed("result"))
)
// Effect<"result">
```

### Effect.all

Combine multiple effects, preserving structure:

```typescript
// Array of effects → Effect of array
const array = Effect.all([
  Effect.succeed(1),
  Effect.succeed(2),
  Effect.succeed(3)
])
// Effect<[number, number, number]>

// Object of effects → Effect of object
const object = Effect.all({
  name: Effect.succeed("Alice"),
  age: Effect.succeed(30)
})
// Effect<{ name: string; age: number }>
```

Control concurrency with options:

```typescript
// Sequential (default)
Effect.all(tasks)

// All at once
Effect.all(tasks, { concurrency: "unbounded" })

// Limited concurrency
Effect.all(tasks, { concurrency: 3 })
```

## When to Use What

| Pattern | Use When |
|---------|----------|
| `pipe` | Chaining transformations, adding instrumentation |
| `Effect.gen` | Complex logic with multiple steps, conditionals |
| `map` | Transforming the success value |
| `tap` | Side effects without changing the value |
| `flatMap` | Chaining effects that depend on previous results |
| `andThen` | Flexible chaining with mixed input types |
| `Effect.all` | Running multiple independent effects |

**General guidance:**
- Use generators for application code (readable, familiar)
- Use pipes for library code and instrumentation (more efficient)
- Mix both as needed—they compose well together
