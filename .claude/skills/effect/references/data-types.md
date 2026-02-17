# Data Types

## Option

`Option<A>` represents a value that may or may not exist. Type-safe alternative to `null`/`undefined`.

```ts
import { Option } from "effect"

// Creating
Option.some(42)                      // Option<number>
Option.none()                        // Option<never>
Option.fromNullable(null)            // None
Option.fromNullable("hello")         // Some("hello")

// Checking
Option.isSome(opt)
Option.isNone(opt)

// Transforming
Option.map(opt, n => n * 2)
Option.flatMap(opt, n => n === 0 ? Option.none() : Option.some(100 / n))

// Extracting
Option.getOrElse(opt, () => 0)
Option.getOrThrow(opt)               // throws if None
```

Generator syntax:

```ts
const result = Option.gen(function* () {
  const x = yield* Option.some(1)
  const y = yield* Option.some(2)
  return x + y
})  // Some(3)

// Short-circuits on None
const failed = Option.gen(function* () {
  const x = yield* Option.some(1)
  yield* Option.none()  // stops here
  return x + 10
})  // None
```

## Either

`Either<R, L>` represents success (`Right`) or failure (`Left`) with error information.

```ts
import { Either } from "effect"

// Creating
Either.right(42)                     // Either<number, never>
Either.left("error")                 // Either<never, string>

// Checking
Either.isRight(e)
Either.isLeft(e)

// Transforming
Either.map(e, n => n * 2)            // transform Right
Either.mapLeft(e, err => `Error: ${err}`)  // transform Left
Either.flatMap(e, n => n === 0 ? Either.left("zero") : Either.right(100 / n))
```

Generator syntax:

```ts
const result = Either.gen(function* () {
  const x = yield* Either.right(1)
  const y = yield* Either.right(2)
  return x + y
})  // Right(3)

// Short-circuits on Left
const failed = Either.gen(function* () {
  const x = yield* Either.right(1)
  yield* Either.left("oops")  // stops here
  return x + 10
})  // Left("oops")
```

Converting between Option and Either:

```ts
Either.fromOption(Option.some(1), () => "was none")  // Right(1)
Either.fromOption(Option.none(), () => "was none")   // Left("was none")
Option.getRight(Either.right(1))                     // Some(1)
Option.getLeft(Either.left("e"))                     // Some("e")
```

## Data.Class

Immutable records with structural equality:

```ts
import { Data, Equal } from "effect"

class Person extends Data.Class<{ name: string; age: number }> {}

const p1 = new Person({ name: "Alice", age: 30 })
const p2 = new Person({ name: "Alice", age: 30 })
Equal.equals(p1, p2)  // true
```

With methods:

```ts
class User extends Data.Class<{ id: string; email: string }> {
  get domain() {
    return this.email.split("@")[1]
  }
  withEmail(email: string) {
    return new User({ ...this, email })
  }
}
```

## Data.TaggedClass

Adds `_tag` field for discriminated unions:

```ts
class Loading extends Data.TaggedClass("Loading")<{}> {}
class Success extends Data.TaggedClass("Success")<{ data: string }> {}
class Failure extends Data.TaggedClass("Failure")<{ error: Error }> {}

type State = Loading | Success | Failure

const handle = (state: State) => {
  switch (state._tag) {
    case "Loading": return "Loading..."
    case "Success": return state.data
    case "Failure": return state.error.message
  }
}
```

## Data.TaggedEnum

Concise discriminated unions with constructors, type guards, and pattern matching:

```ts
import { Data } from "effect"

type HttpError = Data.TaggedEnum<{
  BadRequest: { message: string }
  NotFound: { resource: string }
  ServerError: { reason: string }
}>

const { BadRequest, NotFound, ServerError, $is, $match } =
  Data.taggedEnum<HttpError>()

// Create instances
const err = BadRequest({ message: "Invalid input" })

// Type guards
$is("BadRequest")(err)  // true

// Pattern matching
const getMessage = $match({
  BadRequest: ({ message }) => `Bad request: ${message}`,
  NotFound: ({ resource }) => `Not found: ${resource}`,
  ServerError: ({ reason }) => `Server error: ${reason}`,
})
```

Generic TaggedEnums:

```ts
type Result<E, A> = Data.TaggedEnum<{
  Success: { value: A }
  Failure: { error: E }
}>

interface ResultDefinition extends Data.TaggedEnum.WithGenerics<2> {
  readonly taggedEnum: Result<this["A"], this["B"]>
}

const { Success, Failure } = Data.taggedEnum<ResultDefinition>()
```

## Data.struct / Data.tuple

Ad-hoc immutable data without classes:

```ts
import { Data, Equal } from "effect"

const point1 = Data.struct({ x: 10, y: 20 })
const point2 = Data.struct({ x: 10, y: 20 })
Equal.equals(point1, point2)  // true

const coords = Data.tuple(10, 20, 30)
const items = Data.array([1, 2, 3])
```

## Exit

`Exit<A, E>` represents effect outcome — either `Success<A>` or `Failure<Cause<E>>`:

```ts
import { Effect, Exit, Cause } from "effect"

const exit = Effect.runSyncExit(Effect.succeed(42))

if (Exit.isSuccess(exit)) {
  console.log(exit.value)
} else {
  console.log(Cause.pretty(exit.cause))
}

// Creating
Exit.succeed(42)
Exit.fail("error")
Exit.die(new Error("bug"))
```

## Cause

`Cause<E>` represents everything that can go wrong:

| Tag | Description | When it occurs |
|-----|-------------|----------------|
| `Empty` | No error | One side of parallel succeeded |
| `Fail<E>` | Expected failure | `Effect.fail` |
| `Die` | Unexpected defect | `throw`, `Effect.die` |
| `Interrupt` | Fiber interrupted | `Effect.interrupt`, timeout |
| `Sequential<E>` | Multiple sequential errors | Error during finalization |
| `Parallel<E>` | Multiple parallel errors | Multiple fibers failed |

```ts
import { Cause } from "effect"

Cause.fail("error")              // expected failure
Cause.die(new Error("bug"))      // unexpected defect
Cause.interrupt(FiberId.none)    // interruption

// Inspecting
Cause.failureOption(cause)       // Option<E>
Cause.failures(cause)            // Chunk<E>
Cause.defects(cause)             // Chunk<unknown>
Cause.isInterrupted(cause)
Cause.pretty(cause)              // human-readable string
```

Handling defects with `catchAllCause`:

```ts
const handled = riskyEffect.pipe(
  Effect.catchAllCause((cause) => {
    if (Cause.isDie(cause)) {
      return Effect.succeed("caught defect")
    }
    return Effect.fail("other error")
  })
)
```

## When to Use Each

| Type | Use Case |
|------|----------|
| `Option` | Value may or may not exist |
| `Either` | Sync operation with typed error |
| `Data.Class` | Immutable domain objects |
| `Data.TaggedEnum` | Discriminated unions |
| `Exit` | Inspect effect result without throwing |
| `Cause` | Full error info including defects/interruption |
