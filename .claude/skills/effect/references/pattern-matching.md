# Pattern Matching

Effect's `Match` module brings exhaustive pattern matching to TypeScript. It replaces verbose if/else chains or switch statements with a structured, type-safe API that ensures all cases are handled at compile time.

## Match.type, Match.value

There are two ways to create a matcher: by type or by value.

### Match.type - Create a Matcher Function

`Match.type<T>()` creates a reusable matcher function for a given type:

```typescript
import { Match } from "effect"

type Status = "pending" | "active" | "completed"

// Create a matcher function
const getStatusLabel = Match.type<Status>().pipe(
  Match.when("pending", () => "Waiting to start"),
  Match.when("active", () => "In progress"),
  Match.when("completed", () => "Done"),
  Match.exhaustive
)

// Use the matcher
getStatusLabel("pending")    // "Waiting to start"
getStatusLabel("active")     // "In progress"
getStatusLabel("completed")  // "Done"
```

### Match.value - Match a Specific Value

`Match.value(x)` creates a matcher for a known value, returning the result directly:

```typescript
import { Match } from "effect"

const input: string | number = "hello"

// Match against a specific value
const result = Match.value(input).pipe(
  Match.when(Match.string, (s) => `String: ${s}`),
  Match.when(Match.number, (n) => `Number: ${n}`),
  Match.exhaustive
)
// result: "String: hello"
```

### Built-in Type Predicates

Match provides predicates for common types:

```typescript
import { Match } from "effect"

const describe = Match.type<unknown>().pipe(
  Match.when(Match.string, (s) => `string: ${s}`),
  Match.when(Match.number, (n) => `number: ${n}`),
  Match.when(Match.boolean, (b) => `boolean: ${b}`),
  Match.when(Match.bigint, (n) => `bigint: ${n}`),
  Match.when(Match.symbol, () => `symbol`),
  Match.when(Match.null, () => `null`),
  Match.when(Match.undefined, () => `undefined`),
  Match.when(Match.date, (d) => `date: ${d.toISOString()}`),
  Match.when(Match.record, (r) => `object with keys`),
  Match.orElse(() => "something else")
)
```

Additional predicates:

```typescript
import { Match } from "effect"

// Match non-empty strings
Match.when(Match.nonEmptyString, (s) => `non-empty: ${s}`)

// Match specific literal values
Match.when(Match.is("a", "b", "c"), (v) => `one of: ${v}`)

// Match any value (catch-all before orElse)
Match.when(Match.any, (v) => `anything: ${v}`)

// Match defined (non-null, non-undefined) values
Match.when(Match.defined, (v) => `defined: ${v}`)

// Match class instances
Match.when(Match.instanceOf(Error), (e) => `error: ${e.message}`)
```

## Match.tag for Discriminated Unions

`Match.tag` matches on the `_tag` field of discriminated unions, which is the Effect ecosystem convention for tagged types.

### Basic Tag Matching

```typescript
import { Match } from "effect"

type Event =
  | { readonly _tag: "UserCreated"; readonly userId: string }
  | { readonly _tag: "UserDeleted"; readonly userId: string }
  | { readonly _tag: "UserUpdated"; readonly userId: string; readonly changes: object }

const handleEvent = Match.type<Event>().pipe(
  Match.tag("UserCreated", (e) => `Created user ${e.userId}`),
  Match.tag("UserDeleted", (e) => `Deleted user ${e.userId}`),
  Match.tag("UserUpdated", (e) => `Updated user ${e.userId}`),
  Match.exhaustive
)

handleEvent({ _tag: "UserCreated", userId: "123" })
// "Created user 123"
```

### Matching Multiple Tags

A single `Match.tag` can handle multiple variants:

```typescript
import { Match } from "effect"

type Result =
  | { readonly _tag: "Success"; readonly data: string }
  | { readonly _tag: "Cached"; readonly data: string }
  | { readonly _tag: "Error"; readonly error: Error }

const getMessage = Match.type<Result>().pipe(
  // Handle both Success and Cached the same way
  Match.tag("Success", "Cached", (r) => `Data: ${r.data}`),
  Match.tag("Error", (r) => `Error: ${r.error.message}`),
  Match.exhaustive
)
```

### Match.tags - Object Syntax

For concise exhaustive matching, use `Match.tags` with an object:

