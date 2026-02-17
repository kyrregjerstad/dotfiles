# Error Handling

## Expected Errors vs Defects

Effect distinguishes two error categories:

**Expected errors (failures)** — tracked in the `E` type parameter, recoverable:
- Validation errors, "not found", permission denied, rate limits, network errors

**Unexpected errors (defects)** — not in type signature, unrecoverable:
- Bugs, invariant violations, critical config failures, null pointer exceptions

The key question: **can the caller reasonably do something about this error?**

- User not found → caller can show "user doesn't exist" message → **expected**
- Database connection string missing → app can't start, no recovery → **defect**
- Invalid JSON from user input → return validation error → **expected**
- Bug causing null dereference → fix the code, don't catch it → **defect**

```ts
import { Effect, Data } from "effect"

// Expected error — in the E channel, caller must handle
class NotFoundError extends Data.TaggedError("NotFoundError")<{
  resource: string
  id: string
}> {}

const findUser = (id: string): Effect.Effect<User, NotFoundError> =>
  Effect.gen(function* () {
    const user = yield* database.findById(id)
    if (!user) return yield* new NotFoundError({ resource: "User", id })
    return user
  })
```

### Converting to Defects

When an error isn't recoverable at your level, convert it to a defect:

```ts
// orDie — convert all errors to defects (app entry point, config loading)
const config = yield* loadConfig.pipe(Effect.orDie)

// die — convert specific error to defect
program.pipe(Effect.catchTag("ConfigError", (e) => Effect.die(e)))

// dieMessage — defect with message
Effect.dieMessage("Critical invariant violated")
```

### When to Catch Defects

Almost never. Defects indicate bugs — catching them hides problems. Only catch at system boundaries for logging/diagnostics, or for plugin sandboxing where you must isolate untrusted code.

## Recovering from Errors

### catchAll

Handle all errors:

```ts
const recovered: Effect.Effect<string, never> = program.pipe(
  Effect.catchAll((error) => Effect.succeed(`Recovered from ${error._tag}`))
)
```

### catchTag

Handle specific error by `_tag`, removes it from type:

```ts
// Before: Effect<string, HttpError | ValidationError>
// After:  Effect<string, ValidationError>
const recovered = program.pipe(
  Effect.catchTag("HttpError", (e) => Effect.succeed(`HTTP ${e.statusCode}`))
)
```

### catchTags

Handle multiple errors:

```ts
const recovered: Effect.Effect<string, never> = program.pipe(
  Effect.catchTags({
    HttpError: (e) => Effect.succeed(`HTTP: ${e.statusCode}`),
    ValidationError: (e) => Effect.succeed(`Validation: ${e.message}`)
  })
)
```

## Retry

```ts
import { Effect, Schedule } from "effect"

// Fixed retries
program.pipe(Effect.retry({ times: 3 }))

// Conditional retry
program.pipe(
  Effect.retry({
    times: 3,
    while: (error) => error._tag === "RequestError"
  })
)

// With delay
program.pipe(
  Effect.retry({
    schedule: Schedule.spaced("500 millis")
  })
)

// Exponential backoff
program.pipe(
  Effect.retry({
    schedule: Schedule.exponential("500 millis", 2)
  })
)

// Exponential + max retries
program.pipe(
  Effect.retry(
    Schedule.exponential("100 millis").pipe(
      Schedule.compose(Schedule.recurs(3))
    )
  )
)
```

## Timeout

```ts
// Basic — adds TimeoutException to error channel
program.pipe(Effect.timeout("5 seconds"))

// With custom error
program.pipe(
  Effect.timeoutFail({
    duration: "5 seconds",
    onTimeout: () => new TimeoutError()
  })
)

// Returns Option (None if timed out)
program.pipe(Effect.timeoutOption("5 seconds"))
```

## Retry + Timeout Combined

```ts
const resilientFetch = (url: string) =>
  fetchEffect(url).pipe(
    Effect.timeout("2 seconds"),           // per-attempt timeout
    Effect.retry({
      while: (e) => e._tag === "RequestError",
      schedule: Schedule.exponential("500 millis")
    }),
    Effect.timeout("10 seconds"),          // overall timeout
    Effect.orDie
  )
```

## Cause

Full error model beyond just failures:

| Type | Description |
|------|-------------|
| `Fail<E>` | Expected error via `Effect.fail` |
| `Die` | Defect via `Effect.die` or throw |
| `Interrupt` | Fiber cancellation |
| `Sequential` | Multiple failures in sequence |
| `Parallel` | Multiple failures from concurrency |

### sandbox

Move full `Cause` into error channel for inspection:

```ts
const sandboxed = Effect.sandbox(program)
// Effect<A, Cause<E>>

sandboxed.pipe(
  Effect.catchTags({
    Die: (cause) => Effect.succeed(fallback)
  })
)
```

## Schema.TaggedError

Serializable, type-safe errors:

```ts
import { Schema } from "effect"

class ValidationError extends Schema.TaggedError<ValidationError>()(
  "ValidationError",
  {
    field: Schema.String,
    message: Schema.String,
  }
) {}

// Yieldable directly — no Effect.fail needed
const validate = Effect.gen(function* () {
  if (!data.email) {
    return yield* new ValidationError({ field: "email", message: "Required" })
  }
  return data
})
```

### Schema.Defect

Wrap unknown errors for serialization:

```ts
class ApiError extends Schema.TaggedError<ApiError>()(
  "ApiError",
  {
    endpoint: Schema.String,
    error: Schema.Defect,  // handles any unknown value
  }
) {}

Effect.tryPromise({
  try: () => fetch(url),
  catch: (error) => new ApiError({ endpoint: url, error })
})
```

`Schema.Defect` converts Error instances to `{ name, message }` objects, other values to strings.