```typescript
import { Match, pipe } from "effect"

type Shape =
  | { readonly _tag: "Circle"; readonly radius: number }
  | { readonly _tag: "Rectangle"; readonly width: number; readonly height: number }
  | { readonly _tag: "Triangle"; readonly base: number; readonly height: number }

const area = pipe(
  Match.type<Shape>(),
  Match.tags({
    Circle: ({ radius }) => Math.PI * radius ** 2,
    Rectangle: ({ width, height }) => width * height,
    Triangle: ({ base, height }) => (base * height) / 2
  }),
  Match.exhaustive
)

area({ _tag: "Circle", radius: 5 })  // ~78.54
```

### Match.tagsExhaustive - Exhaustive Object Syntax

`Match.tagsExhaustive` requires handlers for all tags and doesn't need `Match.exhaustive`:

```typescript
import { Match, pipe } from "effect"

type Status =
  | { readonly _tag: "Idle" }
  | { readonly _tag: "Loading" }
  | { readonly _tag: "Error"; readonly message: string }
  | { readonly _tag: "Success"; readonly data: unknown }

const statusToNumber = pipe(
  Match.type<Status>(),
  Match.tagsExhaustive({
    Idle: () => 0,
    Loading: () => 1,
    Error: () => -1,
    Success: () => 2
  })
)
// No Match.exhaustive needed - compiler ensures all tags are covered
```

### Match.tagStartsWith - Hierarchical Tags

Match tags by prefix for hierarchical naming:

```typescript
import { Match, pipe } from "effect"

type ApiEvent =
  | { readonly _tag: "User.Created" }
  | { readonly _tag: "User.Updated" }
  | { readonly _tag: "User.Deleted" }
  | { readonly _tag: "Order.Created" }
  | { readonly _tag: "Order.Shipped" }

const getCategory = pipe(
  Match.type<ApiEvent>(),
  Match.tagStartsWith("User", () => "user-event"),
  Match.tagStartsWith("Order", () => "order-event"),
  Match.exhaustive
)
```

### Custom Discriminator Fields

Use `Match.discriminator` for fields other than `_tag`:

```typescript
import { Match, pipe } from "effect"

type Action =
  | { readonly type: "INCREMENT"; readonly amount: number }
  | { readonly type: "DECREMENT"; readonly amount: number }
  | { readonly type: "RESET" }

const handleAction = pipe(
  Match.type<Action>(),
  Match.discriminator("type")("INCREMENT", (a) => `+${a.amount}`),
  Match.discriminator("type")("DECREMENT", (a) => `-${a.amount}`),
  Match.discriminator("type")("RESET", () => "reset"),
  Match.exhaustive
)
```

Or use `Match.discriminatorsExhaustive` for object syntax:

```typescript
import { Match, pipe } from "effect"

type Action =
  | { readonly type: "INCREMENT"; readonly amount: number }
  | { readonly type: "DECREMENT"; readonly amount: number }
  | { readonly type: "RESET" }

const handleAction = pipe(
  Match.type<Action>(),
  Match.discriminatorsExhaustive("type")({
    INCREMENT: (a) => `+${a.amount}`,
    DECREMENT: (a) => `-${a.amount}`,
    RESET: () => "reset"
  })
)
```

## Pattern Conditions with Match.when

`Match.when` matches values using predicates, literals, or object patterns.

### Literal Values

```typescript
import { Match } from "effect"

const httpStatus = Match.type<number>().pipe(
  Match.when(200, () => "OK"),
  Match.when(201, () => "Created"),
  Match.when(404, () => "Not Found"),
  Match.when(500, () => "Server Error"),
  Match.orElse((status) => `Unknown: ${status}`)
)
```

### Predicate Functions

```typescript
import { Match } from "effect"

const classify = Match.type<number>().pipe(
  Match.when((n) => n < 0, () => "negative"),
  Match.when((n) => n === 0, () => "zero"),
  Match.when((n) => n > 0, () => "positive"),
  Match.exhaustive
)
```

### Object Patterns

Match nested object properties:

```typescript
import { Match } from "effect"

type User = {
  readonly name: string
  readonly age: number
  readonly role: "admin" | "user"
}

const describeUser = Match.type<User>().pipe(
  // Match by property value
  Match.when({ role: "admin" }, (u) => `Admin: ${u.name}`),
  // Match with predicate
  Match.when({ age: (a) => a >= 18 }, (u) => `Adult: ${u.name}`),
  Match.orElse((u) => `Minor: ${u.name}`)
)

describeUser({ name: "Alice", age: 25, role: "admin" })  // "Admin: Alice"
describeUser({ name: "Bob", age: 20, role: "user" })     // "Adult: Bob"
describeUser({ name: "Charlie", age: 15, role: "user" }) // "Minor: Charlie"
```

### Deeply Nested Patterns

```typescript
import { Match } from "effect"

type Response = {
  readonly data: {
    readonly user: {
      readonly status: "active" | "inactive"
    }
  }
}

const checkStatus = Match.type<Response>().pipe(
  Match.when(
    { data: { user: { status: "active" } } },
    () => "User is active"
  ),
  Match.when(
    { data: { user: { status: "inactive" } } },
    () => "User is inactive"
  ),
  Match.exhaustive
)
```

### Match.whenOr - Multiple Patterns

Match any of several patterns:

```typescript
import { Match } from "effect"

type Error =
  | { readonly _tag: "NetworkError" }
  | { readonly _tag: "TimeoutError" }
  | { readonly _tag: "ValidationError"; readonly field: string }

const shouldRetry = Match.type<Error>().pipe(
  Match.whenOr(
    { _tag: "NetworkError" },
    { _tag: "TimeoutError" },
    () => true  // Retry network and timeout errors
  ),
  Match.when({ _tag: "ValidationError" }, () => false),
  Match.exhaustive
)
```

### Match.whenAnd - All Patterns Must Match

```typescript
import { Match } from "effect"

type Request = {
  readonly authenticated: boolean
  readonly role: "admin" | "user"
  readonly age: number
}

const canAccess = Match.type<Request>().pipe(
  Match.whenAnd(
    { authenticated: true },
    { role: "admin" },
    () => "Full access"
  ),
  Match.whenAnd(
    { authenticated: true },
    { age: (a) => a >= 18 },
    () => "Adult access"
  ),
  Match.orElse(() => "No access")
)
```

### Match.not - Negative Matching

```typescript
import { Match } from "effect"

const greet = Match.type<string | number>().pipe(
  Match.not("goodbye", (v) => `Hello, ${v}!`),
  Match.orElse(() => "Farewell!")
)

greet("world")    // "Hello, world!"
greet("goodbye")  // "Farewell!"
```

## Completion Functions

Every matcher must end with a completion function that determines how unmatched cases are handled.

### Match.exhaustive - Require All Cases

TypeScript will error if any case is unhandled:

```typescript
import { Match } from "effect"

type Color = "red" | "green" | "blue"

const toHex = Match.type<Color>().pipe(
  Match.when("red", () => "#ff0000"),
  Match.when("green", () => "#00ff00"),
  // Missing "blue" - TypeScript error!
  Match.exhaustive
)
```

### Match.orElse - Provide Fallback

Handle unmatched cases with a fallback:

```typescript
import { Match } from "effect"

const toHex = Match.type<string>().pipe(
  Match.when("red", () => "#ff0000"),
  Match.when("green", () => "#00ff00"),
  Match.when("blue", () => "#0000ff"),
  Match.orElse((color) => `unknown color: ${color}`)
)

toHex("red")     // "#ff0000"
toHex("yellow")  // "unknown color: yellow"
```

### Match.orElseAbsurd - Throw on Unmatched

Throws if no pattern matches (use when you believe all cases are covered):

```typescript
import { Match } from "effect"

type KnownStatus = 200 | 404 | 500

const statusName = Match.type<KnownStatus>().pipe(
  Match.when(200, () => "OK"),
  Match.when(404, () => "Not Found"),
  Match.when(500, () => "Server Error"),
  Match.orElseAbsurd  // Throws if somehow a different value arrives
)
```

### Match.option - Wrap in Option

Returns `Option.some(result)` if matched, `Option.none()` otherwise:

```typescript
import { Match, Option } from "effect"

const maybeHex = Match.type<string>().pipe(
  Match.when("red", () => "#ff0000"),
  Match.when("green", () => "#00ff00"),
  Match.option
)

maybeHex("red")     // Some("#ff0000")
maybeHex("yellow")  // None
```

### Match.either - Wrap in Either

Returns `Either.right(result)` if matched, `Either.left(unmatchedValue)` otherwise:

```typescript
import { Match, Either } from "effect"

const parseColor = Match.type<string>().pipe(
  Match.when("red", () => "#ff0000"),
  Match.when("green", () => "#00ff00"),
  Match.either
)

parseColor("red")     // Right("#ff0000")
parseColor("yellow")  // Left("yellow")
```

## Return Type Enforcement

Use `Match.withReturnType` to ensure all branches return the same type:

```typescript
import { Match } from "effect"

type Input = { a: number } | { b: string }

const process = Match.type<Input>().pipe(
  Match.withReturnType<string>(),  // Must be first!
  Match.when({ a: Match.number }, ({ a }) => `number: ${a}`),
  Match.when({ b: Match.string }, ({ b }) => b),
  Match.exhaustive
)
```

## Shorthand Functions

### Match.valueTags - Direct Value Matching

For matching a value against tags without building a matcher:

```typescript
import { Match, pipe } from "effect"

type Response =
  | { readonly _tag: "Success"; readonly data: string }
  | { readonly _tag: "Error"; readonly message: string }

const response: Response = { _tag: "Success", data: "hello" }

const result = pipe(
  response,
  Match.valueTags({
    Success: ({ data }) => `Got: ${data}`,
    Error: ({ message }) => `Error: ${message}`
  })
)
// "Got: hello"

// Or non-pipe style:
Match.valueTags(response, {
  Success: ({ data }) => `Got: ${data}`,
  Error: ({ message }) => `Error: ${message}`
})
```

### Match.typeTags - Create Type Matcher

Similar shorthand for type-based matching:

```typescript
import { Match } from "effect"

type Action =
  | { readonly _tag: "Add"; readonly value: number }
  | { readonly _tag: "Remove"; readonly id: string }

const handleAction = Match.typeTags<Action>()({
  Add: ({ value }) => `Adding ${value}`,
  Remove: ({ id }) => `Removing ${id}`
})

handleAction({ _tag: "Add", value: 42 })  // "Adding 42"
```

## Real-World Examples

### Error Handling with Match

```typescript
import { Match, Effect } from "effect"

type AiError =
  | { readonly _tag: "HttpRequestError"; readonly message: string }
  | { readonly _tag: "HttpResponseError"; readonly status: number }
  | { readonly _tag: "ParseError"; readonly details: string }
  | { readonly _tag: "RateLimitError"; readonly retryAfter: number }

const handleAiError = Match.type<AiError>().pipe(
  Match.tag("HttpRequestError", (err) =>
    Effect.logError(`Request failed: ${err.message}`)
  ),
  Match.tag("HttpResponseError", (err) =>
    Effect.logError(`Response error: ${err.status}`)
  ),
  Match.tag("ParseError", (err) =>
    Effect.logError(`Parse error: ${err.details}`)
  ),
  Match.tag("RateLimitError", (err) =>
    Effect.logWarning(`Rate limited, retry in ${err.retryAfter}s`)
  ),
  Match.exhaustive
)
```

### State Machine Transitions

```typescript
import { Match } from "effect"

type State =
  | { readonly _tag: "Idle" }
  | { readonly _tag: "Loading"; readonly startedAt: number }
  | { readonly _tag: "Success"; readonly data: unknown }
  | { readonly _tag: "Error"; readonly error: Error }

type Event =
  | { readonly _tag: "Fetch" }
  | { readonly _tag: "FetchSuccess"; readonly data: unknown }
  | { readonly _tag: "FetchError"; readonly error: Error }
  | { readonly _tag: "Reset" }

const transition = (state: State, event: Event): State =>
  Match.value(state).pipe(
    Match.when({ _tag: "Idle" }, () =>
      Match.value(event).pipe(
        Match.tag("Fetch", () => ({ _tag: "Loading" as const, startedAt: Date.now() })),
        Match.orElse(() => state)
      )
    ),
    Match.when({ _tag: "Loading" }, () =>
      Match.value(event).pipe(
        Match.tag("FetchSuccess", (e) => ({ _tag: "Success" as const, data: e.data })),
        Match.tag("FetchError", (e) => ({ _tag: "Error" as const, error: e.error })),
        Match.orElse(() => state)
      )
    ),
    Match.whenOr({ _tag: "Success" }, { _tag: "Error" }, () =>
      Match.value(event).pipe(
        Match.tag("Reset", () => ({ _tag: "Idle" as const })),
        Match.orElse(() => state)
      )
    ),
    Match.exhaustive
  )
```

### API Response Handling

```typescript
import { Match, pipe } from "effect"

type ApiResponse<T> =
  | { readonly _tag: "Success"; readonly data: T; readonly cached: boolean }
  | { readonly _tag: "NotFound"; readonly resource: string }
  | { readonly _tag: "Unauthorized"; readonly reason: string }
  | { readonly _tag: "ServerError"; readonly code: number }

const handleResponse = <T>(response: ApiResponse<T>) =>
  pipe(
    Match.value(response),
    Match.tags({
      Success: ({ data, cached }) =>
        cached ? `Cached: ${JSON.stringify(data)}` : `Fresh: ${JSON.stringify(data)}`,
      NotFound: ({ resource }) => `Resource not found: ${resource}`,
      Unauthorized: ({ reason }) => `Access denied: ${reason}`,
      ServerError: ({ code }) => `Server error ${code}`
    }),
    Match.exhaustive
  )
```
